#import "MacDesktopEngine.h"
#import "HttpManager.h"
#import "PairManager.h"
#import "CryptoManager.h"
#import "ServerInfoResponse.h"
#import "AppListResponse.h"
#import "TemporaryApp.h"
#import "StreamConfiguration.h"
#import "MacPairingHttp.h"
#import <VideoToolbox/VideoToolbox.h>
#import <Limelight.h>
#import <opus_multistream.h>
#include <arpa/inet.h>
#include <stdatomic.h>

@interface MacDesktopEngine () <PairCallback>
@property(atomic) BOOL cancelled;
@property(nonatomic) TrunklinePairingHttpManager *http;
@property(nonatomic) NSString *address;
@property(nonatomic) StreamConfiguration *configuration;
@property(nonatomic) BOOL away;
- (void)report:(NSString *)state error:(NSString *)error;
- (int)submit:(PDECODE_UNIT)unit;
- (int)audioSetup:(POPUS_MULTISTREAM_CONFIGURATION)config;
- (void)audioPacket:(char *)bytes length:(int)length;
- (void)audioCleanup;
@end

static MacDesktopEngine *active;
static dispatch_queue_t engineQueue;
static int videoSetup(int format, int width, int height, int rate, void *context, int flags) { return format == VIDEO_FORMAT_H264 ? 0 : -1; }
static int videoSubmit(PDECODE_UNIT unit) { @autoreleasepool { return [active submit:unit]; } }
static void started(void) { [active report:@"Streaming" error:nil]; }
static void terminated(int code) { if (!active.cancelled) [active report:@"Stopped" error:@"Desktop connection ended. Reconnect to try again."]; }
static void stageFailed(int stage, int code) { if (!active.cancelled) [active report:@"Failed" error:@"Could not establish the desktop stream. Check the host and network."]; }
static int audioInit(int config, POPUS_MULTISTREAM_CONFIGURATION opus, void *context, int flags) { return [active audioSetup:opus]; }
static void audioCleanup(void) { [active audioCleanup]; }
static void audioDecode(char *data, int length) { @autoreleasepool { [active audioPacket:data length:length]; } }

@implementation MacDesktopEngine {
    NSData *_sps;
    NSData *_pps;
    CMVideoFormatDescriptionRef _format;
    BOOL _waitingForKeyframe;
    uint64_t _submittedVideoFrames;
    BOOL _hasNetworkFrame;
    uint32_t _lastNetworkFrame;
    uint64_t _expectedFrames, _lostFrames;
    double _networkWindowStart;
    NSDictionary<NSString *, NSNumber *> *_networkSample;
    atomic_bool _startedCore;
    OpusMSDecoder *_opus;
    AVAudioEngine *_audioEngine;
    AVAudioPlayerNode *_player;
    AVAudioFormat *_audioFormat;
    int _queuedAudioFrames;
}
- (instancetype)init {
    if ((self = [super init])) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ engineQueue = dispatch_queue_create("com.trunkline.mac-stream", DISPATCH_QUEUE_SERIAL); });
        _pairingToken = NSUUID.UUID.UUIDString;
        _displayLayer = [AVSampleBufferDisplayLayer new];
        _displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        _displayLayer.backgroundColor = NSColor.blackColor.CGColor;
        _waitingForKeyframe = YES;
    }
    return self;
}
- (void)dealloc { if (_format) CFRelease(_format); }
- (void)report:(NSString *)state error:(NSString *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.cancelled && self.stateChanged) self.stateChanged(state, error);
    });
}
- (uint64_t)submittedVideoFrames { @synchronized(self) { return _submittedVideoFrames; } }
- (void)recordFrame:(uint32_t)frame time:(double)time {
    @synchronized(self) {
        uint32_t delta = frame - _lastNetworkFrame;
        if (!_hasNetworkFrame || delta > 10000) {
            _networkWindowStart = time; _expectedFrames = 1; _lostFrames = 0;
            _hasNetworkFrame = YES; _networkSample = nil;
        } else if (delta > 0) {
            _expectedFrames += delta; _lostFrames += delta - 1;
        } else { return; }
        _lastNetworkFrame = frame;
        if (time - _networkWindowStart >= 2 && _expectedFrames > 0) {
            _networkSample = @{@"time": @(time), @"loss": @((double)_lostFrames / _expectedFrames)};
            _networkWindowStart = time; _expectedFrames = 0; _lostFrames = 0;
        }
    }
}
- (NSDictionary<NSString *, NSNumber *> *)networkSample {
    @synchronized(self) {
        if (!_networkSample || self.cancelled || CACurrentMediaTime() - _networkSample[@"time"].doubleValue > 3) return nil;
        return _networkSample;
    }
}
- (void)startHost:(NSString *)host certificate:(NSData *)certificate width:(int)width height:(int)height fps:(int)fps bitrate:(int)bitrate away:(BOOL)away {
    NSAssert(NSThread.isMainThread, @"Start on the main thread");
    if (active) { [self report:@"Failed" error:@"The previous desktop connection is closing. Try again shortly."]; return; }
    active = self;
    self.address = host;
    self.away = away;
    self.cancelled = NO;
    StreamConfiguration *config = [StreamConfiguration new];
    config.host = host; config.width = width; config.height = height;
    config.frameRate = fps; config.bitRate = bitrate;
    config.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
    config.supportedVideoFormats = VIDEO_FORMAT_H264;
    config.riKey = [Utils randomBytes:16]; config.riKeyId = arc4random();
    config.playAudioOnPC = NO;
    self.configuration = config;
    [self report:@"Preparing desktop…" error:nil];
    dispatch_async(engineQueue, ^{
        if (self.cancelled) return;
        [CryptoManager generateKeyPairUsingSSL];
        if (![CryptoManager readCertFromFile].length || ![CryptoManager readP12FromFile].length || ![CryptoManager readKeyFromFile].length) {
            [self report:@"Failed" error:@"Could not prepare this Mac’s desktop identity. Check available storage and try again."];
            return;
        }
        TemporaryHost *target = [TemporaryHost new];
        target.activeAddress = host; target.serverCert = certificate;
        self.http = [[TrunklinePairingHttpManager alloc] initWithHost:target];
        self.http.pairingName = [@"Trunkline-" stringByAppendingString:self.pairingToken];
        if (self.cancelled) { [self.http cancelPendingRequests]; return; }
        if (!certificate) {
            PairManager *pair = [[PairManager alloc] initWithManager:self.http clientCert:[CryptoManager readCertFromFile] callback:self];
            [pair main];
        } else { [self launchWithCertificate:certificate]; }
    });
}
- (void)startPairing:(NSString *)pin {
    dispatch_async(dispatch_get_main_queue(), ^{ if (!self.cancelled && self.pairingCode) self.pairingCode(pin); });
}
- (void)pairSuccessful:(NSData *)certificate {
    if (self.cancelled) return;
    dispatch_async(dispatch_get_main_queue(), ^{ if (!self.cancelled && self.paired) self.paired(certificate); });
    [self.http setServerCert:certificate];
    [self launchWithCertificate:certificate];
}
- (void)pairFailed:(NSString *)message { [self report:@"Pairing failed" error:@"Desktop pairing failed. Check the host’s Desktop settings and retry."]; }
- (void)alreadyPaired { [self report:@"Pairing failed" error:@"This Mac’s saved desktop pairing is missing. Remove its old desktop pairing on the host, then try again."]; }
- (void)launchWithCertificate:(NSData *)certificate {
    if (self.cancelled) return;
    ServerInfoResponse *info = [ServerInfoResponse new];
    [self.http executeRequestSynchronously:[HttpRequest requestForResponse:info withUrlRequest:[self.http newServerInfoRequest:NO]]];
    if (self.cancelled) return;
    if (![info isStatusOk] || ![[info getStringTag:@"PairStatus"] isEqual:@"1"]) {
        [self report:@"Failed" error:@"The host did not accept this desktop pairing. Check its paired devices."]; return;
    }
    TemporaryHost *host = [TemporaryHost new];
    [info populateHost:host];
    AppListResponse *list = [AppListResponse new];
    [self.http executeRequestSynchronously:[HttpRequest requestForResponse:list withUrlRequest:[self.http newAppListRequest]]];
    TemporaryApp *desktop = nil;
    if ([list isStatusOk]) for (TemporaryApp *app in [list getAppList]) if ([app.name isEqualToString:@"Desktop"]) { desktop = app; break; }
    if (!desktop || self.cancelled) { [self report:@"Failed" error:@"The host’s Desktop service is unavailable."]; return; }
    StreamConfiguration *config = self.configuration;
    config.serverCert = certificate; config.httpsPort = host.httpsPort;
    config.appVersion = [info getStringTag:@"appversion"];
    config.gfeVersion = [info getStringTag:@"GfeVersion"];
    config.serverCodecModeSupport = host.serverCodecModeSupport;
    config.appID = desktop.id;
    NSString *verb = [[info getStringTag:@"state"] hasSuffix:@"_SERVER_BUSY"] ? @"resume" : @"launch";
    HttpResponse *launch = [HttpResponse new];
    [self.http executeRequestSynchronously:[HttpRequest requestForResponse:launch withUrlRequest:[self.http newLaunchOrResumeRequest:verb config:config]]];
    NSString *session = [launch getStringTag:@"sessionUrl0"];
    if (self.cancelled) return;
    if (![launch isStatusOk] || !session.length || !config.appVersion.length) { [self report:@"Failed" error:@"The host could not start its desktop stream."]; return; }
    SERVER_INFORMATION server;
    LiInitializeServerInformation(&server);
    server.address = [Utils addressPortStringToAddress:config.host].UTF8String;
    server.serverInfoAppVersion = config.appVersion.UTF8String;
    server.serverInfoGfeVersion = config.gfeVersion.UTF8String;
    server.rtspSessionUrl = session.UTF8String;
    server.serverCodecModeSupport = config.serverCodecModeSupport;
    STREAM_CONFIGURATION stream;
    LiInitializeStreamConfiguration(&stream);
    stream.width = config.width; stream.height = config.height; stream.fps = config.frameRate;
    stream.bitrate = config.bitRate; stream.supportedVideoFormats = VIDEO_FORMAT_H264;
    stream.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
    stream.encryptionFlags = ENCFLG_ALL;
    stream.streamingRemotely = self.away ? STREAM_CFG_REMOTE : STREAM_CFG_AUTO;
    stream.packetSize = self.away ? 1024 : 1392;
    memcpy(stream.remoteInputAesKey, config.riKey.bytes, 16);
    uint32_t keyID = htonl(config.riKeyId);
    memcpy(stream.remoteInputAesIv, &keyID, 4);
    CONNECTION_LISTENER_CALLBACKS callbacks;
    DECODER_RENDERER_CALLBACKS video;
    AUDIO_RENDERER_CALLBACKS audio;
    LiInitializeConnectionCallbacks(&callbacks);
    LiInitializeVideoCallbacks(&video);
    LiInitializeAudioCallbacks(&audio);
    callbacks.connectionStarted = started; callbacks.connectionTerminated = terminated; callbacks.stageFailed = stageFailed;
    video.setup = videoSetup; video.submitDecodeUnit = videoSubmit;
    video.capabilities = CAPABILITY_DIRECT_SUBMIT;
    audio.init = audioInit; audio.cleanup = audioCleanup; audio.decodeAndPlaySample = audioDecode;
    _startedCore = YES;
    int result = LiStartConnection(&server, &stream, &callbacks, &video, &audio, NULL, 0, NULL, 0);
    if (result != 0 && !self.cancelled) [self report:@"Failed" error:@"Desktop connection failed. Check the host and try again."];
}
- (void)stop {
    NSAssert(NSThread.isMainThread, @"Stop on the main thread");
    if (self.cancelled) return;
    self.cancelled = YES;
    [self.http cancelPendingRequests];
    if (active == self) LiInterruptConnection();
    dispatch_async(engineQueue, ^{
        if (self->_startedCore) LiStopConnection();
        [self audioCleanup];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.displayLayer.sampleBufferRenderer flush];
            if (active == self) active = nil;
        });
    });
}
+ (void)finishStopping:(void (^)(void))completion {
    NSAssert(NSThread.isMainThread, @"Stop on the main thread");
    [active stop];
    dispatch_async(engineQueue ?: dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dispatch_async(dispatch_get_main_queue(), completion);
    });
}
- (void)moveX:(double)x y:(double)y { if (!self.cancelled && _startedCore) LiSendMousePositionEvent((short)(x*32766), (short)(y*32766), 32767, 32767); }
- (void)button:(int)button down:(BOOL)down { if (!self.cancelled && _startedCore) LiSendMouseButtonEvent(down ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, button); }
- (void)key:(unsigned short)key down:(BOOL)down modifiers:(unsigned char)modifiers { if (!self.cancelled && _startedCore) LiSendKeyboardEvent(0x8000 | key, down ? KEY_ACTION_DOWN : KEY_ACTION_UP, modifiers); }
- (void)scrollX:(short)x y:(short)y {
    if (self.cancelled || !_startedCore) return;
    if (y) LiSendHighResScrollEvent(y);
    if (x) LiSendHighResHScrollEvent(x);
}

- (int)submit:(PDECODE_UNIT)unit {
    if (self.cancelled || !unit || unit->fullLength <= 0 || unit->fullLength > 8*1024*1024) return DR_NEED_IDR;
    [self recordFrame:unit->frameNumber time:CACurrentMediaTime()];
    NSMutableData *annex = [NSMutableData dataWithCapacity:unit->fullLength];
    for (PLENTRY part = unit->bufferList; part; part = part->next) {
        if (part->length <= 0 || annex.length + part->length > (NSUInteger)unit->fullLength) return DR_NEED_IDR;
        [annex appendBytes:part->data length:part->length];
    }
    const uint8_t *bytes = annex.bytes;
    NSMutableData *frame = [NSMutableData new];
    NSUInteger start = NSNotFound;
    BOOL keyframe = NO;
    for (NSUInteger i = 0; i <= annex.length; ) {
        NSUInteger prefix = 0;
        if (i + 3 <= annex.length && bytes[i] == 0 && bytes[i+1] == 0) {
            if (bytes[i+2] == 1) prefix = 3;
            else if (i+4 <= annex.length && bytes[i+2] == 0 && bytes[i+3] == 1) prefix = 4;
        }
        if (prefix || i == annex.length) {
            if (start != NSNotFound && i > start) {
                NSData *nal = [annex subdataWithRange:NSMakeRange(start, i-start)];
                int type = bytes[start] & 31;
                if (type == 7) { if (![_sps isEqual:nal]) { _sps = nal; if (_format) { CFRelease(_format); _format = NULL; } } }
                else if (type == 8) { if (![_pps isEqual:nal]) { _pps = nal; if (_format) { CFRelease(_format); _format = NULL; } } }
                else {
                    keyframe |= type == 5;
                    uint32_t length = htonl((uint32_t)nal.length);
                    [frame appendBytes:&length length:4]; [frame appendData:nal];
                }
            }
            if (i == annex.length) break;
            start = i + prefix; i = start;
        } else i++;
    }
    if (!_format && _sps.length && _pps.length) {
        const uint8_t *sets[] = {_sps.bytes, _pps.bytes};
        size_t sizes[] = {_sps.length, _pps.length};
        if (CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL, 2, sets, sizes, 4, &_format)) return DR_NEED_IDR;
        _waitingForKeyframe = YES;
    }
    AVSampleBufferVideoRenderer *renderer = self.displayLayer.sampleBufferRenderer;
    if (renderer.status == AVQueuedSampleBufferRenderingStatusFailed || !renderer.readyForMoreMediaData) {
        [renderer flush]; _waitingForKeyframe = YES;
    }
    if (!_format || !frame.length || (_waitingForKeyframe && !keyframe)) return DR_NEED_IDR;
    CMBlockBufferRef block = NULL;
    CMSampleBufferRef sample = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL, NULL, frame.length, NULL, NULL, 0, frame.length, 0, &block);
    if (!status) status = CMBlockBufferReplaceDataBytes(frame.bytes, block, 0, frame.length);
    size_t length = frame.length;
    if (!status) status = CMSampleBufferCreateReady(NULL, block, _format, 1, 0, NULL, 1, &length, &sample);
    if (!status) {
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, true);
        CFDictionarySetValue((CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0), kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
        [renderer enqueueSampleBuffer:sample];
        _waitingForKeyframe = NO;
        @synchronized(self) { _submittedVideoFrames += 1; }
    }
    if (sample) CFRelease(sample);
    if (block) CFRelease(block);
    return status ? DR_NEED_IDR : DR_OK;
}
- (int)audioSetup:(POPUS_MULTISTREAM_CONFIGURATION)config {
    if (config->channelCount != 2 || config->sampleRate != 48000) return -1;
    int error;
    _opus = opus_multistream_decoder_create(config->sampleRate, 2, config->streams, config->coupledStreams, config->mapping, &error);
    if (!_opus) return -1;
    _audioEngine = [AVAudioEngine new]; _player = [AVAudioPlayerNode new];
    _audioFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
    [_audioEngine attachNode:_player];
    [_audioEngine connect:_player to:_audioEngine.mainMixerNode format:_audioFormat];
    NSError *failure;
    if (![_audioEngine startAndReturnError:&failure]) { [self audioCleanup]; return -1; }
    [_player play];
    return 0;
}
- (void)audioPacket:(char *)bytes length:(int)length {
    if (!_opus || self.cancelled) return;
    float pcm[5760*2];
    int frames = opus_multistream_decode_float(_opus, (unsigned char *)bytes, length, pcm, 5760, 0);
    if (frames <= 0) return;
    @synchronized(self) { if (_queuedAudioFrames > 2400) return; _queuedAudioFrames += frames; }
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_audioFormat frameCapacity:frames];
    buffer.frameLength = frames;
    for (int i=0; i<frames; i++) { buffer.floatChannelData[0][i] = pcm[i*2]; buffer.floatChannelData[1][i] = pcm[i*2+1]; }
    [_player scheduleBuffer:buffer completionHandler:^{ @synchronized(self) { self->_queuedAudioFrames -= frames; } }];
}
- (void)audioCleanup {
    [_player stop]; [_audioEngine stop];
    _player = nil; _audioEngine = nil;
    if (_opus) { opus_multistream_decoder_destroy(_opus); _opus = NULL; }
}
@end
