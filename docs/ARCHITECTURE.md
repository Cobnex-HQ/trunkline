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

## Display and input

Desktop layout must preserve the selected Mac display's aspect ratio. Coordinate conversion must use the same content rectangle and transforms as rendering, including letterboxing, zoom, pan and orientation. Monitor metadata and a pending switch must not be confused with the previously rendered frame. Cover geometry numerically and validate the actual renderer/touch path on hardware.

## Generated and private state

`project.yml` generates the Xcode project. Downloads and native build trees live under `.build/` or ignored vendor directories. `Config/Generated.xcconfig` contains the staged engine path; `Config/Local.xcconfig` contains developer signing choices. Runtime identities, credentials and experiment records never belong in the repository.
