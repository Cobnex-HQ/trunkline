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

The native integration checks are collected in `Scripts/verify.sh`. This also builds both apps, so run a Mac development build first to generate the desktop runtime configuration. Use `Scripts/verify-desktop-pointer.sh` for engine pointer checks and the window verification scripts for their native integration cases. Read each script's usage before running device-dependent checks.

## Hardware acceptance

Before a binary release, test iPhone and iPad in portrait and landscape, before and after zoom/pan; tap the centre and all display corners. Verify mixed-resolution/Retina monitors and switching while frames are arriving. Test keyboard, scroll, drag, reconnect, session exclusion, switching saved Macs, permission denial and resumed sessions after sleep.

Check local Wi-Fi, a different Wi-Fi network and cellular independently. Simulator tests and two processes on one machine are not evidence of an external connection. Check reboot/login behaviour and initial FileVault unlock separately. Record results without device IDs or connection secrets.
