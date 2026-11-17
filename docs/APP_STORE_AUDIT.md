# App Store audit

17 November 2026. Scope: iPhone and iPad companion, version 0.1.0, build 3. The Mac host is distributed separately. **Do not submit this build yet.** Apple decides approval after reviewing the actual binary, metadata and working service.

## Changes

- Removed the redundant global ATS exception. Local networking remains enabled for host discovery. Test the release on real local and external networks before shipping.
- Declared elapsed-time measurement and file metadata access in the app privacy manifest.
- Blocked terminal graphics commands from reading or deleting companion files. Inline graphics remain supported.
- Replaced the unsupported-codec process abort with a decoder recovery request.
- Replaced the OpenSSL artifact with version 3.6.5000, verified its release digest and pinned publisher signature, and bundled the matching wrapper licence. Bootstrap no longer removes SDK signatures.
- Added native setup help, privacy and support access before and after connection.
- Added an archive preflight and an export guard for configuration, required-reason declarations and open notice findings.

## Release blockers

| Item | Evidence and next step |
| --- | --- |
| OpenSSL privacy manifest | The device framework imports `stat`, `fstat` and `lstat`, but declares no required-reason APIs. Obtain a correctly declared, signed SDK or build a reviewed replacement from source. Do not edit the signed artifact or copy the app’s reasons into it without verifying SDK use. |
| Licence clearance | 42 of 367 locked external Rust packages lack standalone notices recognised by the collector. Reconcile exact terms and shipping targets. Verify FFmpeg/Opus sources and flags, other native/web notices, and the App Store licence basis for Trunkline and every linked component. See [third-party audit](THIRD_PARTY.md). |
| Developer enrollment | Owner confirmed they are not enrolled. A paid team, App Store Connect app record and distribution signing are needed for TestFlight and App Store release. |
| Reviewer access | Provide an isolated demo Mac, private pairing credentials, working host-download instructions and a reliable route from Apple’s network. Simulator presentation fixtures are not a functional demo. |
| Release acceptance | Complete the device/network matrix below, privacy labels, encryption documentation, screenshots, age rating and Xcode validation against the final signed binary. |

## Privacy declarations

| Category | Reason | Source use |
| --- | --- | --- |
| UserDefaults | CA92.1 | App preferences and saved connection metadata |
| SystemBootTime | 35F9.1 | Elapsed heartbeat and latency measurements. Raw boot time is not transmitted |
| FileTimestamp | C617.1, 3B52.1 | App-container files and documents explicitly selected through the system file picker |

These declarations cover the app. Embedded frameworks need their own declarations. The import scanner covers selected symbols, not every API, SDK behaviour or App Store privacy answer. Trace remaining static-library file calls before final privacy sign-off.

## Device acceptance

Record build, OS, device class, network and outcome without identifiers or secrets.

| Test | Required result |
| --- | --- |
| Fresh installation | Setup explains the Mac requirement. QR scan and manual import work. Camera/local-network denial has a usable recovery path |
| iPhone and iPad | Portrait, landscape, resized iPad windows, software/floating/hardware keyboards and large text remain usable |
| Accessibility | VoiceOver can pair, connect, navigate, type and disconnect. Gesture actions have accessible menu alternatives. Reduce Motion is respected |
| Desktop | Touch/click, drag, scroll, zoom, rotation, Mission Control and display switching work with mixed display scaling |
| Terminal and Files | No local command execution. Transfers, document picker, cancellation and reconnect work without exposing other companion files |
| Connectivity | IPv6-only/DNS64/NAT64, local Wi-Fi, unrelated Wi-Fi and cellular. Test denial, interruption, recovery, host sleep and contention between devices |
| Lifecycle | Backgrounding disconnects and obscures sensitive content. Foregrounding permits reconnection. No unsupported background-service claims |
| Endurance | Long sessions without crashes, rising memory, excessive heat or unexpected Keychain prompts |

Current results and remaining hardware checks are in [VALIDATION.md](VALIDATION.md). Simulator tests do not establish physical input accuracy, external reachability or IPv6-only support.

## Review basis

Trunkline mirrors a user-controlled Mac. Terminal commands execute on that Mac, not in a downloaded local runtime. It has no publisher account signup, storefront, subscription or device-wide VPN. Keep those claims aligned with the release. Generic host mirroring is distinct from remote clients for a specific software service, but that distinction does not guarantee acceptance.

Relevant Apple requirements: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) sections 2.1, 2.5, 4.2.7, 5.1 and 5.2, [SDK privacy and signature requirements](https://developer.apple.com/support/third-party-SDK-requirements/), and [required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
