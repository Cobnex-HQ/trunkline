# Contributing to Trunkline

Start with the [developer guide](docs/README.md) and [setup instructions](README.md). Read [architecture](docs/ARCHITECTURE.md) before changing module boundaries.

## Workflow

1. Open an issue for a significant feature, protocol change or dependency upgrade. Include the problem and expected behaviour.
2. Create a focused branch from `main`. Keep generated projects, binaries, signing settings, pairing material and device logs out of commits.
3. Put shared policy in `Packages/Core`, native feature behaviour in the relevant app feature, and transport changes in `Packages/Transport`.
4. Add a regression test for a reproducible bug. Run the relevant suites in docs/TESTING.md and report exactly what you tested, including device/OS combinations without personal identifiers.
5. Open a pull request describing the problem, resulting behaviour, validation and remaining limitations. For visual changes, include screenshots without private content.

Keep formatting changes focused. Use four-space Swift indentation, descriptive names and native APIs. Run `cargo fmt` for Rust. Prefer Python’s standard library. Put engine changes in `Engines/Desktop/Patches` and review integrity manifests when updating vendor files.

Contributions must be compatible with GPL-3.0. Retain original notices and record each dependency’s exact source. Submit only code you have the right to license.

## Reporting issues

Provide reproduction steps, expected/actual results, OS and app version, and whether the connection is local or away. Remove passcodes, tokens, pairing links, hostnames, public addresses and device identifiers from logs. Report security concerns privately using SECURITY.md rather than a public issue.
