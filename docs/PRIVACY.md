# Trunkline privacy notice

Last updated: 17 November 2026. This notice describes the current Trunkline source release and development builds. Public App Store privacy disclosures must be checked against the exact release binary before submission.

Trunkline connects an iPhone or iPad to a Mac chosen by its user. There is no Trunkline-operated account service, advertising service or analytics backend in this release.

## Information used by the app

- **Pairing and security:** Mac names, network addresses, host certificate fingerprints and connection preferences identify saved Macs. Connection secrets and identities are stored locally using platform security facilities, including Keychain. Treat pairing QR codes as sensitive.
- **Remote content:** desktop video/audio, pointer and keyboard input, terminal commands/output, selected files and clipboard content pass between the paired devices to provide the requested features. Trunkline does not upload that content to a publisher-operated storage service. Files copied to a device remain there until the user removes them.
- **Permissions:** camera access scans pairing QR codes; Face ID/Touch ID can unlock saved credentials; local-network access connects devices. The Mac separately requires screen-capture and input-control permissions. An operating-system permission does not grant access to an unpaired device.
- **Diagnostics:** local logs can include connection events, device/network addresses, application names and errors. Support reports or screenshots may contain personal information; review and redact them before sharing. This release has no automatic publisher-operated diagnostic upload.

## Away access and third parties

When Away access is configured, its peer-discovery and connection-establishment infrastructure can observe network metadata, including IP addresses, peer identifiers and connection timing. This infrastructure can be operated by third parties. The current transport allows application traffic only on an authenticated direct connection; it does not use a relay fallback for desktop, terminal or file traffic. Do not interpret this as anonymity or guaranteed connectivity on every network.

Apple processes App Store/TestFlight downloads and any diagnostics or feedback shared through those services under Apple's policies. Visiting the project's GitHub pages or filing an issue also shares information with GitHub. Their handling of that information is separate from the local app.

## Control and retention

Disconnect to end a connection. Use Forget Mac to remove a saved pairing from the companion, and revoke desktop pairings on the host when a device should no longer have access. These actions do not delete files already transferred, terminal output saved elsewhere, operating-system records or copies shared in support reports. Removing the app is not a guarantee that Keychain items, backups or externally saved files are erased.

Disable Away access if you do not want its connection-establishment activity. You can also revoke camera, network, screen-capture and input permissions in system settings; affected features will stop working.

The project does not sell user data or embed advertising/tracking SDKs. No claim is made about the independent retention policies of network infrastructure, Apple, GitHub or a modified third-party build.

## Questions and security reports

Project support: https://github.com/Cobnex-HQ/trunkline/issues

For security issues, use the repository's private vulnerability-reporting channel described in [SECURITY.md](../SECURITY.md). Never put passwords, pairing links, private files or unredacted diagnostic logs into a public issue.
