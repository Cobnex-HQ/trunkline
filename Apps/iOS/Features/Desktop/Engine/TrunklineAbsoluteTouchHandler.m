// Trunkline adaptation: non-owning input/view references; upstream notice follows.
//
//  AbsoluteTouchHandler.m
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import "AbsoluteTouchHandler.h"
#import "TrunklineTouchInput.h"

#include <Limelight.h>

// How long the fingers must be stationary to start a right click
#define LONG_PRESS_ACTIVATION_DELAY 0.650f

// How far the finger can move before it cancels a right click
#define LONG_PRESS_ACTIVATION_DELTA 0.01f

@interface AbsoluteTouchHandler () <TrunklineTouchInput>
@end

@implementation AbsoluteTouchHandler {
    __weak StreamView* view;
    
    NSTimer* longPressTimer;
    CGPoint lastTouchDownLocation;
}

- (id)initWithView:(StreamView*)view {
    self = [self init];
    self->view = view;
    return self;
}

- (void)onLongPressStart:(NSTimer*)timer {
    if (!view) return;
    // Raise the left click and start a right click
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT);
}

- (void)cancelPendingInput {
    [longPressTimer invalidate];
    longPressTimer = nil;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    // Ignore touch down events with more than one finger
    if ([[event allTouches] count] > 1) {
        return;
    }
    
    UITouch* touch = [touches anyObject];
    CGPoint touchLocation = [touch locationInView:view];
    
    // Direct touch is an absolute target, including a second nearby tap. Keeping
    // the previous position here makes small controls miss the user's finger.
    [view updateCursorLocation:touchLocation isMouse:NO];
    
    // Press the left button down
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
    
    // Start the long press timer
    longPressTimer = [NSTimer scheduledTimerWithTimeInterval:LONG_PRESS_ACTIVATION_DELAY
                                                      target:self
                                                    selector:@selector(onLongPressStart:)
                                                    userInfo:nil
                                                     repeats:NO];
    
    lastTouchDownLocation = touchLocation;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    // Ignore touch move events with more than one finger
    if ([[event allTouches] count] > 1) {
        return;
    }
    
    UITouch* touch = [touches anyObject];
    CGPoint touchLocation = [touch locationInView:view];
    
    if (sqrt(pow((touchLocation.x / view.bounds.size.width) - (lastTouchDownLocation.x / view.bounds.size.width), 2) +
             pow((touchLocation.y / view.bounds.size.height) - (lastTouchDownLocation.y / view.bounds.size.height), 2)) > LONG_PRESS_ACTIVATION_DELTA) {
        // Moved too far since touch down. Cancel the long press timer.
        [longPressTimer invalidate];
        longPressTimer = nil;
    }
    
    [view updateCursorLocation:[[touches anyObject] locationInView:view] isMouse:NO];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    // Only fire this logic if all touches have ended
    if ([[event allTouches] count] == [touches count]) {
        // UIKit can deliver a new position with the lift, without an intervening
        // touchesMoved. Send it before releasing so a drag ends at the finger.
        if (touches.count == 1) {
            [view updateCursorLocation:[[touches anyObject] locationInView:view] isMouse:NO];
        }
        [self touchesCancelled:touches withEvent:event];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    // Pinch/pan cancellation must release the drag without teleporting to one
    // of the gesture's fingers or synthesizing a final pointer target.
    [self cancelPendingInput];
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
}

@end
