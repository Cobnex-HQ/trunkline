# Validation status

Recorded 2026-11-16 for the pointer, permission, connection-input and workspace-navigation changes. This is a development validation record, not public-release certification. See [test instructions](TESTING.md) and [release gates](RELEASING.md).

## Confirmed on hardware

The user confirmed on iPad that direct touch positions the pointer correctly and clicks open Mac menus after granting the correct macOS input permission. The user also confirmed connection-field keyboard focus/scrolling, passcode show/hide, Mission Control and Mac Spaces gestures. The updated companion is installed on iPad and iPhone; equivalent hands-on confirmation of the latest iPhone changes remains pending.

## Automated and local checks

- Contributor suite: 18 tooling tests, 100 shared Swift tests and 11 Rust transport tests passed.
- iPhone simulator: 52 companion tests and 3 viewport tests passed. These cover native software-keyboard visibility, passcode selection/focus/text preservation, gesture routing, pointer transforms, rotation and zoom.
- Both macOS and iOS device-target builds passed.
- Native checks passed for queued input ordering, backend pointer targets, capture lifecycle, display geometry and display-selection state.
- Host launch/login-item checks passed: startup does not request interactive permissions, pending consent is represented accurately, and registration failures/retries preserve actual state.
- Pairing, controls and file-transfer tests passed for timeout, disconnect, cancellation, stale responses and subsequent retry. These use controlled fixtures and do not establish real network recovery after a reboot.
- The installed Apple-silicon Mac bundle passed signature, bundled-helper and external-runtime-dependency verification. The input backend patch applies to the pinned upstream source.
- Public-source policy and secret scans passed. Private settings, device identifiers, logs, provisioning profiles and build products are excluded from the source export.

## Remaining acceptance work

| Area | Remaining evidence |
| --- | --- |
| Physical monitors | Multiple connected displays, mixed Retina scaling, portrait displays and unplugging a display during streaming. |
| Unattended operation | Real reboot/login, FileVault startup, sleep/wake and repeated app launches without unexpected credential prompts. |
| Real network recovery | Wi-Fi interruption and switching networks during an active connection. |
| Multiple devices/Macs | Live iPhone/iPad contention for one host and switching between two physical Macs. |
| Away access | Broader cellular and unrelated Wi-Fi coverage; earlier successful connections do not establish universal reachability. |
| Accessibility/layout | VoiceOver, large text, floating/hardware keyboards and the full portrait/landscape device matrix. |
| Sustained performance | Measured end-to-end latency, frame rate, CPU, thermals and battery consumption during longer sessions. |
| Distribution | Fresh-Mac setup/upgrade tests, Intel validation if advertised, exact corresponding-source/dependency review, and authorised public signing/notarization. |

No Mac reboot, global network interruption, credential reset or public binary release was performed for these checks. Source publication does not mark the remaining hardware and distribution gates complete.

## Distribution preparation — 2026-11-17

- Both iOS and Apple-silicon Mac **Release archives** built without distribution signing; these are validation artifacts, not installable/public releases. Both resolve version 0.1.0 and build 3 from the project settings.
- The contributor suite passed: 23 tooling tests, 100 Swift core tests and 11 Rust tests. Release tests include actual ad-hoc-signature rejection, unsigned-archive rejection, archive path containment, local-only App Store export settings and notarization-status validation.
- All 52 companion tests passed after replacing a route-fixture timing assumption with confirmed probe completion and listener cancellation. The app's connection deadlines were not changed.
- Real unsigned iOS/Mac archives were rejected before distribution output was created. The installed development Mac app was also rejected by the public-release check.
- Privacy links and the current-source privacy notice were added. App Store review instructions and the Developer ID/notarization workflow are documented.
- **Not performed:** Developer ID signing, live notarization/stapling/Gatekeeper acceptance, signed App Store export/upload or public binary publication. No Developer ID Application or Apple Distribution identity was available. Complete those external steps, licensing/privacy review and the hardware gates above before release.

## Third-party attribution audit — 2026-11-17

- Built unsigned iOS and Apple-silicon Mac Release archives with the revised notice collector and acknowledgments links. No installed app was replaced and no binary was published.
- Verified all 14 mandatory original/supplemental notice files by SHA-256 inside each archive; both pinned Moonlight App Store exception texts remain intact.
- All 29 tooling tests (including six notice regressions), 100 shared Swift tests and 11 Rust tests passed. Pinned client/terminal/crypto dependency verification also passed.
- The generated inventory reports 42 of 367 external Cargo packages for further notice review. This is the full lock graph, including other targets and build dependencies, not a target-specific binary inventory.
- Exact codec sources/build flags, complete native/Rust/web notices, OpenSSL wrapper provenance and whole-app App Store licensing remain unresolved. See THIRD_PARTY.md. This audit does not certify public binary distribution.
