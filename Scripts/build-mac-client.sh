#!/bin/sh
set -eu
cd "$SRCROOT"
for arch in $ARCHS; do
    if [ ! -f ".build/desktop-dependencies/install/$arch/lib/libopus.a" ]; then
        python3 Scripts/build-desktop-dependencies.py "$arch" --only opus
    fi
done
