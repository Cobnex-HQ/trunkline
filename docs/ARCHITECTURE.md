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
| Terminal, files and Mac controls | Matching `Features/Terminal`, `Features/Files` and `Features/Controls` directories in each app |
| Keep-awake behaviour | `Apps/macOS/Features/Power/` and shared power policies in `Packages/Core` |
| Away transport | `Packages/Transport/src/`, its `iOS/P2PProbe.h` bridge, and `Apps/macOS/Features/Connection/AwayAccessHost.swift` |

Trace cross-device changes through the companion request, shared message and host handler. Test older peers, authentication and session admission. Terminal access does not verify the separate desktop stream or input permissions.

## Display and input

Preserve the selected display’s aspect ratio. Input and rendering must share the same content rectangle, zoom, pan, letterboxing and orientation transforms. During a monitor switch, distinguish pending metadata from the displayed frame. Test geometry numerically and touch behaviour on hardware.

## Generated and private state

`project.yml` generates the Xcode project. Downloads and native build trees live under `.build/` or ignored vendor directories. `Config/Generated.xcconfig` contains the staged engine path. `Config/Local.xcconfig` contains developer signing choices. Runtime identities, credentials and experiment records never belong in the repository.
