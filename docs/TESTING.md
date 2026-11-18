# Validation

Run `python3 Scripts/dev.py test` for tooling, shared Swift and Rust tests. Tests must work without maintainer credentials, device IDs or private networks.

## Select checks for your change

Run commands from the repository root with the development prerequisites installed.

| Area changed | Focused check |
| --- | --- |
| Python setup, packaging or release tooling | `python3 -m unittest discover -s Tests/Tooling` |
| Shared Swift protocol, geometry or policy | `swift test --package-path Packages/Core --scratch-path .build/core --disable-sandbox` |
| Rust transport | `cargo test --locked --manifest-path Packages/Transport/Cargo.toml` |
| Companion connection, keyboard or workspace | `Scripts/verify-companion.sh SIMULATOR_UDID` after setup |
| UIKit viewport and touch mapping | `Scripts/verify-viewport.sh SIMULATOR_UDID` after setup, followed by hardware acceptance |
| Client movement/button ordering | `Scripts/verify-input-ordering.sh` after dependency preparation |
| Terminal exit and remote keep-awake | `sh Scripts/verify-terminal-power.sh` on macOS, then companion tests |
| Mac sharing confirmations and connection lifecycle | `sh Scripts/verify-mac-client.sh` on macOS |
| Native layouts, sheets and orientation | [Simulator screenshot review](../Tests/UIReview/README.md), plus MacClientTests for Mac window captures |
| iOS release archive | `python3 Scripts/audit-ios.py --archive PATH.xcarchive --report .build/ios-preflight.json` |

Run every suite affected by a change. Documentation edits need link, path and command checks, not an engine rebuild.

## Simulator checks

After `setup`, app compilation can be checked without a personal signing team:

```sh
xcodebuild -project Trunkline.xcodeproj -scheme Trunkline \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/ios-simulator CODE_SIGNING_ALLOWED=NO build
```

For simulator regression tests, find a bootable iPhone or iPad with `xcrun simctl list devices available`, then run:

```sh
Scripts/verify-companion.sh SIMULATOR_UDID
Scripts/verify-viewport.sh SIMULATOR_UDID
```

The companion suite replays isolated Claude startup captures from `Tests/Fixtures/ClaudeStartup`. It checks redraws, menu keys and rotation without installing Claude or using an account.

`Scripts/verify.sh` runs native integration checks and builds both apps. Build the Mac host first to prepare its runtime. Input-ordering checks cover rapid taps, drag endpoints and coalescing. `Scripts/verify-desktop-pointer.sh` checks engine targets and delayed cursor snapshots. Read the window and device scripts’ usage before running them.

Use an available device ID for `SIMULATOR_UDID`. Test results are in Derived Data under `Logs/Test/*.xcresult`. Set `TRUNKLINE_SIM_DERIVED_DATA=.build/ios-simulator` to reuse the build above. Otherwise the scripts use separate defaults. Open results in Xcode and redact diagnostics before sharing.

## What CI covers

On pull requests and pushes to `main`, [Checks](../.github/workflows/ci.yml) runs secret and source scans, tooling, input-ordering, Swift and Rust tests, plus the simulator build, companion tests and viewport tests. Failed simulator results are kept temporarily as artifacts.

The full [Mac build](../.github/workflows/host-build.yml) runs manually. Normal CI does not validate the complete host runtime, hardware, cellular access, OS permissions or distribution signing. See [VALIDATION.md](VALIDATION.md).

## Hardware acceptance

Before a binary release, test iPhone and iPad in portrait and landscape, before and after zoom/pan. Tap the centre and all display corners. Verify mixed-resolution/Retina monitors and switching while frames are arriving. Test keyboard, scroll, drag, reconnect, session exclusion, switching saved Macs, permission denial and resumed sessions after sleep.

For connection input, test with several saved Macs and the software keyboard in both orientations. The passcode must stay above the keyboard. Reveal/hide must preserve text, selection and focus. Check the Go key, Done dismissal, saved-credential fallback, and large text.

For desktop navigation, verify three-finger left/right changes Spaces, up opens Mission Control and down opens App windows. Verify the equivalent toolbar/menu actions and that two-finger pinch/pan still work. Test with VoiceOver using the menu alternatives. Physical display switching and Mac Spaces are separate features. Test both with different monitor aspect ratios.

For terminal input, start a session in each orientation and rotate with the keyboard shown and hidden. Tap the terminal to open the keyboard, type, use shortcut keys, dismiss by button and swipe, then rotate again. The shortcut row must stay above the keyboard and the live prompt must remain visible. Scroll into history and rotate again to check that reading position is preserved. Repeat with a full-screen terminal program and a hardware keyboard.

For desktop zoom, place the two fingers slightly apart in time, pinch, then lift one finger before the other. The gesture must not click or move the Mac pointer. Check normal taps, single-finger drags and long-press right clicks afterward.

Check local Wi-Fi, a different Wi-Fi network and cellular independently. Simulator tests and two processes on one machine are not evidence of an external connection. Check reboot/login behaviour and initial FileVault unlock separately. Record results without device IDs or connection secrets.

## Mac client

Run `sh Scripts/verify-mac-client.sh` for the real local TCP fixture. It checks authentication, admission rejection, cancellation and preservation of a prepared away tunnel. The `MacClientTests` Xcode scheme checks AppKit pointer mapping, input release and real H.264 decoding.

```sh
xcodebuild -project Trunkline.xcodeproj -scheme MacClientTests \
  -destination 'platform=macOS' -derivedDataPath .build/mac-client test
```

The opt-in streaming test starts an isolated bundled host on ports 59984–60010 with temporary random credentials. It does not use saved host credentials. It requires macOS capture and input permission and checks injected clicks and keys with an event tap that consumes only fixture events. Mouse and keyboard ordering is checked within each input channel. Add `TRUNKLINE_TEST_LIVE_STREAM=1` to the command to run it. Normal CI skips this hardware check.

Before release, test two physical Macs on local and separate networks, including audio, full-screen transitions, mixed-resolution monitors, reconnect and a host already controlled by another device. Test non-US keyboards and input methods separately. The current Mac viewer sends physical key events and does not implement a local IME composition surface.
