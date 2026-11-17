#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/mac-client
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift \
  Apps/macOS/Features/Client/MacClientConnection.swift Tests/MacClient/MacClientChecks.swift \
  -o .build/mac-client/connection-check
.build/mac-client/connection-check
