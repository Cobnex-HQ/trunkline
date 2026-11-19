#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe_app=".build/privacy-capture/Trunkline Privacy Check.app"
mkdir -p "$probe_app/Contents/MacOS"
cat > "$probe_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.trunkline.privacy-capture-check</string>
<key>CFBundleExecutable</key><string>PrivacyCaptureProbe</string>
<key>CFBundleName</key><string>Trunkline Privacy Check</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSScreenCaptureUsageDescription</key><string>Check whether a small test curtain can be excluded from capture. Images stay in memory and are not saved or sent.</string>
</dict></plist>
PLIST
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" Tests/Native/PrivacyCaptureProbe.swift -o "$probe_app/Contents/MacOS/PrivacyCaptureProbe"
codesign --force --sign - "$probe_app"
open "$probe_app"
printf '%s\n' 'Result: .build/privacy-capture/result.json. macOS may require Screen Recording approval for this separate test app.'
