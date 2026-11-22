#import <XCTest/XCTest.h>
#import "TrunklineStreamKeyboard.h"
#import <Limelight.h>
#import "KeyboardSupport.h"
#import "AbsoluteTouchHandler.h"
#import "RelativeTouchHandler.h"
#import <CoreData/CoreData.h>

// Test-facing declaration avoids importing the app target’s generated model headers.
@protocol TrunklineSettingsFixture <NSObject>
- (void)saveSettingsWithBitrate:(NSInteger)bitrate framerate:(NSInteger)fps height:(NSInteger)height width:(NSInteger)width audioConfig:(NSInteger)audio onscreenControls:(NSInteger)controls optimizeGames:(BOOL)optimize multiController:(BOOL)multi swapABXYButtons:(BOOL)swap audioOnPC:(BOOL)audioPC preferredCodec:(uint32_t)codec useFramePacing:(BOOL)pacing enableHdr:(BOOL)hdr btMouseSupport:(BOOL)mouse absoluteTouchMode:(BOOL)direct statsOverlay:(BOOL)stats;
- (NSObject *)getSettings;
@end
#import "VideoDecoderRenderer.h"
#import "Moonlight-Swift.h"
#import <AVFoundation/AVFoundation.h>

// Exercise the actual renderer's display-link scheduling without a network
// connection or submitting synthetic video to the decoder.
@interface TrackingVideoRenderer : VideoDecoderRenderer
@property(nonatomic) NSUInteger ticks;
@end
@implementation TrackingVideoRenderer
- (void)displayLinkCallback:(CADisplayLink *)link { self.ticks += 1; }
@end

@interface VideoDecoderRenderer (GeometryFixture)
- (void)reinitializeDisplayLayer;
@end

@interface PointerRecordingView : StreamView
@property(nonatomic) CGPoint packetPoint;
@property(nonatomic) CGSize packetSize;
@property(nonatomic) NSUInteger pointerEvents;
@end
@implementation PointerRecordingView
- (void)emitPointerX:(short)x y:(short)y width:(short)width height:(short)height {
    self.pointerEvents += 1;
    self.packetPoint = CGPointMake(x, y);
    // The wire protocol transmits inclusive coordinate maxima (width/height minus one).
    self.packetSize = CGSizeMake(width - 1, height - 1);
}
@end

@interface RecordingStreamView : StreamView
@property(nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *events;
@property(nonatomic, strong) NSMutableArray<NSString *> *texts;
@end
@implementation RecordingStreamView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) { _events = [NSMutableArray new]; _texts = [NSMutableArray new]; }
    return self;
}
- (void)emitKeyboardKey:(unsigned short)key action:(unsigned char)action modifiers:(unsigned char)modifiers flags:(unsigned char)flags {
    [self.events addObject:@[@(key), @(action), @(modifiers), @(flags)]];
}
- (void)emitKeyboardText:(NSString *)text { [self.texts addObject:text]; }
- (void)updateCursorLocation:(CGPoint)location isMouse:(BOOL)isMouse {}
@end

@interface StreamView (LifetimeFixture)
- (void)startInteractionTimer;
@end

// UITouch.view is strongly held by UIKit. Preserve that ownership in the fixture.
@interface FixtureStreamTouch : UITouch
@property(nonatomic, strong) UIView *targetView;
@end
@implementation FixtureStreamTouch
- (UIView *)view { return self.targetView; }
- (NSTimeInterval)timestamp { return 1; }
- (CGPoint)locationInView:(UIView *)view { return CGPointMake(100, 100); }
@end
@interface PositionedStreamTouch : FixtureStreamTouch
@property(nonatomic) CGPoint point;
@property(nonatomic) NSTimeInterval time;
@end
@implementation PositionedStreamTouch
- (NSTimeInterval)timestamp { return self.time; }
- (CGPoint)locationInView:(UIView *)view { return self.point; }
@end
@interface FixtureStreamTouchEvent : UIEvent
@property(nonatomic, strong) NSSet<UITouch *> *touchSet;
@end
@implementation FixtureStreamTouchEvent
- (NSSet<UITouch *> *)allTouches { return self.touchSet; }
@end

@interface AbsoluteTouchHandler (GestureFixture)
- (void)emitMouseButtonAction:(char)action button:(int)button;
- (void)onSingleTouchReady:(NSTimer *)timer;
- (void)onLongPressStart:(NSTimer *)timer;
@end
@interface RecordingAbsoluteTouchHandler : AbsoluteTouchHandler
@property(nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *buttonEvents;
@end
@implementation RecordingAbsoluteTouchHandler
- (instancetype)initWithView:(StreamView *)view {
    if ((self = [super initWithView:view])) { _buttonEvents = [NSMutableArray new]; }
    return self;
}
- (void)emitMouseButtonAction:(char)action button:(int)button {
    [self.buttonEvents addObject:@[@(action), @(button)]];
}
@end

@interface FixtureHardwareKey : UIKey
@property(nonatomic) UIKeyboardHIDUsage usage;
@property(nonatomic) UIKeyModifierFlags flags;
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSString *plain;
@end
@implementation FixtureHardwareKey
- (UIKeyboardHIDUsage)keyCode { return self.usage; }
- (UIKeyModifierFlags)modifierFlags { return self.flags; }
- (NSString *)characters { return self.text ?: @""; }
- (NSString *)charactersIgnoringModifiers { return self.plain ?: self.text ?: @""; }
@end

@interface FixtureHardwarePress : UIPress
@property(nonatomic, strong) UIKey *fixtureKey;
@end
@implementation FixtureHardwarePress
- (UIKey *)key { return self.fixtureKey; }
@end

@interface UITextField (HardwareRoutingFixture)
- (NSSet<UIPress *> *)unhandledHardwarePresses:(NSSet<UIPress *> *)presses down:(BOOL)down;
@end

@interface FixtureStreamOwner : NSObject <UserInteractionDelegate, ControllerSupportDelegate>
@property(nonatomic, strong) StreamView *view;
@property(nonatomic, strong) ControllerSupport *controllers;
@end
@implementation FixtureStreamOwner
- (void)userInteractionBegan {}
- (void)userInteractionEnded {}
- (void)gamepadPresenceChanged {}
- (void)mousePresenceChanged {}
- (void)streamExitRequested {}
@end

@interface StreamKeyboardTests : XCTestCase
@end
@implementation StreamKeyboardTests
- (void)testFirstStreamSettingsSavePreservesDirectTouchForTheViewer {
    // A fresh installation has no Settings row. Use the shipped Core Data model
    // and its real validation rules, with only disk storage replaced by memory.
    NSManagedObjectModel *model = [NSManagedObjectModel mergedModelFromBundles:nil];
    NSPersistentStoreCoordinator *store = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSError *error = nil;
    XCTAssertNotNil([store addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:&error]);
    NSManagedObjectContext *(^context)(void) = ^{
        NSManagedObjectContext *value = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        value.persistentStoreCoordinator = store;
        return value;
    };
    NSObject<TrunklineSettingsFixture> *writer = [NSClassFromString(@"DataManager") new];
    [writer setValue:context() forKey:@"managedObjectContext"];
    [writer saveSettingsWithBitrate:20000 framerate:60 height:982 width:1512
        audioConfig:2 onscreenControls:0 optimizeGames:NO multiController:YES
        swapABXYButtons:NO audioOnPC:NO preferredCodec:0 useFramePacing:NO
        enableHdr:NO btMouseSupport:NO absoluteTouchMode:YES statsOverlay:NO];
    NSObject<TrunklineSettingsFixture> *reader = [NSClassFromString(@"DataManager") new];
    [reader setValue:context() forKey:@"managedObjectContext"];
    NSObject *saved = [reader getSettings];
    XCTAssertTrue([[saved valueForKey:@"absoluteTouchMode"] boolValue], @"The viewer must not fall back to trackpad mode after saving direct touch");
    XCTAssertEqualObjects([saved valueForKey:@"width"], @1512);
    XCTAssertEqualObjects([saved valueForKey:@"height"], @982);
    XCTAssertGreaterThan([[saved valueForKey:@"uniqueId"] length], 0U);
}

- (void)testPinchDoesNotEmitPointerOrClickWhenFingersArriveSeparately {
    PointerRecordingView *view = [[PointerRecordingView alloc] initWithFrame:CGRectMake(0, 0, 1000, 1000)];
    StreamConfiguration *config = [StreamConfiguration new]; config.width = 1000; config.height = 1000;
    [view setupStreamView:nil interactionDelegate:nil config:config];
    RecordingAbsoluteTouchHandler *handler = [[RecordingAbsoluteTouchHandler alloc] initWithView:view];
    PositionedStreamTouch *first = [PositionedStreamTouch new]; first.targetView = view; first.point = CGPointMake(200, 200);
    PositionedStreamTouch *second = [PositionedStreamTouch new]; second.targetView = view; second.point = CGPointMake(700, 700);
    FixtureStreamTouchEvent *event = [FixtureStreamTouchEvent new];
    event.touchSet = [NSSet setWithObject:first];
    [handler touchesBegan:event.touchSet withEvent:event];
    XCTAssertEqual(view.pointerEvents, 0U, @"The first finger may still be the start of a pinch");
    first.point = CGPointMake(205, 205);
    [handler touchesMoved:event.touchSet withEvent:event];
    event.touchSet = [NSSet setWithObjects:first, second, nil];
    [handler touchesBegan:[NSSet setWithObject:second] withEvent:event];
    [handler touchesMoved:event.touchSet withEvent:event];
    [handler touchesCancelled:event.touchSet withEvent:event];
    // A late lift or move from the remaining finger must not turn back into input.
    event.touchSet = [NSSet setWithObject:first];
    [handler touchesMoved:event.touchSet withEvent:event];
    [handler touchesEnded:event.touchSet withEvent:event];
    XCTAssertEqual(view.pointerEvents, 0U);
    XCTAssertEqual(handler.buttonEvents.count, 0U);
}

- (void)testDirectTouchTapDragAndLongPressKeepDistinctButtonSequences {
    PointerRecordingView *view = [[PointerRecordingView alloc] initWithFrame:CGRectMake(0, 0, 1000, 1000)];
    StreamConfiguration *config = [StreamConfiguration new]; config.width = 1000; config.height = 1000;
    [view setupStreamView:nil interactionDelegate:nil config:config];
    RecordingAbsoluteTouchHandler *handler = [[RecordingAbsoluteTouchHandler alloc] initWithView:view];
    PositionedStreamTouch *touch = [PositionedStreamTouch new]; touch.targetView = view; touch.point = CGPointMake(200, 200);
    FixtureStreamTouchEvent *event = [FixtureStreamTouchEvent new]; event.touchSet = [NSSet setWithObject:touch];
    [handler touchesBegan:event.touchSet withEvent:event];
    [handler touchesEnded:event.touchSet withEvent:event];
    XCTAssertEqualObjects(handler.buttonEvents, (@[@[@(BUTTON_ACTION_PRESS), @(BUTTON_LEFT)], @[@(BUTTON_ACTION_RELEASE), @(BUTTON_LEFT)]]));
    [handler.buttonEvents removeAllObjects];
    [handler touchesBegan:event.touchSet withEvent:event];
    touch.point = CGPointMake(400, 400);
    [handler touchesMoved:event.touchSet withEvent:event];
    XCTAssertEqual(handler.buttonEvents.count, 0U);
    [handler onSingleTouchReady:nil];
    XCTAssertEqualObjects(handler.buttonEvents, (@[@[@(BUTTON_ACTION_PRESS), @(BUTTON_LEFT)]]));
    touch.point = CGPointMake(600, 600);
    [handler touchesEnded:event.touchSet withEvent:event];
    XCTAssertEqualWithAccuracy(view.packetPoint.x / view.packetSize.width, 0.6, 0.0001);
    XCTAssertEqualObjects(handler.buttonEvents.lastObject, (@[@(BUTTON_ACTION_RELEASE), @(BUTTON_LEFT)]));
    [handler.buttonEvents removeAllObjects];
    [handler touchesBegan:event.touchSet withEvent:event];
    [handler onLongPressStart:nil];
    [handler touchesEnded:event.touchSet withEvent:event];
    XCTAssertEqualObjects(handler.buttonEvents, (@[@[@(BUTTON_ACTION_PRESS), @(BUTTON_RIGHT)], @[@(BUTTON_ACTION_RELEASE), @(BUTTON_RIGHT)]]));
    // Cancellation releases an established drag exactly once, without another tap.
    [handler.buttonEvents removeAllObjects];
    [handler touchesBegan:event.touchSet withEvent:event];
    [handler onSingleTouchReady:nil];
    touch.point = CGPointMake(700, 700);
    [handler touchesMoved:event.touchSet withEvent:event];
    [handler touchesCancelled:event.touchSet withEvent:event];
    [handler touchesEnded:event.touchSet withEvent:event];
    XCTAssertEqualObjects(handler.buttonEvents, (@[@[@(BUTTON_ACTION_PRESS), @(BUTTON_LEFT)], @[@(BUTTON_ACTION_RELEASE), @(BUTTON_LEFT)]]));
}

- (void)testSecondFingerCancelsPendingRelativeDrag {
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, 800)];
    RelativeTouchHandler *handler = [[RelativeTouchHandler alloc] initWithView:(StreamView *)view];
    FixtureStreamTouch *first = [FixtureStreamTouch new]; first.targetView = view;
    FixtureStreamTouch *second = [FixtureStreamTouch new]; second.targetView = view;
    FixtureStreamTouchEvent *event = [FixtureStreamTouchEvent new]; event.touchSet = [NSSet setWithObject:first];
    [handler touchesBegan:event.touchSet withEvent:event];
    event.touchSet = [NSSet setWithObjects:first, second, nil];
    [handler touchesBegan:[NSSet setWithObject:second] withEvent:event];
    XCTAssertNil([handler valueForKey:@"dragTimer"], @"A pinch must not inherit the first finger's drag timer");
    [handler touchesCancelled:event.touchSet withEvent:event];
}

- (void)testDirectTouchMovesToEveryTapEvenNearThePreviousTap {
    PointerRecordingView *view = [[PointerRecordingView alloc] initWithFrame:CGRectMake(0, 0, 1000, 1000)];
    StreamConfiguration *config = [StreamConfiguration new]; config.width = 1000; config.height = 1000;
    [view setupStreamView:nil interactionDelegate:nil config:config];
    AbsoluteTouchHandler *handler = [[AbsoluteTouchHandler alloc] initWithView:view];
    PositionedStreamTouch *touch = [PositionedStreamTouch new]; touch.targetView = view;
    touch.point = CGPointMake(500, 500); touch.time = 10;
    FixtureStreamTouchEvent *event = [FixtureStreamTouchEvent new]; event.touchSet = [NSSet setWithObject:touch];
    [handler touchesBegan:event.touchSet withEvent:event];
    [handler touchesEnded:event.touchSet withEvent:event];
    touch.point = CGPointMake(510, 510); touch.time = 10.1;
    [handler touchesBegan:event.touchSet withEvent:event];
    [handler touchesEnded:event.touchSet withEvent:event];
    XCTAssertEqualWithAccuracy(view.packetPoint.x / view.packetSize.width, 0.51, 0.0001);
    XCTAssertEqualWithAccuracy(view.packetPoint.y / view.packetSize.height, 0.51, 0.0001);
}

- (void)testDirectTouchSendsTheFinalFingerPositionBeforeEndingADrag {
    PointerRecordingView *view = [[PointerRecordingView alloc] initWithFrame:CGRectMake(0, 0, 1000, 1000)];
    StreamConfiguration *config = [StreamConfiguration new]; config.width = 1000; config.height = 1000;
    [view setupStreamView:nil interactionDelegate:nil config:config];
    AbsoluteTouchHandler *handler = [[AbsoluteTouchHandler alloc] initWithView:view];
    PositionedStreamTouch *touch = [PositionedStreamTouch new]; touch.targetView = view;
    touch.point = CGPointMake(500, 500); touch.time = 10;
    FixtureStreamTouchEvent *event = [FixtureStreamTouchEvent new]; event.touchSet = [NSSet setWithObject:touch];
    [handler touchesBegan:event.touchSet withEvent:event];
    touch.point = CGPointMake(540, 560); touch.time = 10.1;
    [handler touchesEnded:event.touchSet withEvent:event];
    XCTAssertEqualWithAccuracy(view.packetPoint.x / view.packetSize.width, 0.54, 0.0001);
    XCTAssertEqualWithAccuracy(view.packetPoint.y / view.packetSize.height, 0.56, 0.0001);
}

- (void)testRealStreamViewMapsRenderedTargetsToWireCoordinatesAcrossViewportSizes {
    NSArray<NSValue *> *sizes = @[[NSValue valueWithCGSize:CGSizeMake(390, 700)],
        [NSValue valueWithCGSize:CGSizeMake(800, 350)], [NSValue valueWithCGSize:CGSizeMake(1024, 1240)],
        [NSValue valueWithCGSize:CGSizeMake(1240, 900)]];
    for (NSValue *sizeValue in sizes) {
        CGSize size = sizeValue.CGSizeValue;
        UIView *root = [[UIView alloc] initWithFrame:(CGRect){CGPointZero, size}];
        UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:root.bounds];
        PointerRecordingView *view = [[PointerRecordingView alloc] initWithFrame:root.bounds];
        StreamConfiguration *config = [StreamConfiguration new]; config.width = 1280; config.height = 830;
        [view setupStreamView:nil interactionDelegate:nil config:config];
        [root addSubview:scroll]; [scroll addSubview:view];
        VideoDecoderRenderer *renderer = [[VideoDecoderRenderer alloc] initWithView:view callbacks:nil
            streamAspectRatio:(float)config.width/config.height useFramePacing:NO];
        TrunklineViewportCoordinator *viewport = [[TrunklineViewportCoordinator alloc] initWithScroll:scroll content:view aspect:(CGFloat)config.width/config.height];
        [viewport layoutInBounds:root.bounds];
        for (NSNumber *sourceAspect in @[@((double)1280/830), @(16.0/9), @(9.0/16), @(21.0/9)]) {
            [viewport setDisplayAspect:sourceAspect.doubleValue];
            [renderer reinitializeDisplayLayer]; // Decoder recovery must retain the selected monitor geometry.
            AVSampleBufferDisplayLayer *layer = [renderer valueForKey:@"displayLayer"];
            CGRect picture = [TrunklineViewport videoRectInSize:layer.bounds.size aspect:sourceAspect.doubleValue];
            XCTAssertEqualWithAccuracy(picture.size.width/picture.size.height, sourceAspect.doubleValue, 0.00001);
            for (NSNumber *zoom in @[@1, @2, @3]) {
                scroll.zoomScale = zoom.doubleValue;
                scroll.contentOffset = CGPointMake((zoom.doubleValue-1)*size.width/2, (zoom.doubleValue-1)*size.height/2);
                for (NSNumber *fraction in @[@0.4, @0.5, @0.6]) {
                    CGPoint imagePoint = CGPointMake(picture.origin.x + picture.size.width*fraction.doubleValue,
                                                    picture.origin.y + picture.size.height*fraction.doubleValue);
                    CGPoint screenPoint = [layer convertPoint:imagePoint toLayer:root.layer];
                    CGPoint touch = [view convertPoint:screenPoint fromView:root];
                    [view updateCursorLocation:touch isMouse:NO];
                    XCTAssertEqualWithAccuracy(view.packetPoint.x/view.packetSize.width, imagePoint.x/layer.bounds.size.width, 0.0001);
                    XCTAssertEqualWithAccuracy(view.packetPoint.y/view.packetSize.height, imagePoint.y/layer.bounds.size.height, 0.0001);
                }
            }
        }
        [renderer stop];
    }
}

- (void)testVideoDisplayLinkContinuesDuringUIKitTrackingAndStopsOnClose {
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 390, 600)];
    TrackingVideoRenderer *renderer = [[TrackingVideoRenderer alloc] initWithView:view callbacks:nil streamAspectRatio:16.0/9.0 useFramePacing:YES];
    [renderer setupWithVideoFormat:VIDEO_FORMAT_H264 width:1280 height:720 frameRate:60];
    void (^runMode)(NSRunLoopMode) = ^(NSRunLoopMode mode) {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.35];
        while (deadline.timeIntervalSinceNow > 0) {
            [[NSRunLoop mainRunLoop] runMode:mode beforeDate:deadline];
        }
    };
    // Wait for a real callback rather than assuming a cold simulator produces
    // its first frame within 350 ms. Stop checks retain an observation window.
    void (^waitForTick)(NSRunLoopMode) = ^(NSRunLoopMode mode) {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
        while (renderer.ticks == 0 && deadline.timeIntervalSinceNow > 0) {
            [[NSRunLoop mainRunLoop] runMode:mode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    };
    [renderer start];
    waitForTick(NSDefaultRunLoopMode);
    XCTAssertGreaterThan(renderer.ticks, 0u, @"The native display link must be active before testing tracking mode");
    renderer.ticks = 0;
    waitForTick(UITrackingRunLoopMode);
    XCTAssertGreaterThan(renderer.ticks, 0u, @"Video display work must continue while UIKit tracks a gesture");
    [renderer stop];
    renderer.ticks = 0;
    runMode(UITrackingRunLoopMode);
    runMode(NSDefaultRunLoopMode);
    XCTAssertEqual(renderer.ticks, 0u, @"Closing the stream must stop display callbacks in both modes");
}
- (void)testFinishedDirectTouchDoesNotRetainTheViewerForDoubleTapHistory {
    __weak StreamView *released = nil;
    AbsoluteTouchHandler *handler;
    @autoreleasepool {
        RecordingStreamView *view = [[RecordingStreamView alloc] initWithFrame:CGRectMake(0, 0, 390, 600)];
        released = view;
        handler = [[AbsoluteTouchHandler alloc] initWithView:view];
        FixtureStreamTouch *touch = [FixtureStreamTouch new]; touch.targetView = view;
        FixtureStreamTouchEvent *event = [FixtureStreamTouchEvent new]; event.touchSet = [NSSet setWithObject:touch];
        [handler touchesBegan:event.touchSet withEvent:event];
        [handler touchesEnded:event.touchSet withEvent:event];
    }
    XCTAssertNil(released, @"Double-tap history must store scalar position/time, not a UITouch retaining the view");
    XCTAssertNotNil(handler);
}
- (void)testInteractionTimerDoesNotKeepAClosedViewerAlive {
    __weak StreamView *released = nil;
    @autoreleasepool {
        StreamView *view = [self streamView]; released = view;
        [view startInteractionTimer];
    }
    XCTAssertNil(released, @"A pending interaction timer must not retain a dismissed viewer");
}
- (void)testClosingStreamViewReleasesItsPendingTouchHandlerImmediately {
    __weak StreamView *releasedView = nil;
    __weak UIResponder *releasedHandler = nil;
    @autoreleasepool {
        StreamView *view = [self streamView]; releasedView = view;
        // Inspect ownership of the real selected handler without replacing it.
        releasedHandler = [view valueForKey:@"touchHandler"];
        XCTAssertNotNil(releasedHandler);
        FixtureStreamTouch *touch = [FixtureStreamTouch new]; touch.targetView = view;
        FixtureStreamTouchEvent *event = [FixtureStreamTouchEvent new]; event.touchSet = [NSSet setWithObject:touch];
        [view touchesBegan:event.touchSet withEvent:event];
    }
    XCTAssertNil(releasedView);
    XCTAssertNil(releasedHandler, @"A dismissed viewer must cancel its delayed touch work rather than waiting for a timer to fire");
}
- (void)testInputDelegateOwnerAndAutomaticOverlayReleaseAfterControllerCleanup {
    __weak FixtureStreamOwner *releasedOwner = nil;
    __weak ControllerSupport *releasedControllers = nil;
    @autoreleasepool {
        FixtureStreamOwner *owner = [FixtureStreamOwner new];
        releasedOwner = owner;
        StreamConfiguration *config = [StreamConfiguration new]; config.width = 1280; config.height = 720;
        owner.controllers = [[ControllerSupport alloc] initWithConfig:config delegate:owner];
        releasedControllers = owner.controllers;
        owner.view = [[StreamView alloc] initWithFrame:CGRectMake(0, 0, 390, 600)];
        [owner.view setupStreamView:owner.controllers interactionDelegate:owner config:config];
        OnScreenControls *overlay = [[OnScreenControls alloc] initWithView:owner.view controllerSup:owner.controllers streamConfig:config];
        [owner.controllers initAutoOnScreenControlMode:overlay];
        [owner.controllers cleanup];
    }
    XCTAssertNil(releasedOwner, @"Input delegates are callbacks, not owners of the viewer");
    XCTAssertNil(releasedControllers, @"Controller cleanup must release notification observers and overlay cycles");
}
- (void)testBothTouchModesAndOverlayDoNotOwnTheirInputView {
    StreamConfiguration *config = [StreamConfiguration new]; config.width = 1280; config.height = 720;
    NSMutableArray *helpers = [NSMutableArray new];
    __weak StreamView *released = nil;
    @autoreleasepool {
        StreamView *view = [[StreamView alloc] initWithFrame:CGRectMake(0, 0, 390, 600)];
        released = view;
        [helpers addObject:[[AbsoluteTouchHandler alloc] initWithView:view]];
        [helpers addObject:[[RelativeTouchHandler alloc] initWithView:view]];
        [helpers addObject:[[OnScreenControls alloc] initWithView:view controllerSup:nil streamConfig:config]];
    }
    XCTAssertNil(released, @"Input helpers must not own their parent view even while callbacks retain the helper");
    XCTAssertEqual(helpers.count, 3u);
}
- (void)testUnusedStreamInputViewsAreReleasedAfterTheirOwnerCloses {
    NSHashTable<StreamView *> *views = [NSHashTable weakObjectsHashTable];
    for (NSUInteger attempt = 0; attempt < 5; attempt++) {
        @autoreleasepool {
            StreamView *view = [self streamView];
            [views addObject:view];
        }
    }
    XCTAssertEqual(views.allObjects.count, 0u, @"Opening and closing viewers must not retain each stream input view");
}

- (FixtureHardwarePress *)pressWithUsage:(UIKeyboardHIDUsage)usage text:(NSString *)text flags:(UIKeyModifierFlags)flags {
    FixtureHardwareKey *key = [FixtureHardwareKey new]; key.usage = usage; key.text = text; key.flags = flags;
    FixtureHardwarePress *press = [FixtureHardwarePress new]; press.fixtureKey = key;
    return press;
}
- (void)testHardwareTextUsesTheClientLayoutWithoutDuplicateKeyUps {
    RecordingStreamView *view = [self streamView];
    for (NSString *text in @[@"a", @"é", @"界"]) {
        FixtureHardwarePress *press = [self pressWithUsage:UIKeyboardHIDUsageKeyboardQ text:text flags:0];
        [view pressesBegan:[NSSet setWithObject:press] withEvent:nil];
        [view pressesEnded:[NSSet setWithObject:press] withEvent:nil];
    }
    XCTAssertEqualObjects(view.texts, (@[@"a", @"é", @"界"]));
    XCTAssertEqual(view.events.count, 0u);
}
- (void)testHardwareShortcutReleasesTheOriginalKeyAfterModifiersChange {
    RecordingStreamView *view = [self streamView];
    FixtureHardwarePress *press = [self pressWithUsage:UIKeyboardHIDUsageKeyboardQ text:@"a" flags:UIKeyModifierCommand | UIKeyModifierShift];
    [view pressesBegan:[NSSet setWithObject:press] withEvent:nil];
    FixtureHardwareKey *key = (FixtureHardwareKey *)press.key;
    key.flags = 0; key.text = @"q";
    [view pressesEnded:[NSSet setWithObject:press] withEvent:nil];
    XCTAssertEqualObjects(view.events, (@[@[@0x41, @3, @9, @0], @[@0x41, @4, @0, @0]]));
}
- (void)testHardwareCancellationReleasesKeysOnce {
    RecordingStreamView *view = [self streamView];
    FixtureHardwarePress *command = [self pressWithUsage:UIKeyboardHIDUsageKeyboardLeftGUI text:@"" flags:UIKeyModifierCommand];
    FixtureHardwarePress *letter = [self pressWithUsage:UIKeyboardHIDUsageKeyboardC text:@"c" flags:UIKeyModifierCommand];
    [view pressesBegan:[NSSet setWithObject:command] withEvent:nil];
    [view pressesBegan:[NSSet setWithObject:letter] withEvent:nil];
    [view pressesCancelled:[NSSet setWithObjects:command, letter, nil] withEvent:nil];
    XCTAssertEqual(view.events.count, 4u);
    XCTAssertEqual([view.events[2][1] intValue], KEY_ACTION_UP);
    XCTAssertEqual([view.events[3][1] intValue], KEY_ACTION_UP);
    [view pressesCancelled:[NSSet setWithObjects:command, letter, nil] withEvent:nil];
    XCTAssertEqual(view.events.count, 4u);
}
- (void)testHardwareShortcutsReachTheMacWhenTextFieldHasFocus {
    RecordingStreamView *view = [self streamView];
    UITextField *field = [self fieldInView:view];
    FixtureHardwarePress *press = [self pressWithUsage:UIKeyboardHIDUsageKeyboardC text:@"c" flags:UIKeyModifierCommand];
    [field pressesBegan:[NSSet setWithObject:press] withEvent:nil];
    [field pressesEnded:[NSSet setWithObject:press] withEvent:nil];
    XCTAssertEqualObjects(view.events, (@[@[@0x43, @3, @8, @0], @[@0x43, @4, @8, @0]]));
}
- (void)testHardwareTextFieldPreservesLayoutText {
    RecordingStreamView *view = [self streamView];
    UITextField *field = [self fieldInView:view];
    FixtureHardwarePress *press = [self pressWithUsage:UIKeyboardHIDUsageKeyboardQ text:@"a" flags:0];
    XCTAssertEqual([field unhandledHardwarePresses:[NSSet setWithObject:press] down:YES].count, 1u);
    field.text = @"0a"; [field sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqual([field unhandledHardwarePresses:[NSSet setWithObject:press] down:NO].count, 1u);
    XCTAssertEqualObjects(view.texts, (@[@"a"]));
    XCTAssertEqual(view.events.count, 0u);
    for (UIKeyCommand *command in view.keyCommands) XCTAssertTrue((command.modifierFlags & UIKeyModifierCommand) != 0, @"Bare keys must remain in UIKit's composition path");
}
- (void)testNumpadEnterAndNavigationRemainPhysicalKeys {
    RecordingStreamView *view = [self streamView];
    for (FixtureHardwarePress *press in @[
        [self pressWithUsage:UIKeyboardHIDUsageKeypadEnter text:@"\r" flags:0],
        [self pressWithUsage:UIKeyboardHIDUsageKeyboardLeftArrow text:UIKeyInputLeftArrow flags:UIKeyModifierAlternate]]) {
        [view pressesBegan:[NSSet setWithObject:press] withEvent:nil];
        [view pressesEnded:[NSSet setWithObject:press] withEvent:nil];
    }
    XCTAssertEqualObjects(view.events, (@[@[@0x0D, @3, @(MODIFIER_EXTENDED), @0], @[@0x0D, @4, @(MODIFIER_EXTENDED), @0],
                                        @[@0x25, @3, @(MODIFIER_ALT), @0], @[@0x25, @4, @(MODIFIER_ALT), @0]]));
    XCTAssertEqual(view.texts.count, 0u);
}
- (void)testMarkedTextKeepsHardwareNavigationInUIKit {
    RecordingStreamView *view = [self streamView];
    UITextField *field = [self fieldInView:view];
    field.selectedTextRange = [field textRangeFromPosition:field.endOfDocument toPosition:field.endOfDocument];
    [field setMarkedText:@"拼" selectedRange:NSMakeRange(1, 0)];
    XCTAssertNotNil(field.markedTextRange);
    FixtureHardwarePress *press = [self pressWithUsage:UIKeyboardHIDUsageKeyboardEscape text:@"\x1b" flags:0];
    XCTAssertEqual([field unhandledHardwarePresses:[NSSet setWithObject:press] down:YES].count, 1u);
    // Model UIKit forwarding an unconsumed event to its containing stream view.
    [view pressesBegan:[NSSet setWithObject:press] withEvent:nil];
    XCTAssertEqual([field unhandledHardwarePresses:[NSSet setWithObject:press] down:NO].count, 1u);
    XCTAssertEqual(view.events.count, 0u, @"IME candidate navigation/cancellation belongs to UIKit until committed");
}
- (void)testUnknownHardwareUsageReturnsToUIKitWithoutCrashing {
    FixtureHardwareKey *key = [FixtureHardwareKey new];
    for (NSNumber *usage in @[@0, @669, @65535]) {
        key.usage = usage.integerValue;
        XCTAssertFalse([KeyboardSupport sendKeyEvent:key down:YES]);
        XCTAssertFalse([KeyboardSupport sendKeyEvent:key down:NO]);
    }
    key.usage = UIKeyboardHIDUsageKeyboardA;
    XCTAssertTrue([KeyboardSupport sendKeyEvent:key down:YES]);
    XCTAssertTrue([KeyboardSupport sendKeyEvent:key down:NO]);
}
- (RecordingStreamView *)streamView {
    RecordingStreamView *view = [[RecordingStreamView alloc] initWithFrame:CGRectMake(0, 0, 390, 600)];
    StreamConfiguration *config = [StreamConfiguration new]; config.width = 1280; config.height = 720;
    [view setupStreamView:nil interactionDelegate:nil config:config];
    return view;
}
- (UITextField *)fieldInView:(StreamView *)view {
    for (UIView *child in view.subviews) if ([child isKindOfClass:UITextField.class]) return (UITextField *)child;
    XCTFail(@"Stream keyboard field missing"); return nil;
}
- (void)testRapidTypingEnqueuesCompleteChordsInOrder {
    RecordingStreamView *view = [self streamView]; UITextField *field = [self fieldInView:view];
    field.text = @"0aB"; [field sendActionsForControlEvents:UIControlEventEditingChanged];
    field.text = @"0c"; [field sendActionsForControlEvents:UIControlEventEditingChanged];
    NSArray *expected = @[@[@0x41, @3, @0, @1], @[@0x41, @4, @0, @1],
                          @[@0x10, @3, @1, @0], @[@0x42, @3, @1, @1], @[@0x42, @4, @1, @1], @[@0x10, @4, @0, @0],
                          @[@0x43, @3, @0, @1], @[@0x43, @4, @0, @1]];
    XCTAssertEqualObjects(view.events, expected, @"Letters and transient modifiers must never interleave or queue on unrelated threads");
    XCTAssertEqualObjects(field.text, @"0");
}
- (void)testReturnAndBackspaceEnqueueWithoutBlockingOrLeavingAKeyDown {
    RecordingStreamView *view = [self streamView]; UITextField *field = [self fieldInView:view];
    XCTAssertFalse([field.delegate textFieldShouldReturn:field]);
    field.text = @""; [field sendActionsForControlEvents:UIControlEventEditingChanged];
    NSArray *expected = @[@[@0x0D, @3, @0, @0], @[@0x0D, @4, @0, @0], @[@0x08, @3, @0, @0], @[@0x08, @4, @0, @0]];
    XCTAssertEqualObjects(view.events, expected);
}
- (void)testUnicodeIsCommittedOnceWithoutDroppingItsFirstCharacter {
    RecordingStreamView *view = [self streamView]; UITextField *field = [self fieldInView:view];
    field.text = @"0A🙂"; [field sendActionsForControlEvents:UIControlEventEditingChanged];
    field.text = @"界"; [field sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqualObjects(view.texts, (@[@"A🙂", @"界"]));
    XCTAssertEqual(view.events.count, 0u);
    XCTAssertEqualObjects(field.text, @"0");
}
- (void)testMarkedTextWaitsUntilCompositionIsCommitted {
    RecordingStreamView *view = [self streamView]; UITextField *field = [self fieldInView:view];
    field.selectedTextRange = [field textRangeFromPosition:field.endOfDocument toPosition:field.endOfDocument];
    [field setMarkedText:@"拼" selectedRange:NSMakeRange(1, 0)];
    [field sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertNotNil(field.markedTextRange);
    XCTAssertEqual(view.texts.count, 0u); XCTAssertEqual(view.events.count, 0u);
    [field unmarkText]; [field sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqualObjects(view.texts, (@[@"拼"]));
    XCTAssertEqualObjects(field.text, @"0");
}
- (void)testNativeKeyboardToggleAndModifierRelease {
    RecordingStreamView *view = [self streamView]; UITextField *field = [self fieldInView:view];
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) if ([candidate isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)candidate; break; }
    XCTAssertNotNil(scene);
    UIWindow *previous = scene.keyWindow;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    UIViewController *controller = [UIViewController new]; controller.view = view;
    window.rootViewController = controller; [window makeKeyAndVisible];
    @try {
        [view toggleSoftwareKeyboard]; XCTAssertTrue(field.isFirstResponder);
        UIToolbar *toolbar = (UIToolbar *)field.inputAccessoryView;
        XCTAssertTrue([toolbar isKindOfClass:UIToolbar.class]);
        XCTAssertFalse([[toolbar.items valueForKey:@"accessibilityLabel"] containsObject:@"Hide keyboard"]);
        UIBarButtonItem *modifiers = toolbar.items[2];
        UIButton *command = [UIButton new];
        [command addAction:(UIAction *)modifiers.menu.children[0] forControlEvents:UIControlEventTouchUpInside];
        [command sendActionsForControlEvents:UIControlEventTouchUpInside];
        UIButton *shift = [UIButton new];
        [shift addAction:(UIAction *)modifiers.menu.children[3] forControlEvents:UIControlEventTouchUpInside];
        [shift sendActionsForControlEvents:UIControlEventTouchUpInside];
        XCTAssertEqualObjects(view.events, (@[@[@0x5B, @3, @8, @0], @[@0xA0, @3, @9, @0]]));
        XCTAssertEqualObjects(modifiers.title, @"⌘ ⇧", @"Held modifiers must remain visible when the menu closes");
        XCTAssertEqualObjects(modifiers.accessibilityValue, @"Command, Shift");
        field.text = @"0A"; [field sendActionsForControlEvents:UIControlEventEditingChanged];
        XCTAssertEqualObjects([view.events subarrayWithRange:NSMakeRange(2, view.events.count - 2)], (@[@[@0x41, @3, @9, @1], @[@0x41, @4, @9, @1]]), @"A held Shift must not receive a transient release while typing an uppercase letter");
        [view toggleSoftwareKeyboard]; XCTAssertFalse(field.isFirstResponder);
        XCTAssertEqualObjects(modifiers.title, @"Modifiers");
        XCTAssertEqual(view.events.count, 6u);
        XCTAssertEqualObjects(view.events.lastObject[2], @0);
        NSSet *released = [NSSet setWithArray:@[view.events[4][0], view.events[5][0]]];
        XCTAssertEqualObjects(released, ([NSSet setWithArray:@[@0x5B, @0xA0]]));
        XCTAssertEqualObjects(view.events[4][1], @4); XCTAssertEqualObjects(view.events[5][1], @4);
        [view toggleSoftwareKeyboard]; XCTAssertTrue(field.isFirstResponder);
        XCTAssertEqual(field.inputAccessoryView, toolbar, @"Reuse the native key row when reopening");
        XCTAssertEqualObjects(field.text, @"0");
        [view toggleSoftwareKeyboard]; XCTAssertEqual(view.events.count, 6u, @"Reopening must not duplicate handlers or retain modifiers");
    } @finally { window.hidden = YES; window.rootViewController = nil; [previous makeKeyWindow]; }
}
- (void)testTypingHandlersAreReadyBeforeTheThreeFingerGesture {
    XCTAssertTrue(NSThread.isMainThread);
    StreamView *view = [[StreamView alloc] initWithFrame:CGRectMake(0, 0, 640, 480)];
    StreamConfiguration *config = [StreamConfiguration new];
    config.width = 1280; config.height = 720;
    [view setupStreamView:nil interactionDelegate:nil config:config];
    UITextField *field = nil;
    for (UIView *child in view.subviews) if ([child isKindOfClass:UITextField.class]) field = (UITextField *)child;
    XCTAssertNotNil(field);
    XCTAssertNotNil(field.delegate, @"Toolbar keyboard must handle Return without first requiring the three-finger gesture");
    field.text = @"0abc";
    [field sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqualObjects(field.text, @"0", @"Typing must be consumed and reset by the stream handler on first use");
}
@end
