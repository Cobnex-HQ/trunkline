# iPhone and iPad distribution

The companion is planned for TestFlight and the App Store. The Mac host will be a separate signed, notarized download. Neither listing is public yet.

## Prepare an archive

Run development setup and generate the project. Use a paid Apple Developer team with access to the bundle ID. Export requires Apple Distribution or Xcode-managed signing. Keep local settings in ignored `Config/Local.xcconfig`.

```sh
python3 Scripts/dev.py ios
python3 Scripts/release.py archive ios --team YOURTEAMID \
  --output dist/Trunkline-iOS.xcarchive
python3 Scripts/release.py ios-export --team YOURTEAMID \
  --archive dist/Trunkline-iOS.xcarchive --output dist/ios-export
```

Replace `YOURTEAMID` with your ten-character team ID. `ios-export` creates a local export without uploading. Validate and upload through Xcode Organizer, or upload the IPA with Transporter. Complete external TestFlight review before beta testing, then submit to App Review.

Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, then regenerate before each upload. Check bundle-ID availability. Forks need their own identifiers and signing assets.

For compilation without membership:

```sh
python3 Scripts/release.py archive ios --unsigned \
  --output .build/validation/Trunkline-iOS.xcarchive
```

Unsigned archives only check compilation. They cannot be installed or exported for distribution.

## Submission material

- **Name:** Trunkline. **Suggested subtitle:** Your Mac, within reach.
- Describe desktop, terminal, files and Mac controls. Do not claim a device-wide VPN or universal away access.
- State the Mac host requirement, supported OS versions and working download URL.
- Supply real iPhone/iPad screenshots and a functional review demo. Debug presentation fixtures are not a demo.
- Verify support/privacy URLs and the [privacy notice](PRIVACY.md) against the release and its SDKs. Assess network metadata and third-party handling before choosing App Store privacy answers.
- Complete encryption/export declarations. The app currently declares non-exempt encryption. Do not change this to bypass review questions.
- Review required-reason APIs, permission descriptions, IPv6-only behaviour and ATS exceptions. Initial desktop discovery uses HTTP. Justify its scope or narrow it after testing.
- Check licences for the full dependency graph and Trunkline’s contributions. Moonlight’s App Store exceptions do not cover unrelated components. Retain notices and corresponding source.

## App Review notes draft

Trunkline provides remote access to a user-controlled Mac. The Mac renders the desktop and executes terminal commands. The companion streams the display and sends input. It does not download executable extensions for local features.

Pair using the Mac’s QR code/link and passcode. Saved credentials use platform authentication. Each host allows one controlling companion. Permissions are requested on the device using the protected feature.

Reviewer flow:

1. Provide an isolated demo Mac or a setup agreed with Apple. Put connection details in private App Review Information. Do not expose a maintainer’s everyday Mac.
2. Scan/import the test pairing link and enter its passcode.
3. Test Desktop, touch clicks, zoom, Keyboard and Spaces and windows. Monitor switching needs multiple displays. Spaces need multiple virtual desktops.
4. Test Terminal, Files and Controls with non-sensitive data.
5. Disconnect and reconnect. Explain the tested Away-access route and its limits. Local tests do not prove external access.

Replace this draft with working demo details, the host-download URL and build limitations. A video can supplement functional reviewer access, not replace it.

## Apple references

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
- https://developer.apple.com/testflight/
