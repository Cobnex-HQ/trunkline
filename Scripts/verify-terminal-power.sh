#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/terminal-power
clang -c Apps/macOS/Features/Terminal/TerminalPTY.c -o .build/terminal-power/pty.o
swiftc -parse-as-library -import-objc-header Apps/macOS/Features/Terminal/TerminalPTY.h \
  Packages/Core/Sources/TrunklineCore/*.swift Apps/macOS/Features/Terminal/TerminalSessions.swift \
  Tests/Native/TerminalExitCheck.swift .build/terminal-power/pty.o -o .build/terminal-power/exit-check
.build/terminal-power/exit-check
swiftc -parse-as-library -import-objc-header Apps/macOS/Features/Terminal/TerminalPTY.h \
  Packages/Core/Sources/TrunklineCore/*.swift Apps/macOS/Features/Terminal/TerminalSessions.swift \
  Tests/Native/TerminalShutdownCheck.swift .build/terminal-power/pty.o -o .build/terminal-power/shutdown-check
.build/terminal-power/shutdown-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift \
  Apps/macOS/Features/Power/KeepAwakeManager.swift Apps/macOS/Features/Power/HostPower.swift \
  Apps/macOS/Features/Controls/MacControls.swift Tests/Native/RemoteAwakeCheck.swift -o .build/terminal-power/awake-check
.build/terminal-power/awake-check
swiftc -parse-as-library Packages/Core/Sources/TrunklineCore/*.swift \
  Apps/iOS/Features/Controls/ClientControls.swift Tests/Native/RemoteAwakeClientCheck.swift -o .build/terminal-power/awake-client-check
.build/terminal-power/awake-client-check
