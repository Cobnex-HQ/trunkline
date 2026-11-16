#import "TrunklineStream.h"
#import "TrunklineStreamKeyboard.h"
#import "Moonlight-Swift.h"
#import "PairManager.h"
#import "StreamFrameViewController.h"
#import "CryptoManager.h"
#import "ServerInfoResponse.h"
#import "AppListResponse.h"
#import "TemporaryApp.h"
#import "DataManager.h"
#import <VideoToolbox/VideoToolbox.h>
#import <Limelight.h>
#define SDL_MAIN_HANDLED
#import <SDL.h>

// Bind the pending Sunshine request to a random token carried separately in
// the authenticated companion channel, without changing the vendor sources.
@interface TrunklinePairingHttpManager : HttpManager
@property(nonatomic, copy) NSString *pairingName;
- (void)cancelPendingRequests;
@end
@implementation TrunklinePairingHttpManager {
    NSMutableSet<NSURLSession *> *_sessions;
    BOOL _stopped;
}
- (void)cancelPendingRequests {
    NSArray<NSURLSession *> *sessions;
    @synchronized (self) { _stopped = YES; sessions = _sessions.allObjects; }
    for (NSURLSession *session in sessions) [session invalidateAndCancel];
}
// Preserve the pinned engine's request/fallback semantics and inherited TLS
// challenge handler, while owning session lifetime so Cancel stops network I/O.
- (void)executeRequestSynchronously:(HttpRequest *)request {
    NSURLSession *session;
    NSURLSessionDataTask *task;
    __block NSData *responseData;
    __block NSError *responseError;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    @synchronized (self) {
        if (_stopped) {
            request.response.statusCode = NSURLErrorCancelled;
            request.response.statusMessage = @"Desktop request cancelled.";
            return;
        }
        if (!request.request) {
            request.response.statusCode = EHOSTDOWN;
            request.response.statusMessage = @"Trunkline Desktop is unreachable.";
            return;
        }
        session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration delegate:self delegateQueue:nil];
        task = [session dataTaskWithRequest:request.request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            responseData = data; responseError = error;
            dispatch_semaphore_signal(finished);
        }];
        if (!_sessions) _sessions = [NSMutableSet new];
        [_sessions addObject:session];
    }
    [task resume];
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
    [session invalidateAndCancel];
    @synchronized (self) {
        [_sessions removeObject:session];
        if (_stopped) {
            request.response.statusCode = NSURLErrorCancelled;
            request.response.statusMessage = @"Desktop request cancelled.";
            return;
        }
    }
    if (!responseError) {
        NSString *xml = responseData ? [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] : nil;
        if (xml) {
            xml = [xml stringByReplacingOccurrencesOfString:@"UTF-16" withString:@"UTF-8" options:NSCaseInsensitiveSearch range:NSMakeRange(0, xml.length)];
            responseData = [xml dataUsingEncoding:NSUTF8StringEncoding];
        }
        [request.response populateWithData:responseData];
    } else {
        request.response.statusCode = responseError.code;
        request.response.statusMessage = responseError.localizedDescription;
    }
    // Fallback is supplied only by the engine's server-information request.
    // Certificate failures on app listing/launch never downgrade to HTTP.
    if (request.fallbackRequest && ((!responseError && request.response.statusCode == request.fallbackError) ||
                                   responseError.code == NSURLErrorServerCertificateUntrusted)) {
        request.request = request.fallbackRequest;
        request.fallbackRequest = nil; request.fallbackError = 0;
        [self executeRequestSynchronously:request];
    }
}
- (NSURLRequest *)newPairRequest:(NSData *)salt clientCert:(NSData *)clientCert {
    NSMutableURLRequest *request = [[super newPairRequest:salt clientCert:clientCert] mutableCopy];
    NSURLComponents *url = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    for (NSURLQueryItem *item in url.queryItems) {
        [items addObject:[item.name isEqualToString:@"devicename"] ? [NSURLQueryItem queryItemWithName:@"devicename" value:self.pairingName] : item];
    }
    url.queryItems = items; request.URL = url.URL;
    return request;
}
@end

@interface ElephantStreamController : StreamFrameViewController
@property(nonatomic, copy) void (^onClose)(void);
@property(nonatomic, copy) void (^workspaceAction)(NSString *);
@property(nonatomic, strong) TrunklineViewportCoordinator *viewport;
- (void)showKeyboard;
- (void)changeZoom:(CGFloat)factor;
@end

@interface TrunklineStream () <PairCallback>
@end

@implementation TrunklineStream {
    NSOperationQueue *_queue;
    TemporaryHost *_host;
    TrunklinePairingHttpManager *_manager;
    TrunklinePairingHttpManager *_loadingManager;
    NSUInteger _loadGeneration;
    PairManager *_pairing;
    BOOL _cancelled;
}
- (instancetype)init {
    if ((self = [super init])) {
        // SwiftUI owns main(), so Moonlight's excluded main.m cannot prepare SDL.
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SDL_SetMainReady(); });
        _pairingToken = NSUUID.UUID.UUIDString;
        _queue = [NSOperationQueue new]; _queue.maxConcurrentOperationCount = 1;
    }
    return self;
}
- (void)loadHost:(NSString *)address certificate:(NSData *)certificate completion:(void (^)(NSArray<NSDictionary<NSString *, NSString *> *> * _Nullable, NSString * _Nullable))completion {
    NSUInteger generation;
    TrunklinePairingHttpManager *previous;
    @synchronized (self) {
        if (_cancelled) return;
        generation = ++_loadGeneration;
        previous = _loadingManager; _loadingManager = nil;
    }
    [previous cancelPendingRequests];
    [_manager cancelPendingRequests]; _manager = nil; _host = nil;
    [_queue cancelAllOperations];
    [_queue addOperationWithBlock:^{
        [CryptoManager generateKeyPairUsingSSL];
        TemporaryHost *host = [TemporaryHost new];
        host.activeAddress = address; host.serverCert = certificate;
        TrunklinePairingHttpManager *manager = [[TrunklinePairingHttpManager alloc] initWithHost:host];
        manager.pairingName = [@"Trunkline-" stringByAppendingString:self.pairingToken];
        @synchronized (self) {
            if (self->_cancelled || self->_loadGeneration != generation) return;
            self->_loadingManager = manager;
        }
        ServerInfoResponse *info = [ServerInfoResponse new];
        [manager executeRequestSynchronously:[HttpRequest requestForResponse:info withUrlRequest:[manager newHttpServerInfoRequest]]];
        if (![info isStatusOk]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!self->_cancelled && self->_loadGeneration == generation) {
                    self->_loadingManager = nil;
                    completion(nil, info.statusMessage ?: @"Trunkline Desktop is unreachable. Start Desktop on the Mac.");
                }
            });
            return;
        }
        [info populateHost:host];
        // Discovery is unauthenticated. Application listing and launch require the paired certificate.
        if (!certificate) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (!self->_cancelled && self->_loadGeneration == generation) {
                self->_loadingManager = nil; self->_host = host; self->_manager = manager; completion(@[], nil);
            } });
            return;
        }
        AppListResponse *list = [AppListResponse new];
        [manager executeRequestSynchronously:[HttpRequest requestForResponse:list withUrlRequest:[manager newAppListRequest]]];
        NSMutableArray *apps = [NSMutableArray new];
        if ([list isStatusOk]) for (TemporaryApp *app in [list getAppList]) {
            if (app.id && app.name) [apps addObject:@{@"id":app.id, @"name":app.name}];
        }
        [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"name"] localizedStandardCompare:b[@"name"]]; }];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self->_cancelled && self->_loadGeneration == generation) {
                self->_loadingManager = nil; self->_host = host; self->_manager = manager;
                NSString *error = nil;
                if (![list isStatusOk]) {
                    error = list.statusCode == 401 || list.statusCode == 403 ? @"Desktop pairing is no longer accepted. Check paired devices in Trunkline on your Mac."
                        : list.statusMessage ?: @"Could not load the desktop. Check the connection and retry.";
                }
                completion([list isStatusOk] ? apps : nil, error);
            }
        });
    }];
}
- (void)pair {
    if (!_manager || _pairing || _cancelled) return;
    _pairing = [[PairManager alloc] initWithManager:_manager clientCert:[CryptoManager readCertFromFile] callback:self];
    [_queue addOperation:_pairing];
}
- (void)startPairing:(NSString *)PIN { dispatch_async(dispatch_get_main_queue(), ^{ if (!self->_cancelled && self.pairingCode) self.pairingCode(PIN); }); }
- (void)pairSuccessful:(NSData *)serverCert {
    dispatch_async(dispatch_get_main_queue(), ^{ self->_pairing = nil; if (!self->_cancelled && self.paired) self.paired(serverCert); });
}
- (void)pairFailed:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{ self->_pairing = nil; if (!self->_cancelled && self.failed) self.failed(message); });
}
- (void)alreadyPaired { [self pairFailed:@"This device is already paired with Trunkline Desktop, but its certificate is missing here. Remove the old client on the Mac and pair again."]; }
- (StreamConfiguration *)configurationForApp:(NSString *)appID title:(NSString *)title width:(int)width height:(int)height fps:(int)fps bitrate:(int)bitrate directTouch:(BOOL)directTouch framePacing:(BOOL)framePacing stats:(BOOL)stats {
    if (!_host.serverCert || _cancelled || !_host.httpsPort) return nil;
    [[DataManager new] saveSettingsWithBitrate:bitrate framerate:fps height:height width:width audioConfig:2 onscreenControls:OnScreenControlsLevelOff optimizeGames:NO multiController:YES swapABXYButtons:NO audioOnPC:NO preferredCodec:CODEC_PREF_AUTO useFramePacing:framePacing enableHdr:NO btMouseSupport:NO absoluteTouchMode:directTouch statsOverlay:stats];
    StreamConfiguration *config = [StreamConfiguration new];
    config.host = _host.activeAddress; config.httpsPort = _host.httpsPort;
    config.appID = appID; config.appName = title; config.serverCert = _host.serverCert;
    config.width = width; config.height = height; config.frameRate = fps; config.bitRate = bitrate;
    config.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
    config.supportedVideoFormats = VIDEO_FORMAT_H264;
    if (VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) config.supportedVideoFormats |= VIDEO_FORMAT_H265;
    if (@available(iOS 16.0, *)) { if (VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)) config.supportedVideoFormats |= VIDEO_FORMAT_AV1_MAIN8; }
    config.serverCodecModeSupport = _host.serverCodecModeSupport;
    config.multiController = YES; config.gamepadMask = [ControllerSupport getConnectedGamepadMask:config];
    config.useFramePacing = framePacing; config.playAudioOnPC = NO; config.optimizeGameSettings = NO;
    return config;
}
- (UIViewController *)streamControllerWithConfig:(StreamConfiguration *)config close:(void (^)(void))close workspaceAction:(void (^)(NSString *))workspaceAction {
    ElephantStreamController *controller = [ElephantStreamController new];
    controller.streamConfig = config; controller.onClose = close; controller.workspaceAction = workspaceAction; return controller;
}
- (void)showKeyboardInController:(UIViewController *)controller {
    if ([controller isKindOfClass:ElephantStreamController.class]) [(ElephantStreamController *)controller showKeyboard];
}
- (void)changeZoomInController:(UIViewController *)controller factor:(CGFloat)factor {
    if ([controller isKindOfClass:ElephantStreamController.class]) [(ElephantStreamController *)controller changeZoom:factor];
}
- (void)updateDisplayInController:(UIViewController *)controller width:(int)width height:(int)height {
    if ([controller isKindOfClass:ElephantStreamController.class] && width > 0 && height > 0) {
        [((ElephantStreamController *)controller).viewport setDisplayAspect:(CGFloat)width / height];
    }
}
- (void)resetZoomInController:(UIViewController *)controller {
    if ([controller isKindOfClass:ElephantStreamController.class]) [(ElephantStreamController *)controller changeZoom:0];
}
- (void)sendKey:(unsigned short)key modifiers:(unsigned char)modifiers {
    // Sunshine synthesizes Shift/Control/Alt, but Meta requires an explicit key event.
    const unsigned short keys[] = {0xA0, 0xA2, 0xA4, 0x5B};
    const unsigned char flags[] = {MODIFIER_SHIFT, MODIFIER_CTRL, MODIFIER_ALT, MODIFIER_META};
    unsigned char held = 0;
    for (int index = 0; index < 4; index++) if (modifiers & flags[index]) {
        held |= flags[index]; LiSendKeyboardEvent(0x8000 | keys[index], KEY_ACTION_DOWN, held);
    }
    LiSendKeyboardEvent(0x8000 | key, KEY_ACTION_DOWN, modifiers);
    LiSendKeyboardEvent(0x8000 | key, KEY_ACTION_UP, modifiers);
    for (int index = 3; index >= 0; index--) if (modifiers & flags[index]) {
        held &= ~flags[index]; LiSendKeyboardEvent(0x8000 | keys[index], KEY_ACTION_UP, held);
    }
}
- (void)sendText:(NSString *)text {
    NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (bytes.length > 0 && bytes.length <= 65536) LiSendUtf8TextEvent(bytes.bytes, (unsigned int)bytes.length);
}
- (void)cancel {
    TrunklinePairingHttpManager *loading;
    @synchronized (self) { _cancelled = YES; ++_loadGeneration; loading = _loadingManager; _loadingManager = nil; }
    [loading cancelPendingRequests]; [_manager cancelPendingRequests];
    [_pairing cancel]; [_queue cancelAllOperations]; self.pairingCode = nil; self.paired = nil; self.failed = nil;
}
@end

@interface StreamFrameViewController (ElephantLifecycle)
- (void)returnToMainFrame;
@end
@implementation ElephantStreamController
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    if ([controller isKindOfClass:UIAlertController.class]) {
        UIAlertController *alert = (UIAlertController *)controller;
        alert.title = [[alert.title stringByReplacingOccurrencesOfString:@"Moonlight" withString:@"Trunkline Stream"] stringByReplacingOccurrencesOfString:@"Sunshine" withString:@"Trunkline Desktop"];
        alert.message = [[alert.message stringByReplacingOccurrencesOfString:@"Moonlight" withString:@"Trunkline Stream"] stringByReplacingOccurrencesOfString:@"Sunshine" withString:@"Trunkline Desktop"];
    }
    [super presentViewController:controller animated:animated completion:completion];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    UIView *content = nil; UIScrollView *scroll = nil;
    for (UIView *view in self.view.subviews) {
        if ([view isKindOfClass:UIScrollView.class]) {
            scroll = (UIScrollView *)view;
            for (UIView *child in view.subviews) if ([child isKindOfClass:StreamView.class]) content = child;
        } else if ([view isKindOfClass:StreamView.class]) content = view;
    }
    if (!scroll && content) {
        scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
        [content removeFromSuperview]; [scroll addSubview:content];
        [self.view insertSubview:scroll atIndex:0]; scroll.delegate = self;
    }
    if (scroll && content) {
        CGFloat aspect = (CGFloat)self.streamConfig.width / MAX(1, self.streamConfig.height);
        self.viewport = [[TrunklineViewportCoordinator alloc] initWithScroll:scroll content:content aspect:aspect];
        self.viewport.workspaceAction = self.workspaceAction;
    }
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.viewport layoutInBounds:self.view.bounds];
}
- (void)changeZoom:(CGFloat)factor {
    [self.viewport changeZoom:factor];
}
- (void)willMoveToParentViewController:(UIViewController *)parent {
    if (!parent) { [super returnToMainFrame]; self.onClose = nil; self.workspaceAction = nil; self.viewport.workspaceAction = nil; }
    [super willMoveToParentViewController:parent];
}
- (void)returnToMainFrame { [super returnToMainFrame]; if (self.onClose) self.onClose(); }
- (void)showKeyboard {
    // Use the stream's complete keyboard lifecycle, including handlers and dismissal.
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:self.view];
    while (views.count) {
        UIView *view = views.lastObject; [views removeLastObject];
        if ([view isKindOfClass:StreamView.class]) { [(StreamView *)view toggleSoftwareKeyboard]; return; }
        [views addObjectsFromArray:view.subviews];
    }
}
@end
