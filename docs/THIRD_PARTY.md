# Third-party notices

## MacOwl

Source: https://github.com/Cobnex-HQ/macowl.
Copyright (c) 2026 rgcsekaraa. MIT.
The IOKit/pmset keep-awake approach is adapted in `Apps/macOS/Features/Power/KeepAwakeManager.swift`. Original-setting restoration, testable transition planning, crash recovery and native SwiftUI UI were added. Full notice is distributed at `Apps/macOS/Resources/macowl-LICENSE.txt`.

## SwiftTerm

Source: https://github.com/migueldeicaza/SwiftTerm
Pinned tag: v1.11.2; commit: `b1262db5b6bea699a8260a8c66999436c508ca56`.
MIT, including upstream xterm.js/SourceLair/Christopher Jeffrey notices. Full notice is retained in `Vendor/SwiftTerm/LICENSE` and bundled in `Apps/iOS/Resources/SwiftTerm-LICENSE.txt`.

Local adaptation: `iOSAccessoryView.swift` gives the alternate-keyboard toggle an accurate keyboard icon and accessibility label ("Show extra keys" / "Show standard keyboard"). Its input behavior is unchanged.
Trunkline's terminal now supplies its own native input accessory in `Apps/iOS/Features/Terminal/TerminalSurface.swift`, using SwiftTerm's public input/modifier API and escape sequences. The bundled upstream accessory and alternate keyboard remain in the framework but are not presented by Trunkline's session view.
Selected native terminal sources are compiled as a local framework. The small AccessibilityService stub in the upstream Mac directory is also required by the iOS implementation. Example SwiftUI preview compilation is disabled through the framework Debug configuration, without modifying the vendor source. The old upstream source contains Apple API deprecation warnings; upgrade and regression-test before production.

## Sunshine and Moonlight

The desktop and streaming implementation is based on these GPL-3.0 projects. Bootstrap reconstructs the pinned source archives in ignored `Vendor/SunshineSource` and `Vendor/MoonlightSource`; the smaller `Vendor/MoonlightCore` is checked in with ENet/nanors and their notices. X1Kit is reconstructed under MoonlightSource. Adapted client copies under `Apps/iOS/Features/Desktop/Engine` retain upstream headers. `Dependencies/streaming-sources.json` records revisions, and SHA-256 manifests verify prepared files.

The development workflow builds the desktop engine from the revision and patches in `Engines/Desktop`. Its local runtime includes build provenance and collected notices. `Dependencies/upstream-desktop.json` retains the original upstream release provenance for reference; the source repository does not include those application binaries.
The adapted `TrunklineAbsoluteTouchHandler.m`, `TrunklineRelativeTouchHandler.m`, `TrunklineOnScreenControls.m` and `TrunklineControllerSupport.m` use non-owning references back to their view, delegate and automatic overlay. Direct touch sends each finger target without retaining UIKit touch objects. The touch handlers expose local timer cancellation for stream-view destruction. `TrunklineStreamView.m` uses a weak interaction delegate and timer callback. These are local lifetime fixes; the corresponding pinned upstream files remain unchanged, and `project.yml` selects the adapted copies for compilation.

`TrunklineDataManager.m` initializes the required settings ID before the first stream-settings save. Trunkline does not execute the legacy controller’s ID setup; without this adaptation Core Data rejects the save and the viewer falls back to relative touch input.

`Engines/Client/TrunklineInputStream.c` adapts the pinned common-c input sender: absolute movement coalesces only between button events, preserving each tap and drag target. `project.yml` excludes the upstream InputStream.c when compiling this adaptation; the pinned vendor sources remain unchanged.

`TrunklineVideoDecoderRenderer.m` retains the upstream implementation and copyright notice, with its display link registered in common run-loop modes so it continues during UIKit gesture tracking. The pinned upstream file remains unchanged; `project.yml` compiles the adapted copy.

OpenSSL XCFramework package `3.6.3000` (its headers identify OpenSSL `3.6.3`) is retained under `Vendor/OpenSSL` with verified release checksum and preparation details in its provenance JSON. The client also links the pinned upstream FFmpeg, SDL and Opus artifacts. Their matching source/build/license requirements, along with the desktop codec archive and other native libraries, need a complete corresponding-source and notices review before release. The GPL text is bundled with both applications; X1Kit and SwiftTerm retain their notices in source. Source and runtime provenance alone are not a substitute for publishing the required corresponding source.

Sunshine: https://github.com/SunshineStream/Sunshine — GPL-3.0.
Moonlight iOS: https://github.com/moonlight-stream/moonlight-ios — GPL-3.0.
Moonlight core: https://github.com/moonlight-stream/moonlight-common-c — GPL-3.0.

When these are distributed or linked, retain matching source/build instructions and all dependency notices, and review the relevant license and storefront terms. Open-source licensing does not grant brand/endorsement rights.

## Additional libraries and dependency inventory

| Component | Use and retained terms | Evidence / remaining work |
| --- | --- | --- |
| ENet | Moonlight networking; MIT, Lee Salzman | Original `Vendor/MoonlightCore/enet/LICENSE` |
| nanors | Moonlight recovery coding; MIT, Joseph Calderon | Original `Vendor/MoonlightCore/nanors/LICENSE` |
| X1Kit | Companion controller integration; MIT, Adrian Carpenter | Original `Vendor/MoonlightSource/X1Kit/LICENSE.md` after bootstrap |
| SDL 2 | Companion input/audio integration; zlib-style terms, Sam Lantinga | Original `libs/SDL2/include/SDL_copying.h` in the pinned Moonlight archive; header reports 2.28.5 |
| FFmpeg | Companion and desktop codec libraries | Licence depends on compiled options/dependencies; exact sources, build flags and complete notices remain a release gate. Companion header identifies `N-112686-g3f890fbfd9`; desktop artifact is pinned in `Engines/Desktop/dependencies.json` |
| Opus | Companion and desktop audio codec | BSD-style terms and applicable additional notices; desktop 1.6.1 original COPYING is staged from verified source. Confirm the exact companion binary's source/terms; its upstream build script names 1.3.1, which alone does not prove the binary version |
| OpenSSL | Companion crypto and desktop TLS; Apache-2.0 for 3.x | Companion header and full Apache text are bundled; desktop 3.5.9 original licence is staged. Wrapper/source/build provenance still requires verification |
| miniupnpc | Desktop network discovery; BSD-3-Clause | Desktop 2.3.3 original licence is staged from verified source |
| Boost | Desktop C++ support; Boost Software License 1.0, with component-specific notices | Prepared source notices are collected into the desktop runtime |
| nlohmann/json | Desktop JSON; MIT and retained third-party notices | Prepared source notices are collected into the desktop runtime |
| Rust dependency graph | Away transport, async runtime, cryptography and support crates | Exact versions in `Packages/Transport/Cargo.lock`; generated `ThirdParty/Rust-dependencies.json` includes licence expressions, repositories and collected notice paths |

Direct Rust dependencies include libp2p, libp2p-stream, Tokio, tokio-util, futures, serde, serde_json, clap, anyhow and either. The generated inventory also includes transitive, build and other-platform dependencies; it is not a target-specific list of linked code. Each component keeps its own terms, including multi-licence expressions and exceptions. Do not infer that everything is MIT or that a package metadata string replaces the original grant/copyright notice.

Apple system frameworks and SDK libraries are linked through the Apple SDK; they are not vendored under Trunkline's GPL. The desktop engine's generated web assets and their JavaScript dependencies also need inclusion in the final binary inventory; build-time package names alone do not establish which code ships.

## Attribution audit — 2026-11-17

Sunshine and Moonlight are explicitly credited in the repository and both apps' bundled notice collections. Original upstream names must remain in legal attribution even though the product UI uses Trunkline branding; this does not imply upstream endorsement.

Both pinned Moonlight licence files include an **App Store Distribution Exception**. Preserve its exact original wording. That permission is component-specific: it does not automatically extend to Sunshine, unrelated dependencies or all Trunkline contributions. The root licence has not been changed by this audit.

The audit found that prefix-only filename matching omitted `macowl-LICENSE.txt` and `SDL_copying.h` from the aggregated notice directory. The MacOwl text was already a standalone Mac app resource. Collection now recognises those names, includes both apps' resource notices, checks required originals against a hash manifest, and includes the full Apache-2.0 text plus the existing OpenSSL header notice. Adapted Moonlight source copies retain upstream copyright headers and now carry an explicit dated Trunkline modification notice.

The inspected Cargo lock graph contains **367 external packages**. All declare licence metadata, but **42 have no standalone notice matching the collector's naming rules** in their downloaded crate. Some contain inline grants instead. These are surfaced by `ThirdParty/NOTICE-REVIEW.json`; reconcile the exact upstream grants and target usage before shipping. A collected file is evidence, not a compliance approval.

The recorded OpenSSL wrapper revision could not be retrieved from its GitHub repository during this audit (HTTP 404). The local framework's version header and checksum record exist, but the wrapper provenance and original notices cannot be treated as independently verified. Recover a verifiable exact source/build or replace that artifact before public binary distribution.

**Public binary licensing review remains open.** Required follow-up includes exact corresponding sources/build instructions for codecs and modified GPL components, complete target-specific native/Rust/web dependency notices, verification of OpenSSL wrapper provenance, and App Store compatibility for the entire companion dependency graph. Keep the release gates in [RELEASING.md](RELEASING.md). No claim of “all legal issues resolved” is made.

Authoritative references: [Moonlight licence and App Store exception](https://github.com/moonlight-stream/moonlight-ios/blob/02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a/LICENSE.txt), [FFmpeg licensing and source requirements](https://ffmpeg.org/legal.html), [OpenSSL licensing](https://openssl-library.org/source/license/index.html), and [Apache-2.0 redistribution terms](https://www.apache.org/licenses/LICENSE-2.0).

## Bundled acknowledgments

`Scripts/bundle-notices.py` includes discovered vendor license/notice files, the locked Rust dependency license inventory, and these acknowledgments inside each app. This collection does not claim the transitive prebuilt dependency corresponding-source review is complete. Keep the upstream names in these notices even though the normal UI, helper display name, and installer use Trunkline branding.

The mandatory originals are listed in `Dependencies/required-notices.json`; builds fail if one is missing or its bytes change without an explicit manifest update. The collector and its gap reporting are covered by `Tests/Tooling/test_notices.py`. This catches known attribution regressions; it is not an exhaustive licence-compliance scanner.
