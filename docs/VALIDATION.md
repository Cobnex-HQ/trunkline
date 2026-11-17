# Validation status

Development results are recorded below by date. See [test instructions](TESTING.md) and [release requirements](RELEASING.md).

## Companion App Store audit — 2026-11-17

- Passed: 35 tooling tests, 100 shared Swift tests and 11 Rust tests.
- iPhone 18 Pro and iPad mini simulators on iOS 27.2 each passed 54 companion tests and 3 viewport tests. The new regressions reproduce and prevent terminal file access and an unsupported-codec crash.
- Built a clean unsigned iOS Release archive, version 0.1.0, build 3. Incremental archiving initially failed after the SDK replacement. A separate clean Derived Data directory succeeded. Xcode emitted transient dependency-scan diagnostics despite returning success.
- Verified all 15 mandatory notice originals inside the archive, the 1024-pixel opaque App Store icon, absence of simulator fixture strings, and no imported local process-launch APIs among the selected symbols checked in the app, SwiftTerm and OpenSSL.
- Reviewed native help on iPhone in light mode and iPad in dark mode. This is a visual spot check, not full accessibility or orientation acceptance.
- Archive preflight reports two open findings: OpenSSL file-API declarations and 42 dependency notices. The app’s declared reasons and SwiftTerm import checks pass. Export is blocked until findings are resolved.
- Owner is not enrolled in the paid Developer Program. No signed export, upload, device installation or public binary release was performed. [Remaining App Store work](APP_STORE_AUDIT.md) includes licensing, privacy answers, reviewer access and physical-device/network tests.

## Hardware confirmation — 2026-11-16

The user confirmed iPad pointer placement and menu clicks after granting Mac input permission. Keyboard focus/scrolling, passcode visibility, Mission Control and Spaces gestures also worked. Both devices have the updated companion, but matching hands-on iPhone checks remain pending.

## Automated and local checks — 2026-11-16

- Contributor suite: 18 tooling tests, 100 shared Swift tests and 11 Rust transport tests passed.
- iPhone simulator: 52 companion tests and 3 viewport tests passed. Coverage includes keyboard visibility, passcode text/selection/focus, gestures, pointer mapping, rotation and zoom.
- Both macOS and iOS device-target builds passed.
- Native checks passed for queued input ordering, backend pointer targets, capture lifecycle, display geometry and display-selection state.
- Host launch/login-item checks passed: no startup permission prompts, accurate pending consent, and preserved state during registration failure/retry.
- Pairing, controls and file-transfer tests passed for timeout, disconnect, cancellation, stale responses and subsequent retry. These used fixtures, not a real network or reboot.
- The installed Apple-silicon Mac bundle passed signature, bundled-helper and external-runtime-dependency verification. The input backend patch applies to the pinned upstream source.
- Public-source policy and secret scans passed. Private settings, device identifiers, logs, provisioning profiles and build products are excluded from the source export.

## Remaining acceptance work

| Area | Remaining evidence |
| --- | --- |
| Physical monitors | Multiple connected displays, mixed Retina scaling, portrait displays and unplugging a display during streaming. |
| Unattended operation | Real reboot/login, FileVault startup, sleep/wake and repeated app launches without unexpected credential prompts. |
| Real network recovery | Wi-Fi interruption and switching networks during an active connection. |
| Multiple devices/Macs | Live iPhone/iPad contention for one host and switching between two physical Macs. |
| Away access | Broader cellular and unrelated Wi-Fi coverage. Earlier successful connections do not establish universal reachability. |
| Accessibility/layout | VoiceOver, large text, floating/hardware keyboards and the full portrait/landscape device matrix. |
| Sustained performance | Measured end-to-end latency, frame rate, CPU, thermals and battery consumption during longer sessions. |
| Distribution | Fresh-Mac setup/upgrade tests, Intel validation if advertised, exact corresponding-source/dependency review, and authorised public signing/notarization. |

These checks did not reboot the Mac, interrupt its network, reset credentials or publish binaries. The remaining checks still apply.

## Distribution preparation — 2026-11-17

- Unsigned iOS and Apple-silicon Mac Release archives built as version 0.1.0, build 3. They are not installable releases.
- Passed: 23 tooling, 100 Swift and 11 Rust tests. Release checks cover ad-hoc/unsigned rejection, archive path containment, local export settings and notarization status.
- All 52 companion tests passed after fixing a fixture race with confirmed probe completion and listener cancellation. App connection deadlines stayed unchanged.
- Distribution checks rejected real unsigned archives and the installed development Mac app without creating release output.
- Added privacy links, a privacy notice, App Store instructions and the Mac signing/notarization guide.
- **Pending:** Developer ID signing, live notarization/stapling/Gatekeeper checks, signed App Store export/upload and binary publication. Distribution identities were unavailable. Licensing, privacy and hardware checks also remain required.

## Third-party attribution audit — 2026-11-17

- Built unsigned iOS and Apple-silicon Mac archives with the revised collector and acknowledgments links. Installed apps stayed unchanged. No binaries were published.
- Verified 14 required notice files by SHA-256 in each archive, including both Moonlight App Store exceptions.
- Passed: 29 tooling tests, including six notice regressions, 100 Swift tests, 11 Rust tests and pinned dependency verification.
- Notice review remains for 42 of 367 external Cargo packages. Counts include build and other-target dependencies, not just code linked into each app.
- Codec sources/build flags, full native/Rust/web notices, OpenSSL wrapper provenance and App Store licensing remain open. See [third-party findings](THIRD_PARTY.md).
