#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
core=Vendor/MoonlightCore
clang -std=gnu11 -DNDEBUG -DHAS_SOCKLEN_T -I "$core/src" -I "$core/enet/include" \
    Tests/Native/InputOrderingCheck.c "$core/src/LinkedBlockingQueue.c" "$core/src/Platform.c" \
    -Wl,-dead_strip -o .build/input-ordering-check
.build/input-ordering-check
