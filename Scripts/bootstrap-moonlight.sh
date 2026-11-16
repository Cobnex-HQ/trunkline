#!/bin/sh
# Compatibility entry point; dependencies are verified by the shared bootstrap.
set -eu
cd "$(dirname "$0")/.."
exec python3 Scripts/bootstrap.py "$@"
