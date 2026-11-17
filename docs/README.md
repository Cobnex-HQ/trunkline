# Developer documentation

Start with the [repository README](../README.md) to install tools and build from source. Check [validation status](VALIDATION.md) for known limits.

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
| [App Store audit](APP_STORE_AUDIT.md) | Findings, release blockers, privacy reasons and device acceptance |

## Scope and limitations

These guides describe the repository, not a stable SDK or versioned protocol. Check both endpoints before changing messages. Apple distribution and device/network validation remain incomplete. Unsigned validation archives cannot be installed.
