# Contributing to Trunkline

Thanks for helping improve Trunkline. Start with the setup commands in README.md and read docs/ARCHITECTURE.md before changing module boundaries.

## Workflow

1. Open an issue for a significant feature, protocol change or dependency upgrade. Include the problem and expected behaviour.
2. Create a focused branch from `main`. Keep generated projects, binaries, signing settings, pairing material and device logs out of commits.
3. Put shared policy in `Packages/Core`, native feature behaviour in the relevant app feature, and transport changes in `Packages/Transport`.
4. Add a regression test for a reproducible bug. Run the relevant suites in docs/TESTING.md and report exactly what you tested, including device/OS combinations without personal identifiers.
5. Open a pull request describing the problem, resulting behaviour, validation and remaining limitations. For visual changes, include screenshots without private content.

Avoid unrelated formatting changes. Swift uses four spaces, descriptive types and native platform APIs. Rust follows `cargo fmt`; Python tooling uses the standard library unless a dependency is justified. The pinned vendor trees are integrity checked: put engine modifications in `Engines/Desktop/Patches`, and update manifests deliberately when changing a vendored source.

New contributions must be compatible with the project's GPL-3.0 licence. Retain third-party notices and document new dependencies and their exact source. Do not submit code you cannot licence for this project.

## Reporting issues

Provide reproduction steps, expected/actual results, OS and app version, and whether the connection is local or away. Remove passcodes, tokens, pairing links, hostnames, public addresses and device identifiers from logs. Report security concerns privately using SECURITY.md rather than a public issue.
