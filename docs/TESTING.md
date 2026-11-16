# Validation

Run `python3 Scripts/dev.py test` for the default contributor suite: tooling unit tests, `TrunklineCore` tests and Rust transport tests. Tests must not require a maintainer's device IDs, credentials or private network.

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

Choose all affected suites for cross-layer changes. Pure documentation changes need link/path and command review; they do not require recompiling the streaming engine.

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

The native integration checks are collected in `Scripts/verify.sh`. This also builds both apps, so run a Mac development build first to generate the desktop runtime configuration. Use `Scripts/verify-input-ordering.sh` for real client queue/sender checks (rapid taps, drag endpoints and coalescing), `Scripts/verify-desktop-pointer.sh` for engine pointer checks (including delayed system cursor snapshots) and the window verification scripts for their native integration cases. Read each script's usage before running device-dependent checks.

Replace `SIMULATOR_UDID` with an available simulator identifier. Both verification scripts run `xcodebuild test` and write `.xcresult` bundles under their Derived Data `Logs/Test` directory. Set `TRUNKLINE_SIM_DERIVED_DATA=.build/ios-simulator` when invoking them to reuse the build directory above; otherwise each script uses its own default directory. Open a result bundle in Xcode to inspect failures. Keep diagnostic attachments private until reviewed for connection information.

## What CI covers

The [Checks workflow](../.github/workflows/ci.yml) runs secret scanning, tooling tests, client input ordering, Swift core tests, Rust tests, public-source policy, a companion simulator build, companion regression tests and viewport tests. It runs on pushes to `main` and pull requests. Failed simulator test results are retained temporarily as workflow artifacts.

The full [Mac development build](../.github/workflows/host-build.yml) is a separate manual workflow. Ordinary Checks success does not prove that the complete Mac runtime builds or that hardware input, cellular connectivity, OS permissions or signed distribution work. See [VALIDATION.md](VALIDATION.md) for recorded evidence and remaining work.

## Hardware acceptance

Before a binary release, test iPhone and iPad in portrait and landscape, before and after zoom/pan; tap the centre and all display corners. Verify mixed-resolution/Retina monitors and switching while frames are arriving. Test keyboard, scroll, drag, reconnect, session exclusion, switching saved Macs, permission denial and resumed sessions after sleep.

For connection input, test with several saved Macs and the software keyboard in both orientations. The passcode must stay above the keyboard; reveal/hide must preserve text, selection and focus. Check the Go key, Done dismissal, saved-credential fallback, and large text.

For desktop navigation, verify three-finger left/right changes Spaces, up opens Mission Control and down opens App windows. Verify the equivalent toolbar/menu actions and that two-finger pinch/pan still work. Test with VoiceOver using the menu alternatives. Physical display switching and Mac Spaces are separate features; test both with different monitor aspect ratios.

Check local Wi-Fi, a different Wi-Fi network and cellular independently. Simulator tests and two processes on one machine are not evidence of an external connection. Check reboot/login behaviour and initial FileVault unlock separately. Record results without device IDs or connection secrets.
