#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
device="${1:?Usage: Scripts/verify-viewport.sh SIMULATOR-UDID}"
exec xcodebuild -project Trunkline.xcodeproj -scheme ViewportUIKitTests \
  -configuration Debug -parallel-testing-enabled NO -destination-timeout 90 -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath "${TRUNKLINE_SIM_DERIVED_DATA:-.build/viewport-ui-tests}" CODE_SIGNING_ALLOWED=NO test
