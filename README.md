<div align="center">
  <img src="Assets/Branding/glacier-fold-master.png" width="128" alt="Trunkline folded elephant icon">
  <h1>Trunkline</h1>
  <p>A native Mac workspace on your iPhone and iPad.</p>
</div>

Use your Mac’s desktop, terminal, files and controls from a native iPhone or iPad app. The Mac host includes the streaming engine and connection helpers.

**Status: early development.** Build from source for local use and contribution. Public installers are not available yet. Hardware, multi-monitor and network testing remain incomplete. Keep another way to reach an unattended Mac.

## Features

- Native iPhone, iPad and Mac interfaces with light, dark and system appearance.
- Desktop streaming, direct touch, trackpad input, zoom and monitor selection.
- Named terminal sessions, file transfers, app/window controls and keep-awake settings.
- QR pairing, saved Macs and one active controlling device per host.
- Local Wi-Fi access and experimental away access using a Rust transport. Away access depends on network reachability and rendezvous infrastructure. It is not a server-free VPN or a promise to cross every NAT.

## Distribution plan

Planned distribution: TestFlight and App Store for iPhone/iPad, plus a signed, notarized Mac download. See [release preparation](docs/RELEASING.md), [App Store submission](docs/APP_STORE.md), and [privacy](docs/PRIVACY.md).

## Build and install on your Mac

Requirements: **macOS 15+**, full **Xcode 26+**, Python 3.10+, and [Homebrew](https://brew.sh). Open Xcode once to install its components. Build recipes cover Apple silicon and Intel, but only Apple silicon has been validated. The first engine build downloads dependencies and takes longer.

```sh
git clone https://github.com/Cobnex-HQ/trunkline.git
cd trunkline
./Scripts/setup-mac.sh
```

The script installs the Brewfile tools and builds Trunkline without changing your global Rust toolchain. If tools are already configured, use `python3 Scripts/dev.py install`. Run `python3 Scripts/dev.py doctor` to check them. Full Xcode must be active, not just Command Line Tools.

Installation checks pinned downloads, builds and verifies the host and engine, then installs an ad-hoc-signed app at `~/Applications/Trunkline.app`. Quit that app before updating. The previous version is kept as `Trunkline.previous.app`. Local Mac builds need no administrator password or developer membership.

Open Trunkline and grant Screen Recording and Device Control and Data Access permissions, called Accessibility on earlier macOS versions. Signing changes can require approval again. Test saved credentials and remote access locally before leaving the Mac unattended.

## iPhone and iPad

```sh
python3 Scripts/dev.py ios
```

In Xcode, select **Trunkline**, your device and your own signing team. Copy `Config/Local.xcconfig.example` to ignored `Config/Local.xcconfig` for local signing settings. Run the app on your device. Personal signing supports development under Apple’s provisioning limits.

Start access in the Mac app, pair the companion on the same network, and verify Desktop and Terminal before trying away access. See [development](docs/DEVELOPMENT.md) and [security](SECURITY.md).

## Desktop controls

Tap the passcode field to open the keyboard and scroll it into view. The eye button shows or hides the passcode while typing. Leaving the field hides it again.

In the desktop viewer, **Keyboard** opens the remote keyboard. In direct-touch mode, tap to click and move one finger to drag. Pinch to zoom and use two fingers to pan while zoomed in.

- Swipe **up with three fingers** for Mission Control, or **down** for App windows.
- Swipe **left or right with three fingers** to move between the Mac’s Spaces.
- The **Spaces and windows** menu offers the same actions without gestures. They use the Mac’s standard Control–Arrow shortcuts, which must be enabled on the host.
- **Displays** selects a connected physical monitor, one at a time, preserving its proportions. Spaces are virtual desktops within a monitor. Create or rearrange them in Mission Control.

## Repository map

| Directory | Responsibility |
| --- | --- |
| `Apps/iOS` | Companion app, feature views, desktop client integration and design system |
| `Apps/macOS` | Host app and desktop, terminal, controls, files and power features |
| `Packages/Core` | Shared Swift protocol, identity, state and policy. Independently testable |
| `Packages/Transport` | Rust transport library, helper executable and C bridge |
| `Services/DesktopSupervisor` | Small native desktop process supervisor |
| `Engines/Desktop` | Pinned upstream revision, patches and dependency/build recipes |
| `Dependencies` | Download provenance and file-integrity manifests |
| `Vendor` | Small source dependencies with their original licences |
| `Tests` | Companion, native integration and development-tool checks |
| `Scripts` | Setup, build, verification and local packaging tools |
| `Assets/Branding` | Glacier Fold vector sources and icon assets |

`project.yml` defines the Xcode project. Run `python3 Scripts/dev.py setup` to regenerate the ignored `.xcodeproj`. Build outputs, downloads, credentials and local signing settings stay out of Git.

## Contribute

New to the codebase? Start with the [developer documentation index](docs/README.md) and its first-contribution path.

Run `python3 Scripts/dev.py test` for the shared Swift, Rust and tooling suites. See [CONTRIBUTING.md](CONTRIBUTING.md), [architecture](docs/ARCHITECTURE.md), the [test guide](docs/TESTING.md), and [validation status](docs/VALIDATION.md) for app and device checks. Please discuss large architectural changes in an issue first.

## Licence and attribution

Trunkline uses [GNU GPL v3](LICENSE). Sunshine, Moonlight, SwiftTerm, MacOwl and other components retain their original copyrights and licences. See [third-party notices](docs/THIRD_PARTY.md). Trunkline branding does not remove upstream attribution.

CI publishes no app binaries. Public releases must meet the source, licence, signing and platform requirements in [RELEASING.md](docs/RELEASING.md).
