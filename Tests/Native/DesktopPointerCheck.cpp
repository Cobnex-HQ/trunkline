/**
 * @file DesktopPointerCheck.cpp
 * @brief Exercise the actual macOS mouse backend without posting input to the Mac.
 * Display enumeration and final CoreGraphics delivery are the only substituted boundaries.
 */
#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

namespace fixture {
  std::vector<CGRect> displays;
  CGPoint pointer {};
  CGPoint posted {};
  bool stale_snapshot = false;
  CGPoint snapshot {};
  CGEventType type {};
  unsigned posts = 0;
  bool enumeration_fails = false;
  unsigned enumerations = 0;
  CGDisplayReconfigurationCallBack reconfigure = nullptr;
  void *reconfigure_context = nullptr;
  CGError register_callback(CGDisplayReconfigurationCallBack callback, void *context) {
    reconfigure = callback; reconfigure_context = context; return kCGErrorSuccess;
  }
  CGError remove_callback(CGDisplayReconfigurationCallBack, void *) {
    reconfigure = nullptr; reconfigure_context = nullptr; return kCGErrorSuccess;
  }
  void changed() { if (reconfigure) { reconfigure(1, kCGDisplaySetModeFlag, reconfigure_context); } }
  CGDirectDisplayID main_display() { return 1; }
  CGRect bounds(CGDirectDisplayID id) { return displays.at(id - 1); }
  CGError active(uint32_t capacity, CGDirectDisplayID *ids, uint32_t *count) {
    ++enumerations;
    if (enumeration_fails) { return kCGErrorFailure; }
    *count = ids ? std::min(capacity, static_cast<uint32_t>(displays.size())) : displays.size();
    if (ids) { for (uint32_t i = 0; i < *count; ++i) { ids[i] = i + 1; } }
    return kCGErrorSuccess;
  }
  CGPoint location(CGEventRef) { return stale_snapshot ? snapshot : pointer; }
  void post(CGEventTapLocation, CGEventRef event) {
    posted = CGEventGetLocation(event);
    type = CGEventGetType(event);
    ++posts;
  }
  CGError warp(CGPoint value) { pointer = value; return kCGErrorSuccess; }
}
#define CGDisplayRegisterReconfigurationCallback fixture::register_callback
#define CGDisplayRemoveReconfigurationCallback fixture::remove_callback
#define CGMainDisplayID fixture::main_display
#define CGDisplayBounds fixture::bounds
#define CGGetActiveDisplayList fixture::active
#define CGEventGetLocation fixture::location
#define CGEventPost fixture::post
#define CGWarpMouseCursorPosition fixture::warp
#define create_platform_backend create_platform_backend_for_trunkline_pointer_check
#include "platform/macos/macos_backend.cpp"
#undef create_platform_backend
#undef CGDisplayRegisterReconfigurationCallback
#undef CGDisplayRemoveReconfigurationCallback
#undef CGMainDisplayID
#undef CGDisplayBounds
#undef CGGetActiveDisplayList
#undef CGEventGetLocation
#undef CGEventPost
#undef CGWarpMouseCursorPosition

int main() {
  unsigned failures = 0;
  auto expect = [&](double x, double y, const char *name) {
    if (std::abs(fixture::pointer.x - x) > 0.01 || std::abs(fixture::pointer.y - y) > 0.01 ||
        std::abs(fixture::posted.x - x) > 0.01 || std::abs(fixture::posted.y - y) > 0.01) {
      std::printf("FAIL %s: got %.2f,%.2f; expected %.2f,%.2f\n", name, fixture::pointer.x, fixture::pointer.y, x, y);
      ++failures;
    }
  };
  fixture::displays = {{{0, 0}, {1512, 982}}, {{-1920, 0}, {1920, 1080}}};
  auto state = std::make_shared<lvh::detail::macos::MacosInputState>();
  lvh::detail::macos::MacosMouse mouse {state};
  const auto initial_enumerations = fixture::enumerations;
  using enum lvh::MouseEventKind;
  auto submit = [&](const lvh::MouseEvent &event) {
    const auto before = fixture::posts;
    if (!mouse.submit(event).ok() || fixture::posts != before + 1) { ++failures; }
  };
  submit({.kind = absolute_motion, .x = 960, .y = 540, .width = 3432, .height = 1080});
  expect(-960, 540, "absolute point on left display");
  // WindowServer may still report the preceding cursor position when the
  // button packet arrives immediately after its absolute motion packet.
  fixture::snapshot = {100, 100};
  fixture::stale_snapshot = true;
  submit({.kind = button, .button = lvh::MouseButton::left, .pressed = true});
  expect(-960, 540, "click must not jump back to primary display");
  if (fixture::type != kCGEventLeftMouseDown) { ++failures; }
  submit({.kind = absolute_motion, .x = 1000, .y = 560, .width = 3432, .height = 1080});
  expect(-920, 560, "absolute drag follows finger despite stale snapshot");
  if (fixture::type != kCGEventLeftMouseDragged) { ++failures; }
  submit({.kind = button, .button = lvh::MouseButton::left, .pressed = false});
  expect(-920, 560, "release stays at final finger position");
  if (fixture::type != kCGEventLeftMouseUp) { ++failures; }
  submit({.kind = absolute_motion, .x = 960, .y = 540, .width = 3432, .height = 1080});
  submit({.kind = button, .button = lvh::MouseButton::left, .pressed = true});
  expect(-960, 540, "next tap moves to its own target");
  fixture::stale_snapshot = false;
  submit({.kind = relative_motion, .x = 20, .y = -10});
  expect(-940, 530, "drag on left display");
  if (fixture::type != kCGEventLeftMouseDragged) { ++failures; }
  submit({.kind = button, .button = lvh::MouseButton::left, .pressed = false});
  fixture::pointer = {-10, 500};
  submit({.kind = relative_motion, .x = -20, .y = 0});
  expect(-30, 500, "trackpad across display boundary");
  fixture::pointer = {100, 980};
  submit({.kind = relative_motion, .x = 0, .y = 20});
  expect(100, 981, "gap clamps to nearest actual display");
  if (fixture::enumerations != initial_enumerations) { ++failures; }
  fixture::displays = {{{0, 0}, {1512, 982}}, {{0, -1200}, {1920, 1200}}};
  fixture::changed();
  submit({.kind = absolute_motion, .x = 960, .y = 600, .width = 1920, .height = 2182});
  expect(960, -600, "display above primary");
  fixture::displays.resize(1);
  fixture::changed();
  submit({.kind = absolute_motion, .x = 1512, .y = 982, .width = 3024, .height = 1964});
  expect(756, 491, "hot unplug and Retina scaling");
  fixture::enumeration_fails = true;
  fixture::changed();
  submit({.kind = absolute_motion, .x = 756, .y = 491, .width = 1512, .height = 982});
  expect(756, 491, "enumeration failure falls back safely");
  std::printf("%s: actual backend mapping, buttons, drag, gaps and topology changes; no system input posted\n", failures ? "FAIL" : "PASS");
  return failures ? 1 : 0;
}
