#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang"
ios_build_dir="${TRUNKLINE_IOS_DERIVED_DATA:-.build/ios-device}"
python3 Scripts/verify-streaming-vendor.py
Scripts/verify-input-ordering.sh
sh Scripts/verify-terminal-power.sh
python3 -m unittest discover -s Tests/Tooling
clang -Wall -Wextra -Werror Services/DesktopSupervisor/main.c -o .build/TrunklineDesktopSupervisor
python3 Scripts/test-desktop-supervisor.py .build/TrunklineDesktopSupervisor
swift test --package-path Packages/Core --scratch-path .build/core --disable-sandbox
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/macOS/Features/Files/HostFiles.swift Apps/iOS/Features/Files/ClientFiles.swift Tests/Native/HostFilesCheck.swift -o .build/host-files-check
.build/host-files-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/macOS/Features/Files/HostFiles.swift Tests/Native/ResumableHostCheck.swift -o .build/resumable-host-check
.build/resumable-host-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/iOS/Features/Files/ClientFiles.swift Tests/Native/ClientFilesCheck.swift -o .build/client-files-check
.build/client-files-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/iOS/Features/Files/ClientFiles.swift Tests/Native/FileCompatibilityCheck.swift -o .build/file-compatibility-check
.build/file-compatibility-check
swiftc -parse-as-library Apps/macOS/Features/Desktop/DesktopPairingCoordinator.swift Tests/Native/DesktopPairingCheck.swift -o .build/desktop-pairing-check
.build/desktop-pairing-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/iOS/Features/Controls/ClientControls.swift Tests/Native/ClientControlsCheck.swift -o .build/client-controls-check
.build/client-controls-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/iOS/Features/Controls/ClientControls.swift Tests/Native/DesktopDisplayClientCheck.swift -o .build/desktop-display-client-check
.build/desktop-display-client-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/macOS/Features/Power/HostPower.swift Apps/macOS/Features/Controls/MacControls.swift Tests/Native/DesktopDisplayHostCheck.swift -o .build/desktop-display-host-check
.build/desktop-display-host-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/macOS/Features/Desktop/DesktopHost.swift Tests/Native/DesktopHostRefreshCheck.swift -o .build/desktop-host-refresh-check
.build/desktop-host-refresh-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/iOS/Features/Controls/ClientControls.swift Tests/Native/WindowControlsCheck.swift -o .build/window-controls-check
.build/window-controls-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/iOS/Features/Controls/ClientControls.swift Tests/Native/WindowPaginationCheck.swift -o .build/window-pagination-check
.build/window-pagination-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/macOS/Features/Power/HostPower.swift Apps/macOS/Features/Controls/MacControls.swift Tests/Native/HostControlsCheck.swift -o .build/host-controls-check
.build/host-controls-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/macOS/Features/Power/HostPower.swift Apps/macOS/Features/Controls/MacControls.swift Tests/Native/HostPowerCheck.swift -o .build/host-power-check
.build/host-power-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/macOS/Features/Power/PowerControlsAuthorizationView.swift Tests/Native/PowerAuthorizationViewCheck.swift -o .build/power-authorization-view-check
.build/power-authorization-view-check
swiftc -parse-as-library Apps/macOS/App/HostAppDelegate.swift Tests/Native/HostLaunchLifecycleCheck.swift -o .build/host-launch-lifecycle-check
.build/host-launch-lifecycle-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/HostPermissionPolicy.swift Apps/macOS/Features/Connection/HostPermissionRequester.swift Tests/Native/HostPermissionRequestCheck.swift -o .build/host-permission-request-check
.build/host-permission-request-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/macOS/Features/Power/KeepAwakeManager.swift Tests/Native/LoginItemCheck.swift -o .build/login-item-check
.build/login-item-check
clang -Wall -Wextra -I Apps/macOS/Features/Terminal Apps/macOS/Features/Terminal/TerminalPTY.c Tests/Native/pty-smoke.c -o .build/pty-smoke
.build/pty-smoke
xcodebuild -project Trunkline.xcodeproj -scheme TrunklineHost -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Trunkline.xcodeproj -scheme Trunkline -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$ios_build_dir" CODE_SIGNING_ALLOWED=NO build
