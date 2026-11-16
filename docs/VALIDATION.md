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
