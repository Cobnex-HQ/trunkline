#!/bin/sh
set -eu
# The tool target is signed before copying. Do not modify its executable bytes.
cp "$BUILT_PRODUCTS_DIR/TrunklineTerminalLauncher" \
   "$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/TrunklineTerminalLauncher"
