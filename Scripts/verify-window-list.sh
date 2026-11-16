#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
app=.build/WindowListCheck.app
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.trunkline.window-list-check</string>
<key>CFBundleName</key><string>Trunkline Window Check</string>
<key>CFBundleExecutable</key><string>WindowListCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift Apps/macOS/Features/Power/HostPower.swift Apps/macOS/Features/Controls/MacControls.swift Tests/Native/HostWindowListCheck.swift -o "$app/Contents/MacOS/WindowListCheck"
exec "$app/Contents/MacOS/WindowListCheck"
