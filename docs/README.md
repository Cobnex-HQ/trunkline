# Developer documentation

Start with the [repository README](../README.md) for prerequisites and a first local build. Trunkline is an early-development source release; a successful build does not establish release readiness or connectivity on every network.

## First contribution

1. Follow [local development](DEVELOPMENT.md) to choose a host, companion, or shared-code workflow.
2. Use the [architecture and code map](ARCHITECTURE.md) to find the relevant implementation.
3. Read [contribution expectations](../CONTRIBUTING.md), then make a focused change on a branch.
4. Run the relevant checks in [testing](TESTING.md). Include actual results and hardware limitations in your pull request.

## Guides

| Guide | What it answers |
| --- | --- |
| [Development](DEVELOPMENT.md) | Setup, incremental builds, signing, generated files and troubleshooting |
| [Architecture](ARCHITECTURE.md) | Module ownership, source entry points, streaming and input boundaries |
| [Testing](TESTING.md) | Suite selection, simulator commands, CI coverage and device acceptance |
| [Validation record](VALIDATION.md) | What was tested, when, and what remains unverified |
| [Transport](../Packages/Transport/README.md) | Rust helper, C bridge and networking experiments |
| [Desktop engine](../Engines/Desktop/README.md) | Pinned upstream engine, patches and runtime build |
| [Branding](../Assets/Branding/README.md) | Logo sources and app icon assets |
| [Security](../SECURITY.md) | Security boundaries and private vulnerability reporting |
| [Privacy](PRIVACY.md) | Current data handling and permission purposes |
| [Third-party notices](THIRD_PARTY.md) | Dependency provenance, adaptations and licensing work |
| [Releasing](RELEASING.md) | Separate Mac distribution, signing, notarization and release gates |
| [App Store](APP_STORE.md) | Companion export, metadata, reviewer access and submission preparation |

## Scope and limitations

These guides cover working in this repository. They are not a stable public SDK or a versioned wire-protocol specification. Check the shared message definitions and both endpoints before changing protocol behaviour. Initial Apple-service distribution steps and the remaining device/network matrix are documented as pending; do not treat a validation-only archive as an installable release.
