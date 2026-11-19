<div align="center">
  <img src="Assets/Branding/glacier-fold-master.png" width="128" alt="Trunkline folded elephant icon">
  <h1>Trunkline</h1>
  <p>Your Mac workspace, from iPhone, iPad or another Mac.</p>
</div>

Use your Mac’s desktop, terminal, files and controls from a native iPhone or iPad app. The Mac host includes the streaming engine and connection helpers.

To share this Mac, open **My Mac → Sharing**, turn sharing on and choose **Copy pairing link**. The Mac app also includes a native desktop client. Open **Remote Macs → Saved Macs**, paste the other Mac’s pairing link and enter its connection passcode. Connect locally or choose **Away** after enabling away access on the host. Outgoing away connections require sharing on this Mac to be turned off first.

**Status: early development.** Build from source for local use and contribution. Public installers are not available yet. Hardware, multi-monitor and network testing remain incomplete. Keep another way to reach an unattended Mac.

## Features

- Native iPhone, iPad and Mac interfaces with light, dark and system appearance.
- Mac-to-Mac desktop viewing, mouse and keyboard input, audio, full screen, saved Macs and display selection. Terminal and file workspaces remain in the iPhone/iPad client.
- Desktop streaming, direct touch, trackpad input, zoom and monitor selection.
- Named terminal sessions, file transfers, app/window controls and keep-awake settings.
- QR pairing, saved Macs and one active controlling device per host.
- Local Wi-Fi access and experimental away access using a Rust transport. Away access depends on network reachability and rendezvous infrastructure. It is not a server-free VPN or a promise to cross every NAT.

In **Terminal**, swipe through output or use the up/down history buttons. New output follows only when you are at the bottom. `exit` returns to the session list. Reopen an ended session to read its output, start another session or remove it.

The native iPhone/iPad session list separates **Running sessions** from **Ended sessions**. Swipe a row or hold it for actions. **End session** stops the shell and processes attached to that terminal, then waits for the Mac to confirm. Other sessions keep running. The list covers sessions started in Trunkline, not Terminal.app or iTerm.

In **Controls → Mac → Keep awake**, choose Automatic, Mac, or Mac and display. Active connections already keep the Mac and display awake. An extra hold lasts until changed or the Mac app quits. Closed-lid settings require local setup. Volume, media, brightness, apps, windows, clipboard and power actions are also in Controls. Some actions need Mac permissions.

On iPad, use **New window** on the connection screen or **Mac menu → Open in new window**. Windows keep separate connections and navigation. Saved Macs are shared. The current native engine supports one live desktop and one Away connection per app process. Other windows can use local Terminal, Files and Controls. A Mac still accepts only one controlling connection.

In **Controls → Clipboard**, use **Copy from Mac** or **Paste to Mac**. Paste updates the Mac clipboard without typing into its active app. Optional text syncing is saved for each Mac and runs only in the focused, active window. Two-way sync starts with future changes, preserving existing device clipboard text.

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

Turn on sharing in the Mac app, pair the companion on the same network, and verify Desktop and Terminal before trying away access. See [development](docs/DEVELOPMENT.md) and [security](SECURITY.md).

## Desktop controls

Tap the passcode field to open the keyboard and scroll it into view. The eye button shows or hides the passcode while typing. Leaving the field hides it again.

In the desktop viewer, **Keyboard** opens the remote keyboard. In direct-touch mode, tap to click and move one finger to drag. Pinch to zoom and use two fingers to pan while zoomed in.

- Swipe **up with three fingers** for Mission Control, or **down** for App windows.
- Swipe **left or right with three fingers** to move between the Mac’s Spaces.
- The **Spaces and windows** menu offers the same actions without gestures. They use the Mac’s standard Control–Arrow shortcuts, which must be enabled on the host.
- **Displays** selects a connected physical monitor, one at a time, preserving its proportions. Spaces are virtual desktops within a monitor. Create or rearrange them in Mission Control.

On iPhone and iPad, **Desktop → Adapt to network** adjusts video bitrate below the selected quality limit and restores it gradually when loss clears. It requires the updated Mac engine. The desktop keeps the same resolution and proportions. Encoder changes can cause a brief pause. Older hosts keep their selected fixed quality.

Quality, input mode, motion, statistics, adaptive quality and clipboard consent are remembered per Mac on iPhone and iPad. The Mac client remembers quality and display selection. Display preferences use a persistent monitor identity when available. A missing monitor falls back to the host’s current display. Monitors without a reliable identity may need selecting again after restarting the Mac app.

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

### Connection details

Open **Connection details** from a connection error or the Desktop options menu. It shows the last connection stage and typed failure reason. Connected Macs also report input, screen recording and window-control permissions. Older hosts may report these as not checked. A blocked route cannot prove that a Mac is offline. Share connection report exports these checks without addresses, credentials or pairing links.

### iPad external display

On iPadOS 27 or later, connect a display and open **Desktop → Spaces and windows → Use external display**. The display shows the full Mac desktop at its original aspect ratio. The iPad keeps its preview, touch input, keyboard and controls. Output is off by default, stops when the app becomes inactive and is cleared when the desktop closes. It shares the existing connection but uses an additional video decoder while enabled.

Device-sized virtual desktops are not enabled. See the [macOS feasibility check](docs/DISPLAY-FEASIBILITY.md).

### Resumable files

Updated iPhone/iPad clients and Mac hosts support Retry and Cancel in Files, with byte progress. A dropped connection preserves the current transfer in its workspace window. Reconnect to the same Mac and choose Retry. Uploads use a private local snapshot, and downloads reject source-file changes. Existing destinations are never overwritten.

Resume state lasts up to 30 minutes of inactivity while both app processes remain running. It does not survive quitting an app or restarting a device. Transfers stay limited to 512 MB per file, with at most four unfinished host transfers. Older hosts retain the previous transfer flow.
