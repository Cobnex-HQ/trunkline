# Third-party notices

Trunkline credits its dependencies and preserves their original notices. Public binary licensing review remains open. See the findings below and [release requirements](RELEASING.md).

## Sunshine and Moonlight

- [Sunshine](https://github.com/SunshineStream/Sunshine): GPL-3.0, desktop engine.
- [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios): GPL-3.0 with its App Store Distribution Exception, companion streaming client.
- [Moonlight common-c](https://github.com/moonlight-stream/moonlight-common-c): GPL-3.0 with its App Store Distribution Exception, streaming protocol and input.

Bootstrap restores pinned sources into `Vendor/SunshineSource` and `Vendor/MoonlightSource`. `Vendor/MoonlightCore` is checked in with ENet and nanors. X1Kit is restored under MoonlightSource. Revisions are in `Dependencies/streaming-sources.json`. Hash manifests verify prepared files.

The Mac engine is built from `Engines/Desktop` revisions, patches and recipes. Its staged runtime includes provenance and notices. `Dependencies/upstream-desktop.json` records the original release for reference. Those upstream app binaries are not checked in.

Trunkline’s adapted client files retain upstream copyrights and dated modification notices. `project.yml` compiles these copies instead of the pinned originals:

| Adaptation | Change |
| --- | --- |
| Absolute/relative touch, controller and on-screen controls | Non-owning view/delegate references, direct finger targets and timer cleanup |
| `TrunklineStreamView.m` and `TrunklineKeyboardSupport.m` | Weak references, native text composition, layout-aware shortcuts and hardware-key release on cancellation |
| `TrunklineDataManager.m` | Initialise the settings ID so saving direct-touch mode succeeds |
| `Engines/Client/TrunklineInputStream.c` | Coalesce movement only between button events, preserving tap and drag targets |
| `TrunklineVideoDecoderRenderer.m` | Keep video running during UIKit gestures and recover from unsupported codecs |

Both Moonlight licence files retain the exact App Store exception. It does not extend automatically to Sunshine, other dependencies or all Trunkline contributions. Trunkline’s root licence is unchanged. Upstream names remain in legal credits without implying endorsement or trademark permission.

`Engines/MacClient/` adapts the pinned Moonlight iOS HTTP, pairing, identity and utility code for macOS. Original notices remain in the adapted files. The Mac viewer links the same Moonlight C core and input-ordering adaptation, uses native AVFoundation playback, and statically links the pinned desktop Opus 1.6.1 build. Its OpenSSL framework comes from the existing pinned XCFramework. Client identity files stay in a private Application Support directory. TLS identity imports are memory-only, with no repeated Keychain imports.

## SwiftTerm

[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), MIT. Tag `v1.11.2`, commit `b1262db5b6bea699a8260a8c66999436c508ca56`. Original notices, including xterm.js/SourceLair/Christopher Jeffrey credits, remain in `Vendor/SwiftTerm/LICENSE` and `Apps/iOS/Resources/SwiftTerm-LICENSE.txt`.

The local `iOSAccessoryView.swift` adaptation changes its toggle icon and accessibility labels without changing input behaviour. Trunkline presents its own accessory through `TerminalSurface.swift`, using SwiftTerm’s public input/modifier API and escape sequences. The upstream accessory remains in the framework. Trunkline also preserves native selection in `AppleTerminalView.swift` unless the running program has requested mouse input. The modified file has an adaptation header and a pinned checksum.

`Engines/Terminal/TrunklineKittyGraphics.swift` replaces the pinned graphics parser at build time. On iOS it rejects file, temporary-file and shared-memory transports. A remote terminal may send inline graphics, but cannot use this protocol to read or delete companion files. Original notices remain intact.

`TrunklineIOSTerminalView.swift` preserves the reader’s native scroll position when new output arrives. It follows output only when already at the bottom. The terminal input adaptation also fixes function keys, modifier arrows and cancelled hardware-key repeats. Both adapted files replace their pinned originals in `project.yml`.

The framework builds selected native sources, including the Mac-directory AccessibilityService stub needed on iOS. Debug settings disable example previews without vendor edits. Upstream API deprecation warnings still need an upgrade and regression check before production.

## MacOwl

[MacOwl](https://github.com/Cobnex-HQ/macowl), MIT. Copyright (c) 2026 rgcsekaraa. Full notice: `Apps/macOS/Resources/macowl-LICENSE.txt`.

`KeepAwakeManager.swift` adapts its IOKit/pmset approach and adds setting restoration, tested transitions, crash recovery and SwiftUI controls.

## Other dependencies

| Component | Terms and evidence |
| --- | --- |
| ENet | MIT, Lee Salzman. `Vendor/MoonlightCore/enet/LICENSE` |
| nanors | MIT, Joseph Calderon. `Vendor/MoonlightCore/nanors/LICENSE` |
| X1Kit | MIT, Adrian Carpenter. `Vendor/MoonlightSource/X1Kit/LICENSE.md` |
| SDL 2 | zlib-style terms, Sam Lantinga. Original `libs/SDL2/include/SDL_copying.h` in MoonlightSource. Header reports 2.28.5 |
| FFmpeg | Terms depend on build options and dependencies. Companion header: `N-112686-g3f890fbfd9`. Desktop artifact: `Engines/Desktop/dependencies.json`. Exact sources, flags and full notices still need verification |
| Opus | BSD-style terms and additional notices. Desktop 1.6.1 COPYING is staged from verified source. Companion source/terms remain unverified. Its script names 1.3.1, which does not prove the binary version |
| OpenSSL | Apache-2.0 for 3.x. Companion package 3.6.5000 contains OpenSSL 3.6.5. Release digest, source revision and publisher signature are pinned in `Dependencies/openssl.json`. Header, wrapper licence and Apache text are bundled. Desktop 3.5.9 licence is staged |
| miniupnpc | BSD-3-Clause. Desktop 2.3.3 licence is staged from verified source |
| Boost | Boost Software License 1.0 and component-specific notices, collected from prepared sources |
| nlohmann/json | MIT and third-party notices, collected from prepared sources |
| Rust crates | Versions in `Packages/Transport/Cargo.lock`. Licence expressions, repositories and notice paths in bundled `ThirdParty/Rust-dependencies.json` |

Direct Rust dependencies include libp2p, libp2p-stream, Tokio, tokio-util, futures, serde, serde_json, clap, anyhow and either. The inventory includes transitive, build and other-platform packages, not just code linked into each app. Preserve each package’s terms and exceptions. Metadata alone does not replace its original grant and copyright notice.

Apple SDK frameworks/libraries retain Apple’s terms. The engine’s generated web assets and JavaScript dependencies also need a final shipping inventory.

## Audit findings — 2026-11-17

**Fixed:** the collector now includes prefixed or embedded notice names such as `macowl-LICENSE.txt` and `SDL_copying.h`. MacOwl was already a standalone Mac resource. Both apps now collect resource notices, the full Apache-2.0 text and the existing OpenSSL header notice. Required originals are checked by hash.

**Still required before public binaries:**

- Review **42 of 367 external Cargo packages** with no standalone notice matching the collector’s rules. All declare licence metadata and some contain inline grants. Reconcile `ThirdParty/NOTICE-REVIEW.json` with exact upstream terms and target usage.
- Review the replacement OpenSSL build and its privacy declarations. The old invalid source revision was replaced with verified wrapper revision `0a6149bff4fb00921ce0ec1811f726b166638095`. Bootstrap verifies the publisher’s Apple signature and preserves it. The framework’s empty required-reason declaration still needs resolution before App Store export.
- Supply exact corresponding sources and build instructions for codecs and modified GPL components.
- Complete native, Rust and web notices for each shipped target, then review App Store compatibility for the full companion and Trunkline contributions.

## Bundled acknowledgments

`Scripts/bundle-notices.py` copies original notices, this guide and the Rust inventory into each app. `Dependencies/required-notices.json` pins mandatory originals. Builds fail if these are missing or changed without a reviewed manifest update. `Tests/Tooling/test_notices.py` covers collection regressions.

Collected notices and source hashes do not certify licence compliance or replace required corresponding source. Keep original upstream attribution in releases under Trunkline branding.

References: [Moonlight licence and exception](https://github.com/moonlight-stream/moonlight-ios/blob/02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a/LICENSE.txt), [FFmpeg requirements](https://ffmpeg.org/legal.html), [OpenSSL licensing](https://openssl-library.org/source/license/index.html), [Apache-2.0 terms](https://www.apache.org/licenses/LICENSE-2.0).
