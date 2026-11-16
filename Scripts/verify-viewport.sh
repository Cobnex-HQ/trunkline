#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
device="${1:?Usage: Scripts/verify-viewport.sh SIMULATOR-UDID}"
exec xcodebuild -quiet -project Trunkline.xcodeproj -scheme ViewportUIKitTests \
  -configuration Debug -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath .build/viewport-ui-tests CODE_SIGNING_ALLOWED=NO test
