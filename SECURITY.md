# Security policy

Trunkline is an early development project. It provides remote desktop control, terminal execution and file access to the signed-in Mac user. Treat paired devices and connection credentials as access to that account.

## Report a vulnerability

Use **Security → Report a vulnerability** when available. Keep credentials, private logs and exploit details involving other devices out of public issues. Reports are reviewed as capacity allows. No response time or support window is guaranteed.

## Boundaries and operational limits

- Pair only devices you control. Protect pairing QR codes, passcodes, identity keys and saved credentials.
- The companion validates the paired host identity. A new identity requires deliberate pairing. Network reachability alone does not establish trust.
- The host's session admission policy permits one active controlling device. This is an application rule, not an OS account isolation boundary.
- macOS permissions and the user's login session govern capture and input. The host cannot bypass FileVault's pre-login unlock after a reboot.
- Away access is experimental. Reachability varies across networks, and any public rendezvous service can observe network metadata. Do not describe it as anonymous or universally relay-free.
- Dependencies include native streaming and cryptographic code. No independent security audit has been completed.

Keep credentials and local settings out of Git. `Local/`, `Private/`, `.build/`, signing files and `Config/Local.xcconfig` are ignored. Review every commit for private data.
