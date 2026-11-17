# Trunkline transport

Rust connection and tunnel implementation used by the Mac helper and physical iOS companion. The internal crate/binary name remains `trunkline-p2p-probe`. The bundled Mac helper is named `TrunklineRemote`.

```sh
cargo test --locked
cargo build --release --locked
```

`src/session.rs` implements session transport, `tunnel.rs` handles forwarding, `pairing.rs` handles paired configuration, and `native.rs` exposes the C interface declared in `iOS/P2PProbe.h`. `src/main.rs` provides the helper CLI. Use `--help` to inspect commands. Never publish generated identities or pairing files.

`two_process_test.py --helper ADDRESS` is an optional manual networking experiment. It writes private local results to the ignored `Private/` directory and requires an authorised reachable helper. Passing it does not demonstrate cellular connectivity. Away access remains dependent on network reachability and rendezvous service availability.
