#!/bin/zsh
set -euo pipefail
: "${TRUNKLINE_TEAM_ID:?Set your Apple Developer Team ID}"
: "${TRUNKLINE_SIGNING_IDENTITY:?Set your Developer ID Application signing identity}"
: "${TRUNKLINE_NOTARY_PROFILE:?Set a previously configured notarytool Keychain profile}"
cd "${0:A:h:h}"
mkdir -p .build/release
xcodebuild -project Trunkline.xcodeproj -scheme TrunklineHost -configuration Release -destination 'generic/platform=macOS' -archivePath .build/release/TrunklineHost.xcarchive DEVELOPMENT_TEAM="$TRUNKLINE_TEAM_ID" CODE_SIGN_IDENTITY="$TRUNKLINE_SIGNING_IDENTITY" archive
app="$PWD/.build/release/TrunklineHost.xcarchive/Products/Applications/Trunkline.app"
codesign --verify --deep --strict "$app"
ditto -c -k --keepParent "$app" .build/release/TrunklineHost.zip
xcrun notarytool submit .build/release/TrunklineHost.zip --keychain-profile "$TRUNKLINE_NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
ditto -c -k --keepParent "$app" .build/release/TrunklineHost-notarized.zip
