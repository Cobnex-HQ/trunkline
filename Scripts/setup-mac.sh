#!/bin/sh
# One-command local development setup. Install full Xcode and Homebrew first.
set -eu
cd "$(dirname "$0")/.."
case "${1:-install}" in build|install) command_name="${1:-install}" ;; *) printf '%s\n' 'Usage: Scripts/setup-mac.sh [build|install]' >&2; exit 2 ;; esac
if ! command -v brew >/dev/null 2>&1; then
    printf '%s\n' 'Install Homebrew from https://brew.sh, then rerun this script.' >&2
    exit 1
fi
xcodebuild -version
brew bundle --no-upgrade --file=Brewfile
export PATH="$(brew --prefix python@3.13)/libexec/bin:$(brew --prefix rustup)/bin:$(brew --prefix)/bin:$PATH"
rustup toolchain install stable --profile minimal
# Select the toolchain only for this build; do not change the user's global default.
export RUSTUP_TOOLCHAIN=stable
exec python3 Scripts/dev.py "$command_name"
