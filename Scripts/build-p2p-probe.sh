#!/bin/sh
set -eu
case "${SDK_NAME:-}" in iphoneos*) ;; *) exit 0 ;; esac
probe_cargo="${TRUNKLINE_CARGO:-$(command -v cargo || printf %s "${HOME}/.cargo/bin/cargo")}"
if [ ! -x "$probe_cargo" ]; then
    echo 'error: The Trunkline direct connection transport requires Rust (cargo).'
    exit 1
fi
cd "${SRCROOT}/Packages/Transport"
"$probe_cargo" build --lib --release --target aarch64-apple-ios --locked
