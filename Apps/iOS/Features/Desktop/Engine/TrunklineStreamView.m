//
//  StreamView.m
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "TrunklineStreamKeyboard.h"
#import "TrunklineTouchInput.h"
#import "Moonlight-Swift.h"
#include <Limelight.h>
#import "DataManager.h"
#import "ControllerSupport.h"
#import "KeyboardSupport.h"
#import "RelativeTouchHandler.h"
#import "AbsoluteTouchHandler.h"
#import "KeyboardInputField.h"

static const double X1_MOUSE_SPEED_DIVISOR = 2.5;

@implementation StreamView {
    OnScreenControls* onScreenControls;
    
    KeyboardInputField* keyInputField;
    UIBarButtonItem *modifierMenuItem;
    NSMutableSet* keysDown;
    
    float streamAspectRatio;
    BOOL suppressDirectTouches;
    
    // iOS 13.4 mouse support
    NSInteger lastMouseButtonMask;
    float lastMouseX;
    float lastMouseY;
    CGPoint lastScrollTranslation;
    
    // Citrix X1 mouse support
    X1Mouse* x1mouse;
    double accumulatedMouseDeltaX;
    double accumulatedMouseDeltaY;
    
    UIResponder* touchHandler;
    
    __weak id<UserInteractionDelegate> interactionDelegate;
    NSTimer* interactionTimer;
    BOOL hasUserInteracted;
    
    NSDictionary<NSString *, NSNumber *> *dictCodes;
}

- (void) setupStreamView:(ControllerSupport*)controllerSupport
     interactionDelegate:(id<UserInteractionDelegate>)interactionDelegate
                  config:(StreamConfiguration*)streamConfig {
    self->interactionDelegate = interactionDelegate;
    self->streamAspectRatio = (float)streamConfig.width / (float)streamConfig.height;
    
    TemporarySettings* settings = [[[DataManager alloc] init] getSettings];
    
    keysDown = [[NSMutableSet alloc] init];
    keyInputField = [[KeyboardInputField alloc] initWithFrame:CGRectZero];
    [keyInputField setKeyboardType:UIKeyboardTypeDefault];
    [keyInputField setAutocorrectionType:UITextAutocorrectionTypeNo];
    [keyInputField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [keyInputField setSpellCheckingType:UITextSpellCheckingTypeNo];
    keyInputField.smartQuotesType = UITextSmartQuotesTypeNo;
    keyInputField.smartDashesType = UITextSmartDashesTypeNo;
    keyInputField.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
    keyInputField.delegate = self;
    keyInputField.text = @"0";
    [keyInputField addTarget:self action:@selector(onKeyboardPressed:) forControlEvents:UIControlEventEditingChanged];
    [self addSubview:keyInputField];
    
#if TARGET_OS_TV
    // tvOS requires RelativeTouchHandler to manage Apple Remote input
    self->touchHandler = [[RelativeTouchHandler alloc] initWithView:self];
#else
    // iOS uses RelativeTouchHandler or AbsoluteTouchHandler depending on user preference
    if (settings.absoluteTouchMode) {
        self->touchHandler = [[AbsoluteTouchHandler alloc] initWithView:self];
    }
    else {
        self->touchHandler = [[RelativeTouchHandler alloc] initWithView:self];
    }
    
    onScreenControls = [[OnScreenControls alloc] initWithView:self controllerSup:controllerSupport streamConfig:streamConfig];
    OnScreenControlsLevel level = (OnScreenControlsLevel)[settings.onscreenControls integerValue];
    if (settings.absoluteTouchMode) {
        Log(LOG_I, @"On-screen controls disabled in absolute touch mode");
        [onScreenControls setLevel:OnScreenControlsLevelOff];
    }
    else if (level == OnScreenControlsLevelAuto) {
        [controllerSupport initAutoOnScreenControlMode:onScreenControls];
    }
    else {
        Log(LOG_I, @"Setting manual on-screen controls level: %d", (int)level);
        [onScreenControls setLevel:level];
    }
    
    // It would be nice to just use GCMouse on iOS 14+ and the older API on iOS 13
    // but unfortunately that isn't possible today. GCMouse doesn't recognize many
    // mice correctly, but UIKit does. We will register for both and ignore UIKit
    // events if a GCMouse is connected.
    if (@available(iOS 13.4, *)) {
        [self addInteraction:[[UIPointerInteraction alloc] initWithDelegate:self]];
        
        UIPanGestureRecognizer *discreteMouseWheelRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mouseWheelMovedDiscrete:)];
        discreteMouseWheelRecognizer.maximumNumberOfTouches = 0;
        discreteMouseWheelRecognizer.allowedScrollTypesMask = UIScrollTypeMaskDiscrete;
        discreteMouseWheelRecognizer.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
        [self addGestureRecognizer:discreteMouseWheelRecognizer];
        
        UIPanGestureRecognizer *continuousMouseWheelRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mouseWheelMovedContinuous:)];
        continuousMouseWheelRecognizer.maximumNumberOfTouches = 0;
        continuousMouseWheelRecognizer.allowedScrollTypesMask = UIScrollTypeMaskContinuous;
        continuousMouseWheelRecognizer.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
        [self addGestureRecognizer:continuousMouseWheelRecognizer];
    }
    
#if defined(__IPHONE_16_1) || defined(__TVOS_16_1)
    if (@available(iOS 16.1, *)) {
        UIHoverGestureRecognizer *stylusHoverRecognizer = [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(sendStylusHoverEvent:)];
        stylusHoverRecognizer.allowedTouchTypes = @[@(UITouchTypePencil)];
        [self addGestureRecognizer:stylusHoverRecognizer];
    }
#endif
#endif
    
    x1mouse = [[X1Mouse alloc] init];
    x1mouse.delegate = self;
    
    if (settings.btMouseSupport) {
        [x1mouse start];
    }
    
    // This is critical to ensure keyboard events are delivered to this
    // StreamView and not our parent UIView, especially on tvOS.
    [self becomeFirstResponder];
}

- (void)startInteractionTimer {
    // Restart user interaction tracking
    hasUserInteracted = NO;
    
    BOOL timerAlreadyRunning = interactionTimer != nil;
    
    // Start/restart the timer
    [interactionTimer invalidate];
    __weak StreamView *weakSelf = self;
    interactionTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:NO block:^(NSTimer *timer) {
        [weakSelf interactionTimerExpired:timer];
    }];
    
    // Notify the delegate if this was a new user interaction
    if (!timerAlreadyRunning) {
        [interactionDelegate userInteractionBegan];
    }
}

- (void)dealloc {
    [interactionTimer invalidate];
    // Stop local timers without emitting remote input from a late destructor.
    [(id<TrunklineTouchInput>)touchHandler cancelPendingInput];
}

- (void)interactionTimerExpired:(NSTimer *)timer {
    if (!hasUserInteracted) {
        // User has finished touching the screen
        interactionTimer = nil;
        [interactionDelegate userInteractionEnded];
    }
    else {
        // User is still touching the screen. Restart the timer.
        [self startInteractionTimer];
    }
}

- (void) showOnScreenControls {
#if !TARGET_OS_TV
    [onScreenControls show];
#endif
}

- (OnScreenControlsLevel) getCurrentOscState {
    if (onScreenControls == nil) {
        return OnScreenControlsLevelOff;
    }
    else {
        return [onScreenControls getLevel];
    }
}

- (CGSize) getVideoAreaSize {
    return [TrunklineViewport canvasRectInView:self encodedAspect:streamAspectRatio].size;
}

- (CGPoint) adjustCoordinatesForVideoArea:(CGPoint)point {
    CGRect canvas = [TrunklineViewport canvasRectInView:self encodedAspect:streamAspectRatio];
    return CGPointMake(MIN(MAX(point.x - canvas.origin.x, 0), canvas.size.width),
                       MIN(MAX(point.y - canvas.origin.y, 0), canvas.size.height));
}

#if !TARGET_OS_TV

- (uint16_t)getRotationFromAzimuthAngle:(float)azimuthAngle {
    // iOS reports azimuth of 0 when the stylus is pointing west, but Moonlight expects
    // rotation of 0 to mean the stylus is pointing north. Rotate the azimuth angle
    // clockwise by 90 degrees to convert from iOS to Moonlight rotation conventions.
    int32_t rotationAngle = (azimuthAngle - M_PI_2) * (180.f / M_PI);
    if (rotationAngle < 0) {
        rotationAngle += 360;
    }
    return (uint16_t)rotationAngle;
}

- (uint8_t)getTiltFromAltitudeAngle:(float)altitudeAngle {
    // iOS reports an altitude of 0 when the stylus is parallel to the touch surface,
    // while Moonlight expects a tilt of 0 when the stylus is perpendicular to the surface.
    // Subtract the tilt angle from 90 to convert from iOS to Moonlight tilt conventions.
    uint8_t altitudeDegs = abs((int16_t)(altitudeAngle * (180.f / M_PI)));
    return 90 - MIN(90, altitudeDegs);
}

- (BOOL)sendStylusEvent:(UITouch*)event {
    uint8_t type;
    
    // Don't touch stylus events if the host doesn't support them. We want to pass
    // them as normal touches for legacy hosts that don't understand pen events.
    if (!(LiGetHostFeatureFlags() & LI_FF_PEN_TOUCH_EVENTS)) {
        return NO;
    }
    
    switch (event.phase) {
        case UITouchPhaseBegan:
            type = LI_TOUCH_EVENT_DOWN;
            break;
        case UITouchPhaseMoved:
            type = LI_TOUCH_EVENT_MOVE;
            break;
        case UITouchPhaseEnded:
            type = LI_TOUCH_EVENT_UP;
            break;
        case UITouchPhaseCancelled:
            type = LI_TOUCH_EVENT_CANCEL;
            break;
        default:
            return YES;
    }

    CGPoint location = [self adjustCoordinatesForVideoArea:[event locationInView:self]];
    CGSize videoSize = [self getVideoAreaSize];
    
    return LiSendPenEvent(type, LI_TOOL_TYPE_PEN, 0, location.x / videoSize.width, location.y / videoSize.height,
                          (event.force / event.maximumPossibleForce) / sin(event.altitudeAngle),
                          0.0f, 0.0f,
                          [self getRotationFromAzimuthAngle:[event azimuthAngleInView:self]],
                          [self getTiltFromAltitudeAngle:event.altitudeAngle]) != LI_ERR_UNSUPPORTED;
}

- (void)sendStylusHoverEvent:(UIHoverGestureRecognizer*)gesture API_AVAILABLE(ios(13.0)) {
    uint8_t type;
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            type = LI_TOUCH_EVENT_HOVER;
            break;

        case UIGestureRecognizerStateEnded:
            type = LI_TOUCH_EVENT_HOVER_LEAVE;
            break;

        default:
            return;
    }

    CGPoint location = [self adjustCoordinatesForVideoArea:[gesture locationInView:self]];
    CGSize videoSize = [self getVideoAreaSize];
    
    float distance = 0.0f;
#if defined(__IPHONE_16_1) || defined(__TVOS_16_1)
    if (@available(iOS 16.1, *)) {
        distance = gesture.zOffset;
    }
#endif
    
    uint16_t rotationAngle = LI_ROT_UNKNOWN;
    uint8_t tiltAngle = LI_TILT_UNKNOWN;
#if defined(__IPHONE_16_4) || defined(__TVOS_16_4)
    if (@available(iOS 16.4, *)) {
        rotationAngle = [self getRotationFromAzimuthAngle:[gesture azimuthAngleInView:self]];
        tiltAngle = [self getTiltFromAltitudeAngle:gesture.altitudeAngle];
    }
#endif
    
    LiSendPenEvent(type, LI_TOOL_TYPE_PEN, 0, location.x / videoSize.width, location.y / videoSize.height,
                   distance, 0.0f, 0.0f, rotationAngle, tiltAngle);
}

#endif

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self handleMouseButtonEvent:BUTTON_ACTION_PRESS
                          forTouches:touches
                           withEvent:event]) {
        // If it's a mouse event, we're done
        return;
    }
    
    Log(LOG_D, @"Touch down");
    
    // Notify of user interaction and start expiration timer
    [self startInteractionTimer];
    
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
    }
#endif
    
    if ([touchHandler isKindOfClass:AbsoluteTouchHandler.class] && [[event allTouches] count] > 1) {
        // A second finger belongs to local zoom/pan, never a held remote drag.
        [touchHandler touchesCancelled:[event allTouches] withEvent:event];
        suppressDirectTouches = YES;
        return;
    }
    if (suppressDirectTouches) return;
    if (![onScreenControls handleTouchDownEvent:touches]) {
        [touchHandler touchesBegan:touches withEvent:event];

    }
}

- (unsigned char)keyboardModifiers {
    unsigned char result = 0;
    if ([keysDown containsObject:@(0x5B)]) result |= MODIFIER_META;
    if ([keysDown containsObject:@(0xA0)]) result |= MODIFIER_SHIFT;
    if ([keysDown containsObject:@(0xA2)]) result |= MODIFIER_CTRL;
    if ([keysDown containsObject:@(0xA4)]) result |= MODIFIER_ALT;
    return result;
}
- (UIMenu *)keyboardModifierMenu {
    NSArray<NSString *> *titles = @[@"Command", @"Control", @"Option", @"Shift"];
    NSArray<NSString *> *symbols = @[@"command", @"control", @"option", @"shift"];
    NSArray<NSNumber *> *codes = @[@(0x5B), @(0xA2), @(0xA4), @(0xA0)];
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray new];
    __weak StreamView *weakSelf = self;
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSNumber *code = codes[i];
        UIAction *action = [UIAction actionWithTitle:titles[i] image:[UIImage systemImageNamed:symbols[i]] identifier:nil handler:^(UIAction *action) {
            StreamView *strongSelf = weakSelf;
            if (!strongSelf) return;
            BOOL release = [strongSelf->keysDown containsObject:code];
            if (release) [strongSelf->keysDown removeObject:code]; else [strongSelf->keysDown addObject:code];
            [strongSelf emitKeyboardKey:code.unsignedShortValue action:release ? KEY_ACTION_UP : KEY_ACTION_DOWN modifiers:[strongSelf keyboardModifiers] flags:0];
            [strongSelf updateKeyboardModifierMenu];
        }];
        action.state = [keysDown containsObject:code] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithChildren:actions];
}
- (void)updateKeyboardModifierMenu {
    modifierMenuItem.menu = [self keyboardModifierMenu];
    NSArray<NSNumber *> *codes = @[@(0x5B), @(0xA2), @(0xA4), @(0xA0)];
    NSArray<NSString *> *names = @[@"Command", @"Control", @"Option", @"Shift"];
    NSArray<NSString *> *symbols = @[@"⌘", @"⌃", @"⌥", @"⇧"];
    NSMutableArray<NSString *> *activeNames = [NSMutableArray new], *activeSymbols = [NSMutableArray new];
    for (NSUInteger i = 0; i < codes.count; i++) if ([keysDown containsObject:codes[i]]) {
        [activeNames addObject:names[i]]; [activeSymbols addObject:symbols[i]];
    }
    modifierMenuItem.title = activeSymbols.count ? [activeSymbols componentsJoinedByString:@" "] : @"Modifiers";
    modifierMenuItem.accessibilityValue = activeNames.count ? [activeNames componentsJoinedByString:@", "] : @"None";
}
- (UIBarButtonItem *)keyboardButton:(NSString *)title symbol:(NSString *)symbol code:(NSInteger)code {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:symbol] style:UIBarButtonItemStylePlain target:self action:@selector(keyboardButtonPressed:)];
    item.tag = code; item.accessibilityLabel = title;
    return item;
}
- (void)toggleSoftwareKeyboard {
    if (keyInputField.isFirstResponder) {
        [keyInputField resignFirstResponder];
        [self becomeFirstResponder];
        return;
    }
    keyInputField.text = @"0";
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.bounds.size.width, 44)];
    toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    modifierMenuItem = [[UIBarButtonItem alloc] initWithTitle:@"Modifiers" menu:[self keyboardModifierMenu]];
    modifierMenuItem.accessibilityLabel = @"Keyboard modifiers";
    [self updateKeyboardModifierMenu];
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    toolbar.items = @[[self keyboardButton:@"Escape" symbol:@"escape" code:0x1B],
                      [self keyboardButton:@"Tab" symbol:@"arrow.right.to.line" code:0x09],
                      modifierMenuItem,
                      [self keyboardButton:@"Forward delete" symbol:@"delete.forward" code:0x2E],
                      space,
                      [self keyboardButton:@"Hide keyboard" symbol:@"keyboard.chevron.compact.down" code:0]];
    keyInputField.inputAccessoryView = toolbar;
    [keyInputField becomeFirstResponder];
    if (keyInputField.undoManager.isUndoRegistrationEnabled) [keyInputField.undoManager disableUndoRegistration];
}
- (void)keyboardButtonPressed:(UIBarButtonItem *)sender {
    if (sender.tag == 0) { [self toggleSoftwareKeyboard]; return; }
    unsigned char modifiers = [self keyboardModifiers];
    [self emitKeyboardKey:(unsigned short)sender.tag action:KEY_ACTION_DOWN modifiers:modifiers flags:0];
    [self emitKeyboardKey:(unsigned short)sender.tag action:KEY_ACTION_UP modifiers:modifiers flags:0];
}
- (void)emitKeyboardKey:(unsigned short)key action:(unsigned char)action modifiers:(unsigned char)modifiers flags:(unsigned char)flags {
    // The core queues reliable keyboard packets in order; no UI-thread sleep is needed.
    LiSendKeyboardEvent2(0x8000 | key, action, modifiers, flags);
}
- (void)emitKeyboardText:(NSString *)text {
    NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (bytes.length > 0 && bytes.length <= 65536) LiSendUtf8TextEvent(bytes.bytes, (unsigned int)bytes.length);
}

- (BOOL)handleMouseButtonEvent:(int)buttonAction forTouches:(NSSet *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        UITouch* touch = [touches anyObject];
        if (touch.type == UITouchTypeIndirectPointer) {
            if (@available(iOS 14.0, *)) {
                if ([GCMouse current] != nil) {
                    // We'll handle this with GCMouse. Do nothing here.
                    return YES;
                }
            }
            
            UIEventButtonMask normalizedButtonMask;
            
            // iOS 14 includes the released button in the buttonMask for the release
            // event, while iOS 13 does not. Normalize that behavior here.
            if (@available(iOS 14.0, *)) {
                if (buttonAction == BUTTON_ACTION_RELEASE) {
                    normalizedButtonMask = lastMouseButtonMask & ~event.buttonMask;
                }
                else {
                    normalizedButtonMask = event.buttonMask;
                }
            }
            else {
                normalizedButtonMask = event.buttonMask;
            }
            
            UIEventButtonMask changedButtons = lastMouseButtonMask ^ normalizedButtonMask;
                        
            for (int i = BUTTON_LEFT; i <= BUTTON_X2; i++) {
                UIEventButtonMask buttonFlag;
                
                switch (i) {
                    // Right and Middle are reversed from what iOS uses
                    case BUTTON_RIGHT:
                        buttonFlag = UIEventButtonMaskForButtonNumber(2);
                        break;
                    case BUTTON_MIDDLE:
                        buttonFlag = UIEventButtonMaskForButtonNumber(3);
                        break;
                        
                    default:
                        buttonFlag = UIEventButtonMaskForButtonNumber(i);
                        break;
                }
                
                if (changedButtons & buttonFlag) {
                    LiSendMouseButtonEvent(buttonAction, i);
                }
            }
            
            lastMouseButtonMask = normalizedButtonMask;
            return YES;
        }
    }
#endif
    
    return NO;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
        
        UITouch *touch = [touches anyObject];
        if (touch.type == UITouchTypeIndirectPointer) {
            if (@available(iOS 14.0, *)) {
                if ([GCMouse current] != nil) {
                    // We'll handle this with GCMouse. Do nothing here.
                    return;
                }
            }
            
            // We must handle this event to properly support
            // drags while the middle, X1, or X2 mouse buttons are
            // held down. For some reason, left and right buttons
            // don't require this, but we do it anyway for them too.
            // Cursor movement without a button held down is handled
            // in pointerInteraction:regionForRequest:defaultRegion.
            [self updateCursorLocation:[touch locationInView:self] isMouse:YES];
            return;
        }
    }
#endif
    
    hasUserInteracted = YES;
    
    if (suppressDirectTouches) return;
    if (![onScreenControls handleTouchMovedEvent:touches]) {
        [touchHandler touchesMoved:touches withEvent:event];
    }
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    
    if (@available(iOS 13.4, tvOS 13.4, *)) {
        for (UIPress* press in presses) {
            // For now, we'll treated it as handled if we handle at least one of the
            // UIPress events inside the set.
            if ([KeyboardSupport sendKeyEventForPress:press down:YES]) {
                // This will prevent the legacy UITextField from receiving the event
                handled = YES;
            }
        }
    }
    
    if (!handled) {
        [super pressesBegan:presses withEvent:event];
    }
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    
    if (@available(iOS 13.4, tvOS 13.4, *)) {
        for (UIPress* press in presses) {
            // For now, we'll treated it as handled if we handle at least one of the
            // UIPress events inside the set.
            if ([KeyboardSupport sendKeyEventForPress:press down:NO]) {
                // This will prevent the legacy UITextField from receiving the event
                handled = YES;
            }
        }
    }
    
    if (!handled) {
        [super pressesEnded:presses withEvent:event];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self handleMouseButtonEvent:BUTTON_ACTION_RELEASE
                          forTouches:touches
                           withEvent:event]) {
        // If it's a mouse event, we're done
        return;
    }
    
    Log(LOG_D, @"Touch up");
    
    hasUserInteracted = YES;
    
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
    }
#endif
    
    if (suppressDirectTouches) {
        if ([[event allTouches] count] == touches.count) suppressDirectTouches = NO;
        return;
    }
    if (![onScreenControls handleTouchUpEvent:touches]) {
        [touchHandler touchesEnded:touches withEvent:event];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [touchHandler touchesCancelled:[event allTouches] withEvent:event];
    suppressDirectTouches = NO;
    [self handleMouseButtonEvent:BUTTON_ACTION_RELEASE
                      forTouches:touches
                       withEvent:event];
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                [self sendStylusEvent:touch];
            }
        }
    }
#endif
}

#if !TARGET_OS_TV
- (void)emitPointerX:(short)x y:(short)y width:(short)width height:(short)height {
    LiSendMousePositionEvent(x, y, width, height);
}

- (void) updateCursorLocation:(CGPoint)location isMouse:(BOOL)isMouse {
    CGPoint normalizedLocation = [self adjustCoordinatesForVideoArea:location];
    CGSize videoSize = [self getVideoAreaSize];
    
    // Send the mouse position relative to the video region if it has changed
    // if we're receiving coordinates from a real mouse.
    //
    // NB: It is important for functionality (not just optimization) to only
    // send it if the value has changed. We will receive one of these events
    // any time the user presses a modifier key, which can result in errant
    // mouse motion when using a Citrix X1 mouse.
    if (normalizedLocation.x != lastMouseX || normalizedLocation.y != lastMouseY || !isMouse) {
        if (lastMouseX != 0 || lastMouseY != 0 || !isMouse) {
            if (videoSize.width <= 0 || videoSize.height <= 0) return;
            // The protocol sends reference size minus one. Keep sub-point precision
            // and map the image endpoints to that inclusive range consistently.
            const short reference = 32767;
            const double maximum = reference - 1;
            short x = (short)lround(normalizedLocation.x / videoSize.width * maximum);
            short y = (short)lround(normalizedLocation.y / videoSize.height * maximum);
            [self emitPointerX:x y:y width:reference height:reference];
        }
        
        if (isMouse) {
            lastMouseX = normalizedLocation.x;
            lastMouseY = normalizedLocation.y;
        }
    }
}

- (UIPointerRegion *)pointerInteraction:(UIPointerInteraction *)interaction
                       regionForRequest:(UIPointerRegionRequest *)request
                          defaultRegion:(UIPointerRegion *)defaultRegion API_AVAILABLE(ios(13.4)) {
    if (@available(iOS 14.0, *)) {
        if ([GCMouse current] != nil) {
            // We'll handle this with GCMouse. Do nothing here.
            return nil;
        }
    }
    
    // This logic mimics what iOS does with AVLayerVideoGravityResizeAspect
    CGSize videoSize;
    CGPoint videoOrigin;
    if (self.bounds.size.width > self.bounds.size.height * streamAspectRatio) {
        videoSize = CGSizeMake(self.bounds.size.height * streamAspectRatio, self.bounds.size.height);
    } else {
        videoSize = CGSizeMake(self.bounds.size.width, self.bounds.size.width / streamAspectRatio);
    }
    videoOrigin = CGPointMake(self.bounds.size.width / 2 - videoSize.width / 2,
                              self.bounds.size.height / 2 - videoSize.height / 2);
    
    // Move the cursor on the host if no buttons are pressed.
    // Motion with buttons pressed in handled in touchesMoved:
    if (lastMouseButtonMask == 0) {
        [self updateCursorLocation:request.location isMouse:YES];
    }
    
    // The pointer interaction should cover the video region only
    return [UIPointerRegion regionWithRect:CGRectMake(videoOrigin.x, videoOrigin.y, videoSize.width, videoSize.height) identifier:nil];
}

- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region  API_AVAILABLE(ios(13.4)) {
    // Always hide the mouse cursor over our stream view
    return [UIPointerStyle hiddenPointerStyle];
}

- (void)mouseWheelMovedContinuous:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            break;
        
        case UIGestureRecognizerStateEnded:
        default:
            // Ignore recognition failure and other states
            lastScrollTranslation = CGPointMake(0, 0);
            return;
    }
    
    CGPoint currentScrollTranslation = [gesture translationInView:self];
    const short translationMultiplier = 120 * 20; // WHEEL_DELTA * 20
    
    {
        short translationDeltaY = ((currentScrollTranslation.y - lastScrollTranslation.y) / self.bounds.size.height) * translationMultiplier;
        if (translationDeltaY != 0) {
            LiSendHighResScrollEvent(translationDeltaY);
            lastScrollTranslation = currentScrollTranslation;
        }
    }

    {
        short translationDeltaX = ((currentScrollTranslation.x - lastScrollTranslation.x) / self.bounds.size.width) * translationMultiplier;
        if (translationDeltaX != 0) {
            // Direction is reversed from vertical scrolling
            LiSendHighResHScrollEvent(-translationDeltaX);
            lastScrollTranslation = currentScrollTranslation;
        }
    }
}

- (void)mouseWheelMovedDiscrete:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            break;
        
        case UIGestureRecognizerStateEnded:
        default:
            // Ignore recognition failure and other states
            lastScrollTranslation = CGPointMake(0, 0);
            return;
    }
    
    // Using velocityInView is 0 for discrete scroll events
    // when scrolling very slowly, but translationInView does work.
    CGPoint currentScrollTranslation = [gesture translationInView:self];
    
    {
        short translationDeltaY = currentScrollTranslation.y - lastScrollTranslation.y;
        if (translationDeltaY != 0) {
            LiSendScrollEvent(translationDeltaY > 0 ? 1 : -1);
        }
    }

    {
        short translationDeltaX = currentScrollTranslation.x - lastScrollTranslation.x;
        if (translationDeltaX != 0) {
            // Direction is reversed from vertical scrolling
            LiSendHScrollEvent(translationDeltaX < 0 ? 1 : -1);
        }
    }
    
    lastScrollTranslation = currentScrollTranslation;
}

#endif

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (@available(iOS 13.0, *)) {
        // Disable the 3 finger tap gestures that trigger the copy/paste/undo toolbar on iOS 13+
        return gestureRecognizer.name == nil || ![gestureRecognizer.name hasPrefix:@"kbProductivity."];
    }
    else {
        return YES;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    unsigned char modifiers = [self keyboardModifiers];
    [self emitKeyboardKey:0x0D action:KEY_ACTION_DOWN modifiers:modifiers flags:0];
    [self emitKeyboardKey:0x0D action:KEY_ACTION_UP modifiers:modifiers flags:0];
    return NO;
}
- (void)textFieldDidEndEditing:(UITextField *)textField {
    // Release held modifiers when dismissed by UIKit, toolbar or stream closure.
    NSArray<NSNumber *> *held = keysDown.allObjects;
    for (NSNumber *keyCode in held) {
        [keysDown removeObject:keyCode];
        [self emitKeyboardKey:keyCode.unsignedShortValue action:KEY_ACTION_UP modifiers:[self keyboardModifiers] flags:0];
    }
    [self updateKeyboardModifierMenu];
}
- (void)onKeyboardPressed:(UITextField *)textField {
    if (textField.markedTextRange != nil) return;
    NSString *inputText = textField.text ?: @"";
    if (inputText.length == 0) {
        unsigned char modifiers = [self keyboardModifiers];
        [self emitKeyboardKey:0x08 action:KEY_ACTION_DOWN modifiers:modifiers flags:0];
        [self emitKeyboardKey:0x08 action:KEY_ACTION_UP modifiers:modifiers flags:0];
    } else {
        NSString *committed = [inputText hasPrefix:@"0"] ? [inputText substringFromIndex:1] : inputText;
        BOOL requiresUTF8 = NO;
        for (NSUInteger i = 0; i < committed.length; i++) {
            if ([KeyboardSupport translateKeyEvent:[committed characterAtIndex:i] withModifierFlags:0].keycode == 0) { requiresUTF8 = YES; break; }
        }
        if (requiresUTF8) [self emitKeyboardText:committed];
        else for (NSUInteger i = 0; i < committed.length; i++) {
            [self sendLowLevelEvent:[KeyboardSupport translateKeyEvent:[committed characterAtIndex:i] withModifierFlags:0]];
        }
    }
    textField.text = @"0";
    UITextRange *end = [textField textRangeFromPosition:textField.endOfDocument toPosition:textField.endOfDocument];
    [textField setSelectedTextRange:end];
}

- (void)specialCharPressed:(UIKeyCommand *)cmd {
    struct KeyEvent event = [KeyboardSupport translateKeyEvent:0x20 withModifierFlags:[cmd modifierFlags]];
    event.keycode = [[dictCodes valueForKey:[cmd input]] intValue];
    [self sendLowLevelEvent:event];
}

- (void)keyPressed:(UIKeyCommand *)cmd {
    struct KeyEvent event = [KeyboardSupport translateKeyEvent:[[cmd input] characterAtIndex:0] withModifierFlags:[cmd modifierFlags]];
    [self sendLowLevelEvent:event];
}

- (void)sendLowLevelEvent:(struct KeyEvent)event {
    // UIKit delivers keyboard callbacks on main. Enqueue each complete key chord
    // synchronously so rapid typing cannot reorder letters or modifier releases.
    unsigned char held = [self keyboardModifiers];
    BOOL transientModifier = event.modifier != 0 && (held & event.modifier) != event.modifier;
    unsigned char modifiers = held | event.modifier;
    if (transientModifier) [self emitKeyboardKey:event.modifierKeycode action:KEY_ACTION_DOWN modifiers:modifiers flags:0];
    [self emitKeyboardKey:event.keycode action:KEY_ACTION_DOWN modifiers:modifiers flags:SS_KBE_FLAG_NON_NORMALIZED];
    [self emitKeyboardKey:event.keycode action:KEY_ACTION_UP modifiers:modifiers flags:SS_KBE_FLAG_NON_NORMALIZED];
    if (transientModifier) [self emitKeyboardKey:event.modifierKeycode action:KEY_ACTION_UP modifiers:held flags:0];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (NSArray<UIKeyCommand *> *)keyCommands
{
    NSString *charset = @"qwertyuiopasdfghjklzxcvbnm1234567890\t§[]\\'\"/.,`<>-´ç+`¡'º;ñ= ";
    
    NSMutableArray<UIKeyCommand *> * commands = [NSMutableArray<UIKeyCommand *> array];
    dictCodes = [[NSDictionary alloc] initWithObjectsAndKeys: [NSNumber numberWithInt: 0x0d], @"\r", [NSNumber numberWithInt: 0x08], @"\b", [NSNumber numberWithInt: 0x1b], UIKeyInputEscape, [NSNumber numberWithInt: 0x28], UIKeyInputDownArrow, [NSNumber numberWithInt: 0x26], UIKeyInputUpArrow, [NSNumber numberWithInt: 0x25], UIKeyInputLeftArrow, [NSNumber numberWithInt: 0x27], UIKeyInputRightArrow, nil];
    
    [charset enumerateSubstringsInRange:NSMakeRange(0, charset.length)
                                options:NSStringEnumerationByComposedCharacterSequences
                             usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:0 action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierShift action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierControl action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierAlternate action:@selector(keyPressed:)]];
                             }];
    
    for (NSString *c in [dictCodes keyEnumerator]) {
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:0
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift | UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift | UIKeyModifierControl
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierControl
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierControl | UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
    }
    
    return commands;
}

- (void)connectedStateDidChangeWithIdentifier:(NSUUID * _Nonnull)identifier isConnected:(BOOL)isConnected {
    NSLog(@"Citrix X1 mouse state change: %@ -> %s",
          identifier, isConnected ? "connected" : "disconnected");
}

- (void)mouseDidMoveWithIdentifier:(NSUUID * _Nonnull)identifier deltaX:(int16_t)deltaX deltaY:(int16_t)deltaY {
    accumulatedMouseDeltaX += deltaX / X1_MOUSE_SPEED_DIVISOR;
    accumulatedMouseDeltaY += deltaY / X1_MOUSE_SPEED_DIVISOR;
    
    short shortX = (short)accumulatedMouseDeltaX;
    short shortY = (short)accumulatedMouseDeltaY;
    
    if (shortX == 0 && shortY == 0) {
        return;
    }
    
    LiSendMouseMoveEvent(shortX, shortY);
    
    accumulatedMouseDeltaX -= shortX;
    accumulatedMouseDeltaY -= shortY;
}

- (int) buttonFromX1ButtonCode:(enum X1MouseButton)button {
    switch (button) {
        case X1MouseButtonLeft:
            return BUTTON_LEFT;
        case X1MouseButtonRight:
            return BUTTON_RIGHT;
        case X1MouseButtonMiddle:
            return BUTTON_MIDDLE;
        default:
            return -1;
    }
}

- (void)mouseDownWithIdentifier:(NSUUID * _Nonnull)identifier button:(enum X1MouseButton)button {
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, [self buttonFromX1ButtonCode:button]);
}

- (void)mouseUpWithIdentifier:(NSUUID * _Nonnull)identifier button:(enum X1MouseButton)button {
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, [self buttonFromX1ButtonCode:button]);
}

- (void)wheelDidScrollWithIdentifier:(NSUUID * _Nonnull)identifier deltaZ:(int8_t)deltaZ {
    LiSendScrollEvent(deltaZ);
}

#if !TARGET_OS_TV
- (BOOL)isMultipleTouchEnabled {
    return YES;
}
#endif

@end
