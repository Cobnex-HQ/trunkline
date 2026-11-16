# Validation

Run `python3 Scripts/dev.py test` for the default contributor suite: tooling unit tests, `TrunklineCore` tests and Rust transport tests. Tests must not require a maintainer's device IDs, credentials or private network.

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

## Hardware acceptance

Before a binary release, test iPhone and iPad in portrait and landscape, before and after zoom/pan; tap the centre and all display corners. Verify mixed-resolution/Retina monitors and switching while frames are arriving. Test keyboard, scroll, drag, reconnect, session exclusion, switching saved Macs, permission denial and resumed sessions after sleep.

For connection input, test with several saved Macs and the software keyboard in both orientations. The passcode must stay above the keyboard; reveal/hide must preserve text, selection and focus. Check the Go key, Done dismissal, saved-credential fallback, and large text.

For desktop navigation, verify three-finger left/right changes Spaces, up opens Mission Control and down opens App windows. Verify the equivalent toolbar/menu actions and that two-finger pinch/pan still work. Test with VoiceOver using the menu alternatives. Physical display switching and Mac Spaces are separate features; test both with different monitor aspect ratios.

Check local Wi-Fi, a different Wi-Fi network and cellular independently. Simulator tests and two processes on one machine are not evidence of an external connection. Check reboot/login behaviour and initial FileVault unlock separately. Record results without device IDs or connection secrets.
