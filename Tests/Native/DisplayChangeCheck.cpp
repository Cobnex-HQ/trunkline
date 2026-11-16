/** @file DisplayChangeCheck.cpp
 * @brief Exercise native observer registration, invalidation and lifetime without changing displays.
 */
#include <CoreGraphics/CoreGraphics.h>
#include <cstdio>
static CGDisplayReconfigurationCallBack observedCallback;
static void *observedContext;
static bool refuse;
static unsigned removals;
static CGError registerObserver(CGDisplayReconfigurationCallBack callback, void *context) {
  if (refuse) { return kCGErrorFailure; }
  observedCallback = callback; observedContext = context; return kCGErrorSuccess;
}
static CGError removeObserver(CGDisplayReconfigurationCallBack callback, void *context) {
  if (callback != observedCallback || context != observedContext) { return kCGErrorFailure; }
  observedCallback = nullptr; observedContext = nullptr; ++removals; return kCGErrorSuccess;
}
#define CGDisplayRegisterReconfigurationCallback registerObserver
#define CGDisplayRemoveReconfigurationCallback removeObserver
#include "platform/macos/display_change_observer.h"
#undef CGDisplayRegisterReconfigurationCallback
#undef CGDisplayRemoveReconfigurationCallback
int main() {
  {
    platf::DisplayChangeObserver observer;
    if (!observer.registered() || observer.invalidated()) { return 1; }
    observedCallback(1, kCGDisplayBeginConfigurationFlag, observedContext);
    if (observer.invalidated()) { return 2; }
    observedCallback(2, kCGDisplayMovedFlag, observedContext);
    if (!observer.invalidated()) { return 3; }
  }
  if (observedCallback || observedContext || removals != 1) { return 4; }
  {
    platf::DisplayChangeObserver replacement;
    if (replacement.invalidated()) { return 5; }
    observedCallback(3, kCGDisplayRemoveFlag, observedContext);
    if (!replacement.invalidated()) { return 6; }
  }
  refuse = true;
  { platf::DisplayChangeObserver unavailable; if (unavailable.registered()) { return 7; } }
  if (removals != 2) { return 8; }
  std::puts("PASS: completed changes invalidate capture, replacement starts fresh, callback lifetime and registration failure");
}
