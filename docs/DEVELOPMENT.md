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
