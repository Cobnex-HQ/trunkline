# Local development

Follow README.md to install prerequisites. `./Scripts/setup-mac.sh` installs the build tools and then builds/installs the host; pass `build` to produce the app without installing it. The setup assumes Apple's full Xcode toolchain is active. `xcodebuild -version` and `xcrun --sdk macosx --show-sdk-path` help diagnose a Command Line Tools-only selection.

| Command | Result |
| --- | --- |
| `python3 Scripts/dev.py doctor` | Check tools and active Xcode |
| `python3 Scripts/dev.py setup` | Fetch/verify dependencies, prepare Rust and generate Xcode project |
| `python3 Scripts/dev.py build` | Build the native host and bundled engine for this Mac |
| `python3 Scripts/dev.py install` | Build and install into `~/Applications/Trunkline.app` |
| `python3 Scripts/dev.py ios` | Prepare and open the companion project in Xcode |
| `python3 Scripts/dev.py test` | Run tooling, shared Swift and Rust tests |

Equivalent `make` targets are available. Setup writes ignored `Config/Toolchain.xcconfig` so Xcode can locate the same Rust tools without relying on your shell profile. Install accepts `--destination /path/Trunkline.app`; it refuses to replace that destination while its app is running. Build output is `.build/dev-mac`. Logs for the engine are `.build/desktop-dev-ARCH.log`. Successful engine stages are retained under `.build/desktop-runtime-*` for inspection; remove old stages only when no Xcode project is using them.

## Choose a development loop

Run commands from the repository root. Install the README prerequisites first; `setup` checks tools but does not install Homebrew packages. You do not need to compile the desktop engine for shared-code or companion-only changes.

### Shared logic or build tooling

Edit `Packages/Core`, `Packages/Transport`, or `Scripts`, then run the relevant suite in [TESTING.md](TESTING.md). `python3 Scripts/dev.py test` runs all three contributor suites without building either app. Rust tests need the Rust toolchain on PATH and may download locked dependencies on their first run.

### iPhone and iPad interface

Run `python3 Scripts/dev.py ios` once to prepare dependencies and open Xcode. Select the **Trunkline** scheme and an installed iOS simulator, then Run. A simulator build does not require a personal signing team. The simulator is useful for UI and local regression tests; real streaming, device input and away access still need the hardware checks in [TESTING.md](TESTING.md).

For subsequent Swift/UI edits, build in Xcode. Regenerate with `xcodegen generate` after changing `project.yml`; editing the generated `.xcodeproj` directly will lose those changes. Run setup again when dependency or toolchain configuration changes.

### Mac host

Run `./Scripts/setup-mac.sh build` for the first complete host build without installation. The verified app is at `.build/dev-mac/Build/Products/Debug/Trunkline.app`. Use the **TrunklineHost** scheme for subsequent native app edits, retaining the generated runtime configuration. Engine patch or dependency changes need `python3 Scripts/dev.py build` to rebuild and stage the engine again.

For interactive permission and saved-credential testing, choose one installation path and signing identity consistently. Quit the installed host before replacing it; avoid simultaneously running the installed app and Xcode's build copy. Do not use a working unattended-access installation as a disposable test environment.

## Local configuration and build outputs

| File or directory | Owner and purpose |
| --- | --- |
| `project.yml` | Tracked Xcode targets, schemes and build settings; edit this instead of the generated project |
| `Config/Build.xcconfig` | Includes generated toolchain/runtime settings, then local overrides |
| `Config/Local.xcconfig` | Your ignored signing overrides, copied from the example |
| `Config/Toolchain.xcconfig` | Written by setup with Rust executable paths and active toolchain |
| `Config/Generated.xcconfig` | Written by the Mac build with runtime stage and architecture |
| `.build/dev-mac` | Host Xcode build products |
| `.build/desktop-runtime-*` | Staged desktop runtimes referenced by generated configuration |

Do not copy a maintainer's generated configuration: paths and signing identities are machine-specific. If a referenced runtime stage was removed, rerun the Mac build. Avoid deleting all of `.build` as an initial troubleshooting step; it also removes expensive dependency builds and useful logs.

## Signing and permissions

The scripted Mac development build uses an ad-hoc signature. For a stable developer identity or physical iOS devices, configure your own team in the ignored local xcconfig and build from Xcode. Never commit provisioning profiles, certificates or account identifiers. Do not remove the existing app's Keychain items to troubleshoot a build. Verify new permissions and saved access locally before leaving the Mac unattended.

## Dependency updates

Sources and binary SDK archives are pinned in `Dependencies/`; engine sources and dependency recipes are pinned in `Engines/Desktop`. Bootstrap checks hashes even on cache hits and refuses changed source files. Inspect a checksum error rather than disabling validation. Updating a dependency requires reviewing upstream changes, retaining notices, updating hashes and rerunning the relevant integration tests.

Small source vendors are checked in. Large upstream source trees and the OpenSSL XCFramework are reconstructed by bootstrap. Desktop libraries are built from pinned recipes, with the codec archive tracked in the engine dependency manifest. No cached build output is required to clone the source repository.

## Troubleshooting

- **Tool shim errors:** configure the version in your own tool manager or use Homebrew's executable on PATH. The script does not change global tool-manager settings.
- **Downloads fail:** retry after restoring connectivity. Partial downloads are not installed; checksum failures leave the cache for inspection.
- **Engine compilation fails:** inspect the engine log. The first build is considerably slower than an incremental one.
- **No iOS device:** connect, trust and unlock it in Xcode, then use your own signing team.
- **Screen capture/input denied:** complete macOS privacy setup. A new signature can require approval again.
- **Away connection fails:** verify local access first. NAT, firewalls and rendezvous availability can prevent external connections.
