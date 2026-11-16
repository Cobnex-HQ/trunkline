# Distribution and release gates

Trunkline uses two distribution channels:

- **iPhone/iPad:** TestFlight for beta testing, then the App Store. See [companion submission](APP_STORE.md).
- **Mac host:** a Developer ID-signed, notarized, stapled DMG downloaded separately. The host intentionally remains outside App Sandbox; it is not a Mac App Store target.

The repository currently publishes source. No public binary, notarized download or App Store listing exists yet. CI validates source and does not upload applications, installers or credentials.

## Mac release workflow

Prepare the pinned desktop runtime and project using the development build instructions. Keep the installed app separate from all archive/release staging paths. Obtain a **Developer ID Application** certificate with its private key through your paid Apple Developer membership. An Apple Development certificate or ad-hoc signature is insufficient.

```sh
python3 Scripts/release.py archive mac --arch arm64 --team YOURTEAMID \
  --identity 'Developer ID Application: YOUR PUBLISHER (YOURTEAMID)' \
  --output dist/Trunkline-Mac.xcarchive
```

The initial advertised Mac architecture should be Apple silicon. Use `--arch x86_64` only after building the matching desktop runtime and validating on Intel; this command does not manufacture a universal binary.

Store notarization credentials locally using Apple's interactive `notarytool store-credentials` flow. Use an app-specific password or an authorised App Store Connect API key as supported by Apple. Never put those credentials in chat, shell scripts, Git, or CI logs:

```sh
xcrun notarytool store-credentials trunkline-notary
python3 Scripts/release.py mac --archive dist/Trunkline-Mac.xcarchive \
  --identity 'Developer ID Application: YOUR PUBLISHER (YOURTEAMID)' \
  --notary-profile trunkline-notary --output dist
```

The packaging command verifies the Release app and every bundled Mach-O signature, rejects debugger entitlements, checks secure timestamps/Hardened Runtime, and verifies bundled helpers and deployment targets. It copies the archived app to staging; it never re-signs or changes an installed copy.

It submits the copied app for notarization, requires an **Accepted** result, staples/validates the ticket, and checks Gatekeeper. It then builds/signs/notarizes/staples the DMG and verifies it again. A versioned output folder containing the DMG and SHA-256/notarization metadata appears only after all steps succeed. It refuses existing release output. Notary reports remain in ignored `.build/notarization`; inspect warnings before publishing. A timed-out or rejected upload does not become a release.

These Apple-service steps require credentials and have not been validated end-to-end without a Developer ID certificate. Notarization is a technical distribution check, not completion of the licensing or hardware gates below. No command automatically publishes to GitHub.

## Local validation and development packages

```sh
python3 Scripts/release.py archive mac --unsigned --arch arm64 \
  --output .build/validation/Trunkline-Mac.xcarchive
python3 Scripts/release.py verify-mac --app /path/to/release/Trunkline.app
```

The first command proves Release compilation without creating a distributable archive. The second checks Developer ID release eligibility; an installed development build is expected to fail it.

`Scripts/distribution.py mac` remains available for clearly labelled **local development** DMGs. It does not notarize them or make them ready for public distribution.

## Before publishing binaries

1. Resolve the attribution audit findings in [THIRD_PARTY.md](THIRD_PARTY.md), including generated `ThirdParty/NOTICE-REVIEW.json` entries and wrapper provenance. Review licences, original notices and complete corresponding source for the exact desktop/client/codec/crypto dependency graph. Provenance hashes and upstream links alone do not replace required source and build materials. Explicitly review App Store permissions for the iOS dependency graph and our own code.
2. Complete physical-device, display, input, security, reconnect and network checks in [TESTING.md](TESTING.md); [VALIDATION.md](VALIDATION.md) records the outstanding hardware work.
3. Validate a fresh Mac installation and upgrade, permission persistence, and the advertised architectures/OS versions. Changing signing identity can require renewed OS permission or Keychain authorisation; do not promise that moving from a personal build is prompt-free.
4. Confirm privacy disclosures, encryption declarations, reviewer access, support details and actual download URLs. Verify that the in-app privacy links open the current public notice.
5. Review notary logs, inspect the final mounted DMG and verify its checksum. Download it through a browser to a clean Mac and test Gatekeeper, launch and pairing. Check with networking unavailable after the ticket has been stapled.
6. Publish only the reviewed DMG/metadata and exact corresponding source. Keep credentials, logs, profiles, archives and validation-only builds private. Upload the reviewed iOS build to TestFlight/App Store Connect separately.

`Scripts/distribution.py source --output PATH.tar.gz` exports tracked source files, rejecting external symlinks. Inspect the archive and any additional corresponding-source materials before distribution.

Apple references: [Developer ID](https://developer.apple.com/developer-id/), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/), [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
