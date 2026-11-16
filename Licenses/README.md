# Supplemental licence texts

`Apache-2.0/LICENSE.txt` is the unmodified Apache License 2.0 text retrieved from
https://www.apache.org/licenses/LICENSE-2.0.txt on 2026-11-17. Its SHA-256 is pinned
in `Dependencies/required-notices.json` and it is included in both apps.

OpenSSL 3.x uses Apache-2.0. The iOS XCFramework's `opensslv.h` retains its original
OpenSSL Project Authors copyright and licence reference; the bundler preserves
that file alongside this full text. The downloaded framework contains no separate
licence file. This supplements the missing text; it does not establish completeness
of the wrapper's notices, matching sources, or its build dependencies. See
`docs/THIRD_PARTY.md` for the audit findings and release requirements.

Other original notices remain in their dependency trees and application resources.
Do not replace component-specific copyright notices with a generic licence text.
