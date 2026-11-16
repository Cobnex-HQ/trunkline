# Changelog

## Unreleased

- Correct direct-touch settings persistence and preserve pointer targets across rapid taps, clicks and drags.
- Keep Mac button events at the requested remote target while system cursor updates are still pending.
- Show the actual mouse/keyboard permission state and the current macOS settings name.
- Keep the connection passcode above the software keyboard, with focus-preserving show/hide and refocus behaviour.
- Add Mission Control, App windows and Mac Spaces commands with three-finger swipes and toolbar alternatives.
- Keep monitor selection available in the desktop toolbar without duplicate status polling.
- Add input-ordering, password entry and workspace gesture regression coverage.

## 0.1.0 — Initial source release

- Native Mac host and iPhone/iPad companion with desktop, terminal, controls and files.
- Shared Swift core package and Rust connection transport.
- Pinned desktop engine recipes, local patches and dependency integrity verification.
- Mac development setup, build and local installation commands.
- Source-focused repository layout, contributor documentation and automated checks.

This version is a development preview. Public binary distribution and broad hardware/network validation remain separate release gates.
