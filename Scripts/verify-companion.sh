#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
device="${1:?Usage: Scripts/verify-companion.sh SIMULATOR-UDID}"
exec xcodebuild -quiet -project Trunkline.xcodeproj -scheme CompanionClientTests \
  -configuration Debug -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath .build/experience-sim CODE_SIGNING_ALLOWED=NO test
