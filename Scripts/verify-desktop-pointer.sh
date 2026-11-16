#!/bin/zsh
# No streaming connection, screen capture, input event delivery, or OS permission prompts.
set -euo pipefail
cd "${0:A:h:h}"
source_root="${1:-.build/upstream/sunshine}"
input_root="$source_root/third-party/libvirtualhid"
[[ "$(git -C "$source_root" rev-parse HEAD)" == 63d35f702ee9e362e43263742981836ec0710384 ]]
[[ "$(git -C "$input_root" rev-parse HEAD)" == 53e1a949fc0784af716b782ddfa6c647cafd1f05 ]]
mkdir -p .build
clang++ -std=c++23 -I "$input_root/src" -I "$input_root/src/include" \
    Tests/Native/DesktopPointerCheck.cpp "$input_root/src/core/types.cpp" \
    -framework ApplicationServices -framework Carbon -framework CoreFoundation -framework IOKit \
    -o .build/desktop-pointer-check
.build/desktop-pointer-check
clang++ -std=c++23 -I "$source_root/src" Tests/Native/DesktopDisplayGeometryCheck.cpp \
    -framework CoreGraphics -o .build/desktop-geometry-check
.build/desktop-geometry-check

clang++ -std=c++23 -fblocks -I "$source_root/src" Tests/Native/CaptureLifecycleCheck.mm \
    -framework AVFoundation -framework CoreGraphics -framework CoreMedia -framework CoreVideo -framework Foundation \
    -o .build/capture-lifecycle-check
.build/capture-lifecycle-check
clang++ -std=c++23 -I "$source_root/src" Tests/Native/DisplayChangeCheck.cpp \
    -framework CoreGraphics -o .build/display-change-check
.build/display-change-check

clang++ -std=c++23 -I "$source_root/src" Tests/Native/DesktopSelectionCheck.cpp \
    -o .build/desktop-selection-check
.build/desktop-selection-check
