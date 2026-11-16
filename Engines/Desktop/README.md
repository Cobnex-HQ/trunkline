# Desktop engine integration

The Mac host embeds a patched desktop engine built from the upstream revision in `release.json`. `Patches/` contains the local capture, display, pointer and runtime changes. `dependencies.json` pins the static library inputs and codec archive by checksum.

Run `python3 Scripts/dev.py build` from the repository root. It prepares and validates upstream sources, builds dependencies for the current architecture, configures CMake, builds the engine and web assets, audits the result, and stages an immutable local candidate. All outputs stay under `.build/`.

For architecture-specific work, see `Scripts/prepare-desktop-engine.py`, `build-desktop-dependencies.py`, `configure-desktop-release.py`, `audit-desktop-release.py` and `stage-desktop-release.py`. A universal build requires both architectures and their matching audit logs; local development only requires the current architecture.

Original licence and attribution notices are retained. A staged local candidate is not approval for public binary distribution. See `docs/RELEASING.md`.
