# iPhone and iPad distribution

The companion is intended for TestFlight and the App Store. The Mac host is a separate Developer ID-signed, notarized download. There is no public App Store listing or TestFlight invitation yet; publishing source does not create either one.

## Prepare an archive

Install the dependencies using the development setup, generate the Xcode project, and use a paid Apple Developer team with access to the intended bundle ID. Use an Apple Distribution certificate or Xcode-managed distribution signing for the export. Private signing settings belong in ignored `Config/Local.xcconfig`, never Git.

```sh
python3 Scripts/dev.py ios
python3 Scripts/release.py archive ios --team YOURTEAMID \
  --output dist/Trunkline-iOS.xcarchive
python3 Scripts/release.py ios-export --team YOURTEAMID \
  --archive dist/Trunkline-iOS.xcarchive --output dist/ios-export
```

`YOURTEAMID` is a placeholder for your own ten-character team ID. `ios-export` writes a local App Store Connect export; it does not upload or publish the app. Validate and upload the archive using Xcode Organizer, or upload the exported IPA with Apple's Transporter. Start with external TestFlight after its required review, then submit the production version to App Review.

Version and build numbers come from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`; update them and regenerate the project before each upload. Verify bundle-ID availability in your developer account. A fork must use its own identifiers and signing assets.

For compilation without membership:

```sh
python3 Scripts/release.py archive ios --unsigned \
  --output .build/validation/Trunkline-iOS.xcarchive
```

An unsigned archive is only a validation artifact. It is not an installable IPA and the export command rejects it.

## Submission material

- App name: **Trunkline**. Suggested subtitle: **Your Mac, within reach**.
- Describe it as remote access to the user's Mac: desktop, terminal, files and controls. Do not advertise it as a device-wide VPN or promise universal external-network connectivity.
- Explain that the companion requires the separately installed Mac host, with supported OS versions and an actual host-download URL.
- Prepare real iPhone and iPad screenshots. The simulator's debug-only presentation fixtures are not a fully functional review demo.
- Supply working support and privacy URLs. The [privacy notice](PRIVACY.md) describes the current implementation; confirm it and all bundled SDK behaviour against the release binary before entering App Store Connect's privacy answers. Public peer discovery can expose network metadata, so do not automatically select “No Data Collected” without evaluating Apple's definitions and third-party handling.
- Complete encryption/export-compliance questions for the bundled cryptography. The app currently declares non-exempt encryption; do not change that declaration merely to bypass the questions.
- Review required-reason API declarations for the app and dependencies, permission explanations, IPv6-only behaviour, and the broad ATS exception. Initial desktop discovery currently uses HTTP; document the real scope and justification or narrow the exception after compatibility testing.
- Review GPL/App Store permissions for the exact complete dependency graph and Trunkline's own contributions. Upstream iOS/common-c licences include App Store exceptions, but this is not a blanket exception for unrelated dependencies. Preserve notices and corresponding source.

## App Review notes draft

Trunkline is a general remote-access companion for a user-controlled Mac. Desktop content is rendered on that Mac and streamed to the companion. Terminal commands execute on the paired Mac, not on the iPhone/iPad. The companion does not download executable extensions to add local functionality.

The companion connects using a host pairing link/QR code and a connection passcode. Saved credentials can be unlocked with platform authentication. Only one controlling companion session is admitted per host. Permissions are requested on the device where the protected capability is used.

Reviewer flow:

1. Provide a working, isolated demonstration Mac or another review setup agreed with Apple. Supply its connection details privately in App Review Information, not in this repository. Never expose a maintainer's everyday Mac as the review host.
2. Scan/import the supplied pairing link and enter the supplied test passcode.
3. Open Desktop, tap to click, pinch to zoom, open Keyboard, and use the Spaces and windows menu. Physical-monitor switching requires multiple attached displays; Spaces require multiple virtual desktops on the host.
4. Test Terminal, Files and Controls using non-sensitive demonstration data.
5. Disconnect, then reconnect. Explain the supported Away-access route and its network limitations without treating a local-only test as external-access evidence.

Before submission, replace this draft with the actual working demonstration details, reachable host-download URL and any limitations of the submitted build. A video can supplement, but does not replace, functional reviewer access.

## Apple references

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
- https://developer.apple.com/testflight/
