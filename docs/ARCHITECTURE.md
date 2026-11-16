# Architecture

The companion presents a saved Mac connection and a workspace containing desktop, terminal, controls and files. The Mac host owns pairing, session admission and the lifecycle of its bundled helpers.

```text
Apps/iOS ───────── authenticated application protocol ───────── Apps/macOS
   │                                                            │
   ├─ Packages/Core (protocol, geometry, policy, identity) ───────┤
   │                                                            ├─ DesktopSupervisor
   ├─ streaming client ←──────── desktop stream ────────────────┤   └─ patched desktop engine
   └─ Packages/Transport (Rust / C ABI) ── away transport ────────┘
```

## Module boundaries

`TrunklineCore` is a local Swift package. Both apps depend on it rather than compiling duplicate copies of shared source. It contains serialisable messages, connection/security primitives and independently testable policy such as session admission and viewport geometry. Keep platform UI out of this package.

The apps organise code by feature. `App/` composes the application; `Features/` owns connection, desktop, terminal, controls, files and Mac power behaviour; resources and the companion design system have explicit homes. Some feature models remain large and can be split further as their interfaces stabilise. This is a module boundary cleanup, not a claim that every view/model is already minimal.

`Packages/Transport` builds a Rust static library for physical iOS devices and a command-line helper bundled in the Mac app as `TrunklineRemote`. Its crate currently retains the internal `trunkline-p2p-probe` name. The C ABI is declared in `iOS/P2PProbe.h`. Simulator transport capabilities differ from physical devices; simulator UI tests do not prove cellular connectivity.

`Engines/Desktop` records an upstream revision, patch series and dependency lock. Preparation rejects an unexpected checkout rather than overwriting unrelated edits. The development build compiles the engine for the current Mac architecture, audits it and stages a versioned runtime. The app bundles that runtime and the small C supervisor.

## Where to start reading

All paths below are relative to the repository root. Each row identifies entry points, not every supporting file.

| Change | Main entry points |
| --- | --- |
| Companion navigation and appearance | `Apps/iOS/App/TrunklineApp.swift`, `Apps/iOS/App/WorkspaceView.swift`, `Apps/iOS/DesignSystem/` |
| Pairing, reconnect and network selection | `Apps/iOS/Features/Connection/`; `Apps/macOS/App/HostModel.swift` and `Apps/macOS/Features/Connection/` |
| Messages and connection handling | `Packages/Core/Sources/TrunklineCore/Core.swift`, `Transport.swift` and `SessionAdmission.swift` in the same directory |
| Desktop session, zoom and display selection | `Apps/iOS/Features/Desktop/` session and viewport types; shared viewport/display policies in `Packages/Core` |
| Touch and streamed video integration | `Apps/iOS/Features/Desktop/Engine/`; ordered client input in `Engines/Client/TrunklineInputStream.c` |
| Host streaming lifecycle | `Apps/macOS/Features/Desktop/` and `Services/DesktopSupervisor/main.c` |
| Terminal, files and Mac controls | Matching `Features/Terminal`, `Features/Files` and `Features/Controls` directories in each app |
| Keep-awake behaviour | `Apps/macOS/Features/Power/` and shared power policies in `Packages/Core` |
| Away transport | `Packages/Transport/src/`, its `iOS/P2PProbe.h` bridge, and `Apps/macOS/Features/Connection/AwayAccessHost.swift` |

For an operation that crosses devices, trace the companion request, shared message definition and host handler together. A desktop video frame and an application-protocol response travel through different integrations; successful terminal access does not by itself verify streaming or input permissions. Protocol changes must consider an older installed peer and authentication/session admission, not just two matching development builds.

## Display and input

Desktop layout must preserve the selected Mac display's aspect ratio. Coordinate conversion must use the same content rectangle and transforms as rendering, including letterboxing, zoom, pan and orientation. Monitor metadata and a pending switch must not be confused with the previously rendered frame. Cover geometry numerically and validate the actual renderer/touch path on hardware.

## Generated and private state

`project.yml` generates the Xcode project. Downloads and native build trees live under `.build/` or ignored vendor directories. `Config/Generated.xcconfig` contains the staged engine path; `Config/Local.xcconfig` contains developer signing choices. Runtime identities, credentials and experiment records never belong in the repository.
