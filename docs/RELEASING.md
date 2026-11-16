# Release gates

The initial repository publishes source only. CI does not upload applications, SDK archives or installers.

A public binary release must first:

1. Review licences, original notices and complete corresponding source for the exact desktop/client/codec/crypto dependency graph. Provenance hashes and upstream links alone do not replace the required source and build materials.
2. Validate Apple silicon and Intel builds if both are advertised. Audit architecture, deployment target and runtime dependencies with the supplied scripts.
3. Complete the physical-device, display, input, security, reconnect and network checks in TESTING.md.
4. Use the maintainer's authorised signing/notarization workflow, with credentials in private CI secrets or local Keychain profiles, never source files.
5. Document supported OS versions, known limitations, upgrade/rollback behaviour and permission changes.

`Scripts/distribution.py source --output PATH.tar.gz` exports tracked source files from Git, rejecting external symlinks. Inspect the archive before distribution. `Scripts/distribution.py mac` makes a **local development** DMG from a verified signed app; it does not make that app approved for public redistribution. Do not attach that output to a public release until the gates above are complete.
