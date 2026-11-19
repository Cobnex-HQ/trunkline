// Modified for Trunkline; adaptation notice recorded 2026-11-17.
// Based on Moonlight iOS 02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a.
// Original notices and licence are retained; see docs/THIRD_PARTY.md.
//
//  StreamManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamManager.h"
#import "CryptoManager.h"
#import "HttpManager.h"
#import "Utils.h"

#import "StreamView.h"
#import "ServerInfoResponse.h"
#import "HttpResponse.h"
#import "HttpRequest.h"
#import "IdManager.h"

#include <Limelight.h>
#include <math.h>

// The underlying C engine has process-wide state. Reserve it before any
// stream starts and keep the lease until its actual asynchronous stop finishes.
static NSUUID *desktopOwner;
BOOL TrunklineDesktopStreamAvailable(void) {
    @synchronized (StreamManager.class) { return desktopOwner == nil; }
}

@interface TrunklineOwnedConnection : Connection
- (void)terminateWithCompletion:(dispatch_block_t)completion;
@end
@implementation TrunklineOwnedConnection {
    dispatch_group_t _stopping;
}
- (void)terminate { [self terminateWithCompletion:nil]; }
- (void)terminateWithCompletion:(dispatch_block_t)completion {
    @synchronized (self) {
        if (!_stopping) {
            _stopping = dispatch_group_create();
            dispatch_group_enter(_stopping);
            LiInterruptConnection();
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                // LiStartConnection runs in this NSOperation. Wait for it to
                // return before stopping, just as the upstream init lock does.
                [self waitUntilFinished];
                LiStopConnection();
                dispatch_group_leave(self->_stopping);
            });
        }
        if (completion) dispatch_group_notify(_stopping, dispatch_get_main_queue(), completion);
    }
}
@end

@interface StreamManager ()
@property(atomic, strong) id<ConnectionCallbacks> elephantCallbacks;
@end

@implementation StreamManager {
    StreamConfiguration* _config;

    UIView* _renderView;
    TrunklineOwnedConnection* _connection;
    NSUUID *_leaseToken;
    BOOL _denied;
    BOOL _stopRequested;
}

- (id) initWithConfig:(StreamConfiguration*)config renderView:(UIView*)view connectionCallbacks:(id<ConnectionCallbacks>)callbacks {
    self = [super init];
    _leaseToken = [NSUUID UUID];
    @synchronized (StreamManager.class) {
        _denied = desktopOwner != nil;
        if (!_denied) desktopOwner = _leaseToken;
    }
    _config = config;
    _renderView = view;
    self.elephantCallbacks = callbacks;
    _config.riKey = [Utils randomBytes:16];
    _config.riKeyId = arc4random();
    return self;
}

- (void)main {
    if (self.cancelled) { return; }
    if (_denied) {
        [self.elephantCallbacks launchFailed:@"A desktop is open in another window. Close that desktop before opening this one. Other Mac sessions can stay connected."];
        return;
    }
    [CryptoManager generateKeyPairUsingSSL];
    
    HttpManager* hMan = [[HttpManager alloc] initWithAddress:_config.host httpsPort:_config.httpsPort
                                                     serverCert:_config.serverCert];
    
    ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                       fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
    NSString* pairStatus = [serverInfoResp getStringTag:@"PairStatus"];
    NSString* appversion = [serverInfoResp getStringTag:@"appversion"];
    NSString* gfeVersion = [serverInfoResp getStringTag:@"GfeVersion"];
    NSString* serverState = [serverInfoResp getStringTag:@"state"];
    if (![serverInfoResp isStatusOk]) {
        [self.elephantCallbacks launchFailed:serverInfoResp.statusMessage];
        return;
    }
    else if (pairStatus == NULL || appversion == NULL || serverState == NULL) {
        [self.elephantCallbacks launchFailed:@"Failed to connect to PC"];
        return;
    }
    
    if (![pairStatus isEqualToString:@"1"]) {
        // Not paired
        [self.elephantCallbacks launchFailed:@"Device not paired to PC"];
        return;
    }
    
    // Only perform this check on GFE (as indicated by MJOLNIR in state value)
    if ((_config.width > 4096 || _config.height > 4096) && [serverState containsString:@"MJOLNIR"]) {
        // Pascal added support for 8K HEVC encoding support. Maxwell 2 could encode HEVC but only up to 4K.
        // We can't directly identify Pascal, but we can look for HEVC Main10 which was added in the same generation.
        NSString* codecSupport = [serverInfoResp getStringTag:@"ServerCodecModeSupport"];
        if (codecSupport == nil || !([codecSupport intValue] & 0x200)) {
            [self.elephantCallbacks launchFailed:@"Your host PC's GPU doesn't support streaming video resolutions over 4K."];
            return;
        }
    }
    
    // Populate the config's version fields from serverinfo
    _config.appVersion = appversion;
    _config.gfeVersion = gfeVersion;
    
    // resumeApp and launchApp handle calling launchFailed
    NSString* sessionUrl;
    if ([serverState hasSuffix:@"_SERVER_BUSY"]) {
        // App already running, resume it
        if (![self resumeApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    } else {
        // Start app
        if (![self launchApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    }
    
    // Populate RTSP session URL from launch/resume response
    _config.rtspSessionUrl = sessionUrl;
    
    // Initializing the renderer must be done on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cancelled) { return; }
        VideoDecoderRenderer* renderer = [[VideoDecoderRenderer alloc] initWithView:self->_renderView callbacks:self.elephantCallbacks streamAspectRatio:(float)self->_config.width / (float)self->_config.height useFramePacing:self->_config.useFramePacing];
        self->_connection = [[TrunklineOwnedConnection alloc] initWithConfig:self->_config renderer:renderer connectionCallbacks:self.elephantCallbacks];
        NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
        [opQueue addOperation:self->_connection];
    });
}

- (void) stopStream
{
    [self cancel];
    // The controller owns this manager, so release its callback when ending the stream.
    // Serialize renderer/connection access with creation on the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_stopRequested) return;
        self->_stopRequested = YES;
        NSUUID *token = self->_leaseToken;
        dispatch_block_t release = ^{
            @synchronized (StreamManager.class) {
                if ([desktopOwner isEqual:token]) desktopOwner = nil;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:@"TrunklineDesktopStopped" object:nil];
        };
        if (self->_connection) [self->_connection terminateWithCompletion:release];
        else release();
        self->_connection = nil;
        self.elephantCallbacks = nil;
        self->_renderView = nil;
    });
}

- (BOOL) launchApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* launchResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:launchResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"launch" config:_config]]];
    NSString *gameSession = [launchResp getStringTag:@"gamesession"];
    if (![launchResp isStatusOk]) {
        [self.elephantCallbacks launchFailed:launchResp.statusMessage];
        Log(LOG_E, @"Failed Launch Response: %@", launchResp.statusMessage);
        return FALSE;
    } else if (gameSession == NULL || [gameSession isEqualToString:@"0"]) {
        [self.elephantCallbacks launchFailed:@"Failed to launch app"];
        Log(LOG_E, @"Failed to parse game session");
        return FALSE;
    }
    
    *sessionUrl = [launchResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (BOOL) resumeApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* resumeResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:resumeResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"resume" config:_config]]];
    NSString* resume = [resumeResp getStringTag:@"resume"];
    if (![resumeResp isStatusOk]) {
        [self.elephantCallbacks launchFailed:resumeResp.statusMessage];
        Log(LOG_E, @"Failed Resume Response: %@", resumeResp.statusMessage);
        return FALSE;
    } else if (resume == NULL || [resume isEqualToString:@"0"]) {
        [self.elephantCallbacks launchFailed:@"Failed to resume app"];
        Log(LOG_E, @"Failed to parse resume response");
        return FALSE;
    }
    
    *sessionUrl = [resumeResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (NSString*) getStatsOverlayText {
    video_stats_t stats;
    
    if (!_connection) {
        return nil;
    }
    
    if (![_connection getVideoStats:&stats]) {
        return nil;
    }

    const double interval = stats.endTime - stats.startTime;
    if (!isfinite(stats.startTime) || !isfinite(stats.endTime) || !isfinite(interval) || interval <= 0 ||
        stats.totalFrames <= 0 || stats.receivedFrames < 0 || stats.receivedFrames > stats.totalFrames ||
        stats.networkDroppedFrames < 0 || stats.networkDroppedFrames > stats.totalFrames) {
        return nil;
    }
    // The engine retains its last complete window when no new frames arrive.
    // Never leave that old healthy rate on screen during a stalled stream.
    if (CACurrentMediaTime() - stats.endTime > 3.0) {
        return @"No recent video";
    }
    
    uint32_t rtt, variance;
    NSString* latencyString;
    if (LiGetEstimatedRttInfo(&rtt, &variance)) {
        latencyString = [NSString stringWithFormat:@"%u ms · variance %u ms", rtt, variance];
    }
    else {
        latencyString = @"N/A";
    }
    
    NSString* hostProcessingString;
    if (stats.framesWithHostProcessingLatency > 0 && stats.totalHostProcessingLatency >= 0) {
        hostProcessingString = [NSString stringWithFormat:@"\nHost processing: %.1f ms avg · %.1f–%.1f ms",
                                (double)stats.totalHostProcessingLatency / stats.framesWithHostProcessingLatency / 10.0,
                                stats.minHostProcessingLatency / 10.0,
                                stats.maxHostProcessingLatency / 10.0];
    }
    else {
        hostProcessingString = @"";
    }
    
    // Away access uses a local transport bridge. Its RTT is not the remote
    // path's RTT, and neither measurement is end-to-end touch/display latency.
    NSString *host = [NSURLComponents componentsWithString:[@"http://" stringByAppendingString:_config.host ?: @""]].host.lowercaseString;
    BOOL localTransport = [host hasPrefix:@"127."] || [host isEqualToString:@"localhost"] ||
        [host isEqualToString:@"::1"] || [host isEqualToString:@"[::1]"] || [_config.host isEqualToString:@"::1"];
    return [NSString stringWithFormat:@"%d × %d · %@\nReceived: %.2f fps · Network drops: %.2f%%\n%@: %@%@",
            _config.width,
            _config.height,
            [_connection getActiveCodecName],
            stats.receivedFrames / interval,
            100.0 * stats.networkDroppedFrames / stats.totalFrames,
            localTransport ? @"Local transport RTT" : @"Transport RTT",
            latencyString,
            hostProcessingString];
}

@end
