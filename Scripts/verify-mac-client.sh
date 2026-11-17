#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/mac-client
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift \
  Apps/macOS/Features/Client/MacClientConnection.swift Tests/MacClient/MacClientChecks.swift \
  -o .build/mac-client/connection-check
.build/mac-client/connection-check

swiftc -parse-as-library Apps/macOS/Features/Sharing/HostSharingAction.swift \
  Tests/Native/HostSharingActionCheck.swift -o .build/mac-client/sharing-check
.build/mac-client/sharing-check
