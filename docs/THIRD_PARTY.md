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
The adapted `TrunklineAbsoluteTouchHandler.m`, `TrunklineRelativeTouchHandler.m`, `TrunklineOnScreenControls.m` and `TrunklineControllerSupport.m` use non-owning references back to their view, delegate and automatic overlay. Direct-touch history stores position/time instead of retaining UIKit touch objects. The touch handlers expose local timer cancellation for stream-view destruction. `TrunklineStreamView.m` uses a weak interaction delegate and timer callback. These are local lifetime fixes; the corresponding pinned upstream files remain unchanged, and `project.yml` selects the adapted copies for compilation.

`TrunklineVideoDecoderRenderer.m` retains the upstream implementation and copyright notice, with its display link registered in common run-loop modes so it continues during UIKit gesture tracking. The pinned upstream file remains unchanged; `project.yml` compiles the adapted copy.

OpenSSL `3.6.3000` is retained under `Vendor/OpenSSL` with verified release checksum and preparation details in its provenance JSON. The client also links the pinned upstream FFmpeg, SDL and Opus artifacts. Their matching source/build/license requirements, along with the desktop codec archive and other native libraries, need a complete corresponding-source and notices review before release. The GPL text is bundled with both applications; X1Kit and SwiftTerm retain their notices in source. Source and runtime provenance alone are not a substitute for publishing the required corresponding source.

Sunshine: https://github.com/SunshineStream/Sunshine — GPL-3.0.
Moonlight iOS: https://github.com/moonlight-stream/moonlight-ios — GPL-3.0.
Moonlight core: https://github.com/moonlight-stream/moonlight-common-c — GPL-3.0.

When these are distributed or linked, retain matching source/build instructions and all dependency notices, and review the relevant license and storefront terms. Open-source licensing does not grant brand/endorsement rights.

## Bundled acknowledgments

`Scripts/bundle-notices.py` includes discovered vendor license/notice files, the locked Rust dependency license inventory, and these acknowledgments inside each app. This collection does not claim the transitive prebuilt dependency corresponding-source review is complete. Keep the upstream names in these notices even though the normal UI, helper display name, and installer use Trunkline branding.
