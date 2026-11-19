# Validation status

Development results are recorded below by date. See [test instructions](TESTING.md) and [release requirements](RELEASING.md).

## Clipboard controls and consent — 2026-11-19

- Added explicit copy/transfer actions, acknowledged completion, bounded waits and per-Mac opt-in text sync. Backgrounding stops sync. Incoming text does not replace a newer local copy. Timed-out legacy replies are ignored until reconnect.
- Passed 36 tooling, 109 shared Swift and 14 Rust tests. Both simulators passed all 82 companion tests, including clipboard/file-operation isolation. Reviewed the native clipboard screen on iPhone.
- Existing clipboard messages remain compatible with older Mac hosts. Physical paste-permission and cross-device acceptance remain pending.

## Bounded away connection setup — 2026-11-19

- Reproduced the old long setup wait using the real transport executable and an offline loopback endpoint. Clients now stop after 45 seconds with at most five setup attempts and exponential delays of 2, 4, 8 and 16 seconds. The Mac host continues listening with capped backoff.
- Verified cancellation during backoff, bounded failure, continued host availability and direct-only traffic. Late iOS worker events no longer replace the first failure.
- Passed 36 tooling, 104 shared Swift and 14 Rust tests. All 81 companion tests passed on both iPhone and iPad simulators. The native iOS release library built and the Mac away client typechecked.
- Signed updates were installed on both physical devices. The iPhone app launched. The iPad was locked, so its launch remains pending. The Mac update was installed and reopened with the same signing requirement and installation path. Its listening socket and system-awake assertion were verified. No terminal jobs were running before restart.
- Loopback and simulator results do not establish cellular reachability. Physical-device checks on unreachable hosts and restrictive networks remain pending.

## Companion connection restoration — 2026-11-19

- Reproduced background-return and relaunch failures with local connection fixtures. Backgrounding now releases the connection without discarding the in-memory resume credential. Returning restores the workspace and selected running terminal without creating another shell.
- Full relaunch uses the existing protected Keychain credential through platform authentication. Explicit Disconnect, changed pairing, cancelled unlock and busy-host rejection prevent unwanted reconnection.
- All 79 companion tests passed on iPhone and iPad simulators. New tests cover both restoration paths, stale unlock completion, duplicate activation, explicit disconnect and another device using the host.
- Signed builds were installed on both physical devices. The Mac host was not restarted. Device authentication and hands-on background/relaunch acceptance remain to be checked locally.

## Terminal resize and colour environment — 2026-11-18

- Reproduced missing resize signals with the production Mac PTY launcher. Its foreground process group was unset. The new bundled launcher acquires the controlling terminal before starting the shell.
- Verified resize signals reach a foreground job across portrait and landscape sizes. The test also verifies that inherited automation settings cannot disable terminal colour. Shell exit, foreground cleanup and remote-power checks pass.
- Started Claude in a temporary configuration without an account or model request. It emitted colour, responded to menu navigation and redrew after resizing in both directions.
- The signed Mac build and bundled-runtime verification pass. After approval, the update was installed at the same path and the existing Claude session ended cleanly. Installed binaries match the verified build. Sharing restarted with an active listener and a system-awake assertion.
- Existing keyboard, scroll-dismissal and rotation checks pass on iPhone and iPad simulators. The separately reported app-navigation failure has not been reproduced on physical devices. Simulator results do not close that hardware check.

## Native UI and sharing controls — 2026-11-17

- Selected a native grouped workspace after comparing three layout proposals. Updated connection, desktop, controls, terminal, files, help and Mac settings while retaining the Glacier theme and system appearance option.
- Passed 35 tooling, 104 shared Swift, 11 Rust, 61 companion and 3 UIKit viewport tests. Native terminal/power checks and sharing-confirmation checks passed, including cancellation and preserving running terminal jobs.
- The final Mac functional run passed four tests. The opt-in live-stream test and unavailable native window capture were skipped. Ten Mac window captures had already been reviewed in light and dark appearance.
- Reviewed eight main mobile views across both devices, portrait/landscape and light/dark appearance. Detailed sheets, menus and confirmations were also captured on iPhone portrait/light and iPad landscape/dark. The iPad file picker needed a longer simulator-provider startup wait before displaying its native content.
- Signed builds were installed on the Mac, iPhone and iPad. The Mac update preserved its signing requirement, passed bundle verification and restarted its sharing listener and keep-awake assertion. No Mac terminal jobs were running during installation.
- Both mobile devices were locked after the final installation, so their final launches require local unlock. Simulator captures do not substitute for this device check.
- Screenshot fixtures use synthetic data. They do not verify live streaming, camera scanning, authentication or physical touch input. Physical-device acceptance remains required.

## Native terminal list and confirmed shutdown — 2026-11-17

- iPhone and iPad simulators each passed 61 companion tests. New coverage checks UIKit section grouping and selection, duplicate end requests, confirmation before removal, timeout recovery and disconnect cleanup.
- A real Mac PTY regression reproduced a stubborn foreground process surviving the old close path. The corrected path stops it, waits before removing the session, preserves another terminal and waits for cleanup on host quit.
- Passed 35 tooling, 102 shared Swift and 11 Rust tests, plus the native terminal and remote-power checks. Older session messages remain compatible.
- Reviewed the UIKit session list on iPhone in light mode and iPad in dark mode. Running sessions and ended history have separate sections with native swipe actions and confirmation dialogs.
- Signed builds were installed on both devices. Both were locked, so physical-device launch and hands-on session acceptance remain pending.
- Installed and opened the signed Mac update at the same path with the same signing requirement. No terminal jobs were running. Verified remote-access readiness, the listening port and the system-awake assertion after restart.
- Shutdown covers processes in the terminal’s POSIX session. Processes that deliberately detach into a different session are outside this scope. The list does not include sessions created by Terminal.app or iTerm.

## Terminal scrolling, exit and remote power — 2026-11-17

- Both iPhone and iPad simulators passed 58 companion tests. Regressions cover scroll position during output, following the latest output, history paging versus full-screen app keys, read-only ended sessions and exit navigation.
- Passed a real Mac PTY exit test, including final output and creating the next session. Remote keep-awake checks exercise IOKit assertions, active-session protection, local-only lid settings, old-host compatibility and protocol serialization.
- Passed 35 tooling, 100 shared Swift and 11 Rust tests. CI now includes the native terminal/power checks.
- Signed iPhone/iPad builds were installed on both devices. Devices were locked, so launch and hands-on acceptance remain pending.
- Signed Mac build and bundled-runtime verification passed. After approval to end the existing Claude session, the update was installed at the same path with the same signing requirement. Remote access restarted and the Trunkline system-awake assertion was verified. Permissions were not reset.

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

## Mac-to-Mac client — 2026-11-17

- Added an AppKit desktop window with native video/audio playback, physical keyboard and mouse input, saved Macs, display selection and remote controls.
- Passed five native Mac tests, including real H.264 decoding and pairing with an isolated bundled host. The live fixture received desktop frames and verified injected mouse and key events at the macOS event boundary.
- Passed local TCP authentication, admission rejection, cancellation and away-tunnel lifetime checks. The shared suite passed 104 Swift, 35 tooling and 11 Rust tests. The iOS companion simulator suite also passed.
- Local checks used two processes on one Apple-silicon Mac. Two physical Macs, separate-network access, audible playback, Intel execution, non-US keyboards and sustained performance still need acceptance testing.
- The Mac client currently provides desktop viewing and controls. Terminal and files remain mobile-client features. Away connections require stopping this Mac’s own host access because both use the same local tunnel ports.

## Clipboard and iPad windows — 2026-11-19

- Added acknowledged clipboard transfers, per-Mac sync consent and timeout handling. A delayed reply cannot overwrite a newer local copy. Only the focused window may sync.
- Each iPad window owns its connection, navigation and resume state. Saved-Mac mutations merge from storage. Keep-awake claims are released per window.
- The native desktop engine remains process-wide. Its lease lasts through asynchronous shutdown, including repeated close requests. A second window gets an explicit limit instead of redirecting the first stream's video or input. Away access also remains limited to one tunnel per process.
- Passed 85 companion tests on each simulator, including two simultaneous local fixture connections, backgrounding one window, clipboard acknowledgments and native engine ownership. Shared Swift, tooling and Rust suites passed. An additional clipboard focus regression passed after reproducing the overwrite.
- Terminal, Controls and passcode portrait → landscape → portrait UI tests passed on both simulators. Reviewed iPhone terminal and iPad controls captures.
- Physical Stage Manager, two real Macs, clipboard privacy prompts and reconnecting a desktop after closing another window remain acceptance checks. No device installation or public release is claimed by these checks.

## Adaptive streaming — 2026-11-19

- The iPhone/iPad viewer samples fresh video-frame loss every two seconds. Repeated loss reduces bitrate, with a ten-second cooldown. Twenty healthy seconds allow gradual recovery up to the chosen quality limit. Missing, stale or invalid samples cannot raise quality. Loopback RTT is not used.
- A session-bound, authenticated host API controls the VideoToolbox encoder. Bitrate changes recreate the encoder between frames while retaining capture, transport, input and resolution. An encoder failure restores the negotiated limit and disables adaptation. Older hosts receive no new commands.
- An isolated live host/client test on Apple silicon lowered and restored bitrate, verified the host’s bitrate cap, applied bitrate and continued frame delivery, and reported no playback failure. This does not measure sustained latency, packet-loss recovery on a real cellular route, thermals or battery use.
- Passed 114 shared Swift tests, 36 tooling tests, 14 Rust tests, 86 companion tests on each simulator and the native capture/input/display/quality checks. The engine patch compiled and the staged bundle passed runtime dependency audit.
- Mac client automatic adaptation is not yet wired to video-loss telemetry. It can use the same patched host, but its current quality selection stays manual.
