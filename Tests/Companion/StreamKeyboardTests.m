#import <XCTest/XCTest.h>
#import "TrunklineStreamKeyboard.h"
#import <Limelight.h>
#import "KeyboardSupport.h"
#import "AbsoluteTouchHandler.h"
#import "RelativeTouchHandler.h"
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
@end
@implementation PointerRecordingView
- (void)emitPointerX:(short)x y:(short)y width:(short)width height:(short)height {
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
@interface FixtureStreamTouchEvent : UIEvent
@property(nonatomic, strong) NSSet<UITouch *> *touchSet;
@end
@implementation FixtureStreamTouchEvent
- (NSSet<UITouch *> *)allTouches { return self.touchSet; }
@end

@interface FixtureHardwareKey : UIKey
@property(nonatomic) UIKeyboardHIDUsage usage;
@end
@implementation FixtureHardwareKey
- (UIKeyboardHIDUsage)keyCode { return self.usage; }
- (UIKeyModifierFlags)modifierFlags { return 0; }
- (NSString *)characters { return @""; }
- (NSString *)charactersIgnoringModifiers { return @""; }
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

- (void)testUnknownHardwareUsageReturnsToUIKitWithoutCrashing {
    FixtureHardwareKey *key = [FixtureHardwareKey new];
    for (NSNumber *usage in @[@0, @65535]) {
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
        XCTAssertEqualObjects(toolbar.items.lastObject.accessibilityLabel, @"Hide keyboard");
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
