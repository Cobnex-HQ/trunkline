# Distribution and release gates

Trunkline uses two distribution channels:

- **iPhone/iPad:** TestFlight for beta testing, then the App Store. See [companion submission](APP_STORE.md).
- **Mac host:** a Developer ID-signed, notarized, stapled DMG downloaded separately. The host intentionally remains outside App Sandbox. It is not a Mac App Store target.

Only source is published. Public binaries and App Store listings are not available. CI does not upload apps, installers or credentials.

## Mac release workflow

Build the desktop runtime and project using the development guide. Keep archive paths separate from installed apps. Mac distribution requires paid Apple Developer membership and a **Developer ID Application** certificate with its private key. Development and ad-hoc signatures do not qualify.

```sh
python3 Scripts/release.py archive mac --arch arm64 --team YOURTEAMID \
  --identity 'Developer ID Application: YOUR PUBLISHER (YOURTEAMID)' \
  --output dist/Trunkline-Mac.xcarchive
```

Advertise Apple silicon first. Use `--arch x86_64` only with a matching runtime tested on Intel. This does not create a universal binary.

Store notarization credentials in Keychain using the interactive command below. Apple supports app-specific passwords or authorised App Store Connect API keys. Keep credentials out of chat, scripts, Git and logs.

```sh
xcrun notarytool store-credentials trunkline-notary
python3 Scripts/release.py mac --archive dist/Trunkline-Mac.xcarchive \
  --identity 'Developer ID Application: YOUR PUBLISHER (YOURTEAMID)' \
  --notary-profile trunkline-notary --output dist
```

Packaging checks every bundled Mach-O signature, secure timestamps, Hardened Runtime, helpers and deployment targets. It rejects debugger entitlements and works on a staging copy of the archive. Installed apps stay unchanged.

The script notarizes the app, requires **Accepted**, staples and validates its ticket, then checks Gatekeeper. It signs and notarizes the DMG and repeats verification. Only successful runs create the versioned DMG and checksum/notarization metadata. Existing output is never replaced. Review reports in `.build/notarization` before publishing.

Live signing and notarization have not been tested end to end. They require Developer ID credentials. Notarization does not complete the licensing or hardware checks below. Nothing is automatically published to GitHub.

## Local validation and development packages

```sh
python3 Scripts/release.py archive mac --unsigned --arch arm64 \
  --output .build/validation/Trunkline-Mac.xcarchive
python3 Scripts/release.py verify-mac --app /path/to/release/Trunkline.app
```

The first command checks Release compilation without producing an installable archive. The second checks Developer ID eligibility and should reject development builds.

`Scripts/distribution.py mac` creates local development DMGs only. It does not notarize them.

## Before publishing binaries

1. Resolve [licensing findings](THIRD_PARTY.md), including `ThirdParty/NOTICE-REVIEW.json`, OpenSSL wrapper provenance and App Store permissions. Supply exact corresponding sources and build instructions for all required components. Hashes and upstream links alone are insufficient.
2. Complete [hardware and network tests](TESTING.md). See [outstanding checks](VALIDATION.md).
3. Test fresh installation, upgrades, permissions and advertised OS/architecture support. Signing changes can trigger new OS or Keychain approval.
4. Verify privacy disclosures, encryption declarations, reviewer access, support/download URLs and in-app privacy links.
5. Review notary logs, the mounted DMG and its checksum. Download through a browser to a clean Mac. Test Gatekeeper, launch and pairing, including offline ticket validation.
6. Publish the reviewed DMG, metadata and exact corresponding source. Keep credentials, logs, profiles and validation archives private. Upload the reviewed iOS build separately.

`Scripts/distribution.py source --output PATH.tar.gz` exports tracked source and rejects external symlinks. Review it and add any required corresponding-source material before distribution.

Apple references: [Developer ID](https://developer.apple.com/developer-id/), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/), [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
