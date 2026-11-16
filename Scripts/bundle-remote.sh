#!/bin/sh
set -eu
cd "$SRCROOT/Packages/Transport"
cargo_bin="${TRUNKLINE_CARGO:-$(command -v cargo || printf %s "${HOME}/.cargo/bin/cargo")}"
rustup_bin="${TRUNKLINE_RUSTUP:-$(command -v rustup || printf %s "${HOME}/.cargo/bin/rustup")}"
destination="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/TrunklineRemote"
mkdir -p "$(dirname "$destination")"
set --
for architecture in ${ARCHS:-$(uname -m)}; do
    case "$architecture" in
        arm64) target=aarch64-apple-darwin ;;
        x86_64) target=x86_64-apple-darwin ;;
        *) echo "error: Unsupported Mac architecture: $architecture"; exit 1 ;;
    esac
    if ! "$rustup_bin" target list --installed | /usr/bin/grep -qx "$target"; then
        echo "error: Install the Rust target with: rustup target add $target"
        exit 1
    fi
    if [ "$architecture" = "$(uname -m)" ]; then
        "$cargo_bin" build --release --bin trunkline-p2p-probe --locked
        set -- "$@" target/release/trunkline-p2p-probe
    else
        "$cargo_bin" build --release --bin trunkline-p2p-probe --target "$target" --locked
        set -- "$@" "target/$target/release/trunkline-p2p-probe"
    fi
done
/usr/bin/lipo -create "$@" -output "$destination"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
    codesign --force --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$destination"
fi
