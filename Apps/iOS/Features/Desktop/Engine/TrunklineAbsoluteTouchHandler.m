// Modified for Trunkline; adaptation notice recorded 2026-11-17.
// Based on Moonlight iOS 02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a.
// Original notices and licence are retained; see docs/THIRD_PARTY.md.
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

// Allow the second finger of a pinch to arrive before starting a remote drag.
static const NSTimeInterval SingleTouchDelay = 0.12;
static const NSTimeInterval LongPressDelay = 0.65;
static const CGFloat DragThreshold = 5;

@interface AbsoluteTouchHandler () <TrunklineTouchInput>
@end

@implementation AbsoluteTouchHandler {
    __weak StreamView *view;
    NSTimer *longPressTimer;
    NSTimer *singleTouchTimer;
    CGPoint startLocation, currentLocation;
    BOOL active, moved, singleTouchReady;
    int heldButton;
}

- (id)initWithView:(StreamView *)view {
    self = [self init];
    self->view = view;
    return self;
}

- (void)emitMouseButtonAction:(char)action button:(int)button {
    LiSendMouseButtonEvent(action, button);
}

- (void)beginDragIfReady {
    if (!active || !view || !moved || !singleTouchReady || heldButton) return;
    [view updateCursorLocation:startLocation isMouse:NO];
    heldButton = BUTTON_LEFT;
    [self emitMouseButtonAction:BUTTON_ACTION_PRESS button:heldButton];
    [view updateCursorLocation:currentLocation isMouse:NO];
}

- (void)onSingleTouchReady:(NSTimer *)timer {
    [singleTouchTimer invalidate];
    singleTouchTimer = nil;
    singleTouchReady = YES;
    [self beginDragIfReady];
}

- (void)onLongPressStart:(NSTimer *)timer {
    if (!active || !view || moved || heldButton) return;
    [longPressTimer invalidate];
    longPressTimer = nil;
    [view updateCursorLocation:currentLocation isMouse:NO];
    heldButton = BUTTON_RIGHT;
    [self emitMouseButtonAction:BUTTON_ACTION_PRESS button:heldButton];
}

- (void)cancelPendingInput {
    [longPressTimer invalidate];
    longPressTimer = nil;
    [singleTouchTimer invalidate];
    singleTouchTimer = nil;
    active = NO;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (event.allTouches.count != 1) {
        [self touchesCancelled:touches withEvent:event];
        return;
    }
    [self cancelPendingInput];
    startLocation = currentLocation = [[touches anyObject] locationInView:view];
    active = YES;
    moved = singleTouchReady = NO;
    singleTouchTimer = [NSTimer scheduledTimerWithTimeInterval:SingleTouchDelay target:self
        selector:@selector(onSingleTouchReady:) userInfo:nil repeats:NO];
    longPressTimer = [NSTimer scheduledTimerWithTimeInterval:LongPressDelay target:self
        selector:@selector(onLongPressStart:) userInfo:nil repeats:NO];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (event.allTouches.count != 1) {
        [self touchesCancelled:touches withEvent:event];
        return;
    }
    if (!active) return;
    currentLocation = [[touches anyObject] locationInView:view];
    if (hypot(currentLocation.x - startLocation.x, currentLocation.y - startLocation.y) >= DragThreshold) {
        moved = YES;
        [longPressTimer invalidate];
        longPressTimer = nil;
    }
    if (heldButton) [view updateCursorLocation:currentLocation isMouse:NO];
    else [self beginDragIfReady];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!active) return;
    if (event.allTouches.count != 1 || touches.count != 1) {
        [self touchesCancelled:touches withEvent:event];
        return;
    }
    // A tap commits on lift, after it can no longer become a pinch. Drags also
    // send the final finger position, which UIKit may omit from touchesMoved.
    [view updateCursorLocation:[[touches anyObject] locationInView:view] isMouse:NO];
    if (!heldButton) {
        heldButton = BUTTON_LEFT;
        [self emitMouseButtonAction:BUTTON_ACTION_PRESS button:heldButton];
    }
    [self touchesCancelled:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self cancelPendingInput];
    if (heldButton) {
        [self emitMouseButtonAction:BUTTON_ACTION_RELEASE button:heldButton];
        heldButton = 0;
    }
}
@end
