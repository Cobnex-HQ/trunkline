# Architecture

The companion provides desktop, terminal, controls and files for a saved Mac. The host handles pairing, session admission and bundled helper processes.

```text
Apps/iOS ───────── authenticated application protocol ───────── Apps/macOS
   │                                                            │
   ├─ Packages/Core (protocol, geometry, policy, identity) ───────┤
   │                                                            ├─ DesktopSupervisor
   ├─ streaming client ←──────── desktop stream ────────────────┤   └─ patched desktop engine
   └─ Packages/Transport (Rust / C ABI) ── away transport ────────┘
```

## Module boundaries

Both apps use `TrunklineCore` for messages, connections, security and shared policy such as session admission and viewport geometry. Keep platform UI outside this Swift package.

`App/` assembles each app. `Features/` contains its feature code. Resources and the companion design system have separate folders. Some feature models remain large and need further splitting.

`Packages/Transport` builds a Rust static library for physical iOS devices and the Mac helper `TrunklineRemote`. The crate is still named `trunkline-p2p-probe`. Its C interface is in `iOS/P2PProbe.h`. Simulator tests do not prove cellular connectivity.

`Engines/Desktop` pins the upstream revision, patches and dependencies. Preparation rejects an unexpected checkout. The build compiles, audits and stages a runtime for the current Mac architecture, then bundles it with the C supervisor.

## Where to start reading

All paths below are relative to the repository root. Each row identifies entry points, not every supporting file.

| Change | Main entry points |
| --- | --- |
| Companion navigation and appearance | `Apps/iOS/App/TrunklineApp.swift`, `Apps/iOS/App/WorkspaceView.swift`, `Apps/iOS/DesignSystem/` |
| Pairing, reconnect and network selection | `Apps/iOS/Features/Connection/`. `Apps/macOS/App/HostModel.swift` and `Apps/macOS/Features/Connection/` |
| Messages and connection handling | `Packages/Core/Sources/TrunklineCore/Core.swift`, `Transport.swift` and `SessionAdmission.swift` in the same directory |
| Desktop session, zoom and display selection | `Apps/iOS/Features/Desktop/` session and viewport types. Shared viewport/display policies in `Packages/Core` |
| Touch and streamed video integration | `Apps/iOS/Features/Desktop/Engine/`. Ordered client input in `Engines/Client/TrunklineInputStream.c` |
| Host streaming lifecycle | `Apps/macOS/Features/Desktop/` and `Services/DesktopSupervisor/main.c` |
| Mac client | `Apps/macOS/Features/Client/` owns connection state, saved Macs, native AppKit windows and input. `Engines/MacClient/` adapts pairing, H.264 rendering and Opus playback around the shared streaming core |
| Terminal, files and Mac controls | Matching `Features/Terminal`, `Features/Files` and `Features/Controls` directories in each app |
| Keep-awake behaviour | `Apps/macOS/Features/Power/` and shared power policies in `Packages/Core` |
| Away transport | `Packages/Transport/src/`, its `iOS/P2PProbe.h` bridge, and `Apps/macOS/Features/Connection/AwayAccessHost.swift` |

Trace cross-device changes through the companion request, shared message and host handler. Test older peers, authentication and session admission. Terminal access does not verify the separate desktop stream or input permissions.

## Display and input

Preserve the selected display’s aspect ratio. Input and rendering must share the same content rectangle, zoom, pan, letterboxing and orientation transforms. During a monitor switch, distinguish pending metadata from the displayed frame. Test geometry numerically and touch behaviour on hardware.

## Generated and private state

`project.yml` generates the Xcode project. Downloads and native build trees live under `.build/` or ignored vendor directories. `Config/Generated.xcconfig` contains the staged engine path. `Config/Local.xcconfig` contains developer signing choices. Runtime identities, credentials and experiment records never belong in the repository.

## Mac navigation

The sidebar separates the two roles:

- **Remote Macs → Saved Macs** connects to a remote host.
- **My Mac → Sharing** turns sharing on for this Mac and contains its pairing link, QR code, connection passcode and shared folder.
- **My Mac → Desktop / Power** configures this Mac’s capture, input and awake settings.
- **Settings** contains application preferences.

Host credential warnings and sharing actions stay in the host area. A remote connection has its own status and errors. The sidebar footer always describes this Mac.

## Native layout

iPhone uses four workspace tabs. iPad and Mac use native sidebars. Forms group related controls, keep the primary action beside its inputs and limit reading width. Terminal and desktop surfaces retain their available workspace.

Use system typography and Dynamic Type, native buttons, menus and confirmation dialogs. Mobile controls have at least 44-point targets. Quick actions share a consistent grid and label height. Keep the Glacier Fold artwork and named color assets, including light, dark and system appearance. Primary mobile buttons use the navy ControlSurface color for readable white labels.

Screenshot fixtures are debug-only on the simulator. They use synthetic data and do not establish a connection. Their results do not replace physical keyboard, touch, stream or camera acceptance checks.

## M5 script feature comparison

Reviewed both local reference scripts, `M5Server.command` and `M5 Server.command`, on 2026-11-17. Their private connection details are not part of Trunkline. This is a feature audit, not a claim of full parity.

| Script feature | Current Mac client | Remaining work |
| --- | --- | --- |
| Remote desktop | Native streamed desktop, mouse, keyboard, display selection and full screen | Separate physical-Mac acceptance. No SSH/VNC fallback or private virtual desktop session |
| SSH/admin terminal, persistent tmux and session listing | No Mac client terminal workspace | Port the existing authenticated terminal client and session UI. SSH/tmux interoperability is separate work |
| SFTP, file/folder upload and download | No Mac client file workspace | Port shared-folder browsing and transfers. SFTP and recursive folder transfer need separate support |
| CPU, memory, GPU, disk and network diagnostics | Not implemented as remote diagnostic tools | Typed host reports and a native status view, including capability/permission handling |
| Battery, thermal, sleep and lid reports | Remote keep-awake control only | Add remote power diagnostics. Local host power settings are not remote reports |
| Firewall, FileVault, logins and tool versions | Not implemented | Read-only reports with unavailable states |
| Docker health, container resources and live bot logs | Not implemented | Optional configurable service monitoring and log streaming |
| Diagnostic snapshot export and confirmed bot restart | Not implemented | Report export and explicit confirmation for configured service actions |

The iPhone/iPad terminal can run diagnostic commands manually, but that is not equivalent to native diagnostic screens. The Mac client does not inherit all mobile features merely by sharing the host protocol. Service names and project paths must be configured by each user rather than copied from a personal script.

Sharing uses a single on/off switch on its own page. Turning sharing off and disconnecting a device require confirmation. Passcode, shared-folder and Away changes also warn when a device or terminal session is active. The dialog reports running terminal counts and makes clear that sharing changes preserve those jobs. The Sharing page observes terminal summaries as sessions start or exit. Global Settings has no sharing controls.
