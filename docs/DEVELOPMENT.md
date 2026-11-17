# Local development

Install the prerequisites in [README.md](../README.md). `./Scripts/setup-mac.sh` installs tools, builds the host and installs it. Add `build` to skip installation. Check that full Xcode is active with `xcodebuild -version` and `xcrun --sdk macosx --show-sdk-path`.

| Command | Result |
| --- | --- |
| `python3 Scripts/dev.py doctor` | Check tools and active Xcode |
| `python3 Scripts/dev.py setup` | Fetch/verify dependencies, prepare Rust and generate Xcode project |
| `python3 Scripts/dev.py build` | Build the native host and bundled engine for this Mac |
| `python3 Scripts/dev.py install` | Build and install into `~/Applications/Trunkline.app` |
| `python3 Scripts/dev.py ios` | Prepare and open the companion project in Xcode |
| `python3 Scripts/dev.py test` | Run tooling, shared Swift and Rust tests |

Equivalent `make` targets are available. Install accepts `--destination /path/Trunkline.app` and refuses to replace a running app. Engine logs are in `.build/desktop-dev-ARCH.log`. Keep runtime stages while Xcode still references them.

## Choose a development loop

Run commands from the repository root. `setup` checks tools but does not install Homebrew packages. Shared-code and companion-only work do not require an engine build.

### Shared logic or build tooling

Run the relevant suite in [TESTING.md](TESTING.md), or `python3 Scripts/dev.py test` for all three contributor suites. Neither builds the apps. Rust must be on PATH and may download locked dependencies on the first run.

### iPhone and iPad interface

Run `python3 Scripts/dev.py ios`, select **Trunkline** and an installed simulator in Xcode, then Run. Simulator builds need no signing team. Streaming, touch input and away access still need [hardware testing](TESTING.md).

Build later UI edits in Xcode. After editing `project.yml`, run `xcodegen generate`. Direct changes to the generated project will be lost. Rerun setup after dependency or toolchain changes.

### Mac host

Run `./Scripts/setup-mac.sh build` once. The app is at `.build/dev-mac/Build/Products/Debug/Trunkline.app`. Use **TrunklineHost** in Xcode for later app edits. After engine or dependency changes, run `python3 Scripts/dev.py build` again.

Use one installation path and signing identity when testing permissions and saved credentials. Quit the host before replacing it. Avoid running the installed and Xcode copies together, or testing against a Mac you rely on for unattended access.

## Local configuration and build outputs

| File or directory | Owner and purpose |
| --- | --- |
| `project.yml` | Tracked Xcode targets, schemes and build settings. Edit this instead of the generated project |
| `Config/Build.xcconfig` | Includes generated toolchain/runtime settings, then local overrides |
| `Config/Local.xcconfig` | Your ignored signing overrides, copied from the example |
| `Config/Toolchain.xcconfig` | Written by setup with Rust executable paths and active toolchain |
| `Config/Generated.xcconfig` | Written by the Mac build with runtime stage and architecture |
| `.build/dev-mac` | Host Xcode build products |
| `.build/desktop-runtime-*` | Staged desktop runtimes referenced by generated configuration |

Generate your own configuration. Paths and signing identities are machine-specific. Rebuild the host if its runtime stage is missing. Deleting all of `.build` also removes cached dependencies and diagnostic logs.

## Signing and permissions

The Mac script uses ad-hoc signing. For a stable signing identity or physical iOS devices, set your team in `Config/Local.xcconfig` and build in Xcode. Keep signing files and account identifiers out of Git. Do not delete Keychain items to fix a build. Test permissions and saved access locally.

## Dependency updates

Pins live in `Dependencies/` and `Engines/Desktop`. Bootstrap verifies hashes, including cached downloads. Investigate mismatches instead of disabling checks. Dependency updates need upstream review, preserved notices, new hashes and integration tests.

Small dependencies are checked in. Bootstrap restores larger source trees and the OpenSSL XCFramework. Desktop recipes build the native libraries and pin the codec archive. Cloning does not require cached build output.

## Troubleshooting

- **Tool shim errors:** configure the version in your own tool manager or use Homebrew's executable on PATH. The script does not change global tool-manager settings.
- **Downloads fail:** retry after restoring connectivity. Partial downloads are not installed. Checksum failures leave the cache for inspection.
- **Engine compilation fails:** inspect the engine log. The first build is considerably slower than an incremental one.
- **No iOS device:** connect, trust and unlock it in Xcode, then use your own signing team.
- **Screen capture/input denied:** complete macOS privacy setup. A new signature can require approval again.
- **Away connection fails:** verify local access first. NAT, firewalls and rendezvous availability can prevent external connections.
