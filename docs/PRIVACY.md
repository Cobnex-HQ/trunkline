# Trunkline privacy notice

Updated 19 November 2026. Covers the current source release and development builds. Verify App Store disclosures against the exact release binary.

Trunkline connects your iPhone or iPad to your chosen Mac. This release has no Trunkline-operated account, advertising or analytics service.

## Information used by the app

- **Pairing:** saved Mac names, addresses, certificate fingerprints and preferences identify connections. Secrets and identities stay in local platform storage, including Keychain. Pairing QR codes are sensitive.
- **Remote content:** desktop video/audio, input, terminal commands/output, files and clipboard content pass between paired devices. Trunkline does not upload them to publisher-operated storage. Transferred files remain until you remove them.
- **Clipboard:** manual actions transfer text only. Optional sync is off by default and saved per Mac. Mac-to-device sync receives text while the window is active. Both-directions sync also reads newly copied device text and may trigger an iOS paste-permission prompt. Trunkline does not save clipboard history or enable Universal Clipboard for received text. Disconnect stops syncing.
- **Permissions:** the camera scans QR codes, Face ID/Touch ID unlocks saved credentials, and local-network access connects devices. The Mac needs capture and input permissions. OS approval does not authorise unpaired devices.
- **Diagnostics:** local logs may contain connection events, addresses, app names and errors. Redact logs and screenshots before sharing. This release does not automatically upload diagnostics to the publisher.

## Away access and third parties

Away-access discovery services may be operated by third parties and can observe IP addresses, peer IDs and connection timing. App traffic uses an authenticated direct connection, with no relay fallback for desktop, terminal or files. This does not provide anonymity or guarantee connectivity.

Apple handles App Store/TestFlight downloads, diagnostics and feedback under its policies. Visiting project pages or filing issues shares information with GitHub under its policies.

## Control and retention

Disconnect ends a connection. Forget Mac removes a saved companion pairing. Revoke host desktop pairings to remove device access. These actions do not delete transferred files, saved terminal output, OS records or support reports. Uninstalling may leave Keychain items, backups and externally saved files.

While the app remains in memory, it retains the authenticated connection passcode to reconnect after switching apps. Disconnect clears it. After the process ends, reconnection requires the saved Keychain passcode and platform authentication, or manual passcode entry.

Disable Away access to stop its connection setup activity. Revoke camera, network, capture or input permissions in system settings to disable those features.

Trunkline does not sell user data or include advertising/tracking SDKs. Infrastructure providers, Apple, GitHub and modified third-party builds have their own retention policies.

## Questions and security reports

Project support: https://github.com/Cobnex-HQ/trunkline/issues

Report security issues privately through [SECURITY.md](../SECURITY.md). Keep passwords, pairing links, private files and unredacted logs out of public issues.
