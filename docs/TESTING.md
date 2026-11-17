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

`Scripts/verify.sh` runs native integration checks and builds both apps. Build the Mac host first to prepare its runtime. Input-ordering checks cover rapid taps, drag endpoints and coalescing. `Scripts/verify-desktop-pointer.sh` checks engine targets and delayed cursor snapshots. Read the window and device scripts’ usage before running them.

Use an available device ID for `SIMULATOR_UDID`. Test results are in Derived Data under `Logs/Test/*.xcresult`. Set `TRUNKLINE_SIM_DERIVED_DATA=.build/ios-simulator` to reuse the build above. Otherwise the scripts use separate defaults. Open results in Xcode and redact diagnostics before sharing.

## What CI covers

On pull requests and pushes to `main`, [Checks](../.github/workflows/ci.yml) runs secret and source scans, tooling, input-ordering, Swift and Rust tests, plus the simulator build, companion tests and viewport tests. Failed simulator results are kept temporarily as artifacts.

The full [Mac build](../.github/workflows/host-build.yml) runs manually. Normal CI does not validate the complete host runtime, hardware, cellular access, OS permissions or distribution signing. See [VALIDATION.md](VALIDATION.md).

## Hardware acceptance

Before a binary release, test iPhone and iPad in portrait and landscape, before and after zoom/pan. Tap the centre and all display corners. Verify mixed-resolution/Retina monitors and switching while frames are arriving. Test keyboard, scroll, drag, reconnect, session exclusion, switching saved Macs, permission denial and resumed sessions after sleep.

For connection input, test with several saved Macs and the software keyboard in both orientations. The passcode must stay above the keyboard. Reveal/hide must preserve text, selection and focus. Check the Go key, Done dismissal, saved-credential fallback, and large text.

For desktop navigation, verify three-finger left/right changes Spaces, up opens Mission Control and down opens App windows. Verify the equivalent toolbar/menu actions and that two-finger pinch/pan still work. Test with VoiceOver using the menu alternatives. Physical display switching and Mac Spaces are separate features. Test both with different monitor aspect ratios.

Check local Wi-Fi, a different Wi-Fi network and cellular independently. Simulator tests and two processes on one machine are not evidence of an external connection. Check reboot/login behaviour and initial FileVault unlock separately. Record results without device IDs or connection secrets.
