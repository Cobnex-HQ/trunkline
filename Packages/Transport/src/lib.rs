use std::{
    task::{Context, Poll},
    time::Duration,
};
pub mod native;
mod observed;
mod pairing;
mod runner;
mod session;
pub mod tunnel;

pub fn run_cli() -> anyhow::Result<bool> {
    use clap::Parser;
    let args = runner::Args::parse();
    tokio::runtime::Runtime::new()?.block_on(runner::run(args))
}
use either::Either;
use libp2p::{
    Multiaddr, PeerId, StreamProtocol, Swarm, connection_limits,
    core::{Endpoint, multiaddr::Protocol, transport::PortUse},
    dcutr, identify, identity, kad, noise, ping, relay,
    swarm::{
        ConnectionDenied, ConnectionId, FromSwarm, NetworkBehaviour, THandler, THandlerInEvent,
        THandlerOutEvent, ToSwarm, behaviour::toggle::Toggle, dummy,
    },
    tcp, yamux,
};
pub use pairing::{DeviceConfig, pair};

/// A probe stream is allowed only on a direct connection to the paired identity.
pub fn allow_probe(expected: Option<PeerId>, actual: PeerId, address: &Multiaddr) -> bool {
    expected == Some(actual) && !address.iter().any(|part| part == Protocol::P2pCircuit)
}

/// The handler itself is absent on relay/helper connections, so there is no
/// application stream to accidentally fall back to when a direct path drops.
pub struct DirectPing {
    expected: Option<PeerId>,
    inner: ping::Behaviour,
}
impl DirectPing {
    pub fn new(expected: Option<PeerId>) -> Self {
        Self {
            expected,
            inner: ping::Behaviour::new(
                ping::Config::new()
                    .with_interval(Duration::from_millis(500))
                    .with_timeout(Duration::from_secs(5)),
            ),
        }
    }
}
impl NetworkBehaviour for DirectPing {
    type ConnectionHandler =
        Either<<ping::Behaviour as NetworkBehaviour>::ConnectionHandler, dummy::ConnectionHandler>;
    type ToSwarm = ping::Event;
    fn handle_established_inbound_connection(
        &mut self,
        id: ConnectionId,
        peer: PeerId,
        local: &Multiaddr,
        remote: &Multiaddr,
    ) -> Result<THandler<Self>, ConnectionDenied> {
        if allow_probe(self.expected, peer, local) && allow_probe(self.expected, peer, remote) {
            Ok(Either::Left(
                self.inner
                    .handle_established_inbound_connection(id, peer, local, remote)?,
            ))
        } else {
            Ok(Either::Right(dummy::ConnectionHandler))
        }
    }
    fn handle_established_outbound_connection(
        &mut self,
        id: ConnectionId,
        peer: PeerId,
        address: &Multiaddr,
        role: Endpoint,
        port_use: PortUse,
    ) -> Result<THandler<Self>, ConnectionDenied> {
        if allow_probe(self.expected, peer, address) {
            Ok(Either::Left(
                self.inner
                    .handle_established_outbound_connection(id, peer, address, role, port_use)?,
            ))
        } else {
            Ok(Either::Right(dummy::ConnectionHandler))
        }
    }
    fn on_swarm_event(&mut self, event: FromSwarm) {
        self.inner.on_swarm_event(event);
    }
    fn on_connection_handler_event(
        &mut self,
        peer: PeerId,
        id: ConnectionId,
        event: THandlerOutEvent<Self>,
    ) {
        match event {
            Either::Left(event) => self.inner.on_connection_handler_event(peer, id, event),
            Either::Right(never) => match never {},
        }
    }
    fn poll(
        &mut self,
        cx: &mut Context<'_>,
    ) -> Poll<ToSwarm<Self::ToSwarm, THandlerInEvent<Self>>> {
        self.inner.poll(cx).map(|event| event.map_in(Either::Left))
    }
}

mod client_behaviour {
    // rust-libp2p's derive emits unreachable From<Infallible> branches for limits.
    #![allow(unreachable_code)]
    use super::*;
    #[derive(NetworkBehaviour)]
    pub struct Client {
        pub observed: observed::ObservedCandidates,
        pub limits: connection_limits::Behaviour,
        pub relay: relay::client::Behaviour,
        pub identify: identify::Behaviour,
        pub dcutr: Toggle<dcutr::Behaviour>,
        pub probe: DirectPing,
        pub streams: tunnel::DirectStreams,
        pub discovery: Toggle<kad::Behaviour<kad::store::MemoryStore>>,
    }
}
pub use client_behaviour::{Client, ClientEvent};

pub fn record_helper_observation(swarm: &mut Swarm<Client>, address: Multiaddr) {
    // Confirmation would suppress NewExternalAddrCandidate and discard the
    // actual mapped port before DCUtR sees it. Discovery is not reachability.
    swarm.behaviour_mut().observed.record(address);
}

pub fn client(
    key: identity::Keypair,
    expected: Option<PeerId>,
    discovery: bool,
) -> anyhow::Result<Swarm<Client>> {
    Ok(libp2p::SwarmBuilder::with_existing_identity(key)
        .with_tokio()
        .with_tcp(
            tcp::Config::default().nodelay(true),
            noise::Config::new,
            yamux::Config::default,
        )?
        .with_quic()
        .with_dns()?
        .with_relay_client(noise::Config::new, yamux::Config::default)?
        .with_behaviour(|key, relay| {
            let peer = key.public().to_peer_id();
            let mut config = kad::Config::new(StreamProtocol::new("/ipfs/kad/1.0.0"));
            config.set_query_timeout(Duration::from_secs(20));
            let mut kad =
                kad::Behaviour::with_config(peer, kad::store::MemoryStore::new(peer), config);
            kad.set_mode(Some(kad::Mode::Client));
            Client {
                observed: observed::ObservedCandidates::default(),
                limits: connection_limits::Behaviour::new(
                    connection_limits::ConnectionLimits::default()
                        .with_max_pending_incoming(Some(8))
                        .with_max_pending_outgoing(Some(8))
                        .with_max_established(Some(32))
                        .with_max_established_per_peer(Some(4)),
                ),
                relay,
                identify: identify::Behaviour::new(identify::Config::new(
                    "/trunkline/experiment/1".into(),
                    key.public(),
                )),
                dcutr: Some(dcutr::Behaviour::new(peer)).into(),
                probe: DirectPing::new(expected),
                streams: tunnel::DirectStreams::new(expected),
                discovery: discovery.then_some(kad).into(),
            }
        })?
        .with_swarm_config(|cfg| cfg.with_idle_connection_timeout(Duration::from_secs(120)))
        .with_connection_timeout(Duration::from_secs(10))
        .build())
}

#[derive(NetworkBehaviour)]
pub struct Helper {
    pub relay: relay::Behaviour,
    pub identify: identify::Behaviour,
}

/// Used only by the loopback test harness, never deployed as a public service.
pub fn local_helper() -> anyhow::Result<Swarm<Helper>> {
    Ok(libp2p::SwarmBuilder::with_new_identity()
        .with_tokio()
        .with_tcp(
            tcp::Config::default().nodelay(true),
            noise::Config::new,
            yamux::Config::default,
        )?
        .with_behaviour(|key| Helper {
            relay: relay::Behaviour::new(key.public().to_peer_id(), relay::Config::default()),
            identify: identify::Behaviour::new(identify::Config::new(
                "/trunkline/local-helper/1".into(),
                key.public(),
            )),
        })?
        .with_swarm_config(|cfg| cfg.with_idle_connection_timeout(Duration::from_secs(90)))
        .build())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn helper_observation_remains_a_candidate_until_reachability_is_proven() {
        use futures::StreamExt;
        let mut swarm = client(identity::Keypair::generate_ed25519(), None, false).unwrap();
        record_helper_observation(
            &mut swarm,
            "/ip4/203.0.113.8/udp/26876/quic-v1".parse().unwrap(),
        );
        let event = tokio::time::timeout(Duration::from_millis(500), swarm.select_next_some())
            .await
            .expect("Premature confirmation hid the observed NAT port from DCUtR");
        match event {
            libp2p::swarm::SwarmEvent::NewExternalAddrCandidate { address } => {
                assert_eq!(address.to_string(), "/ip4/203.0.113.8/udp/26876/quic-v1")
            }
            other => panic!("Expected an observed candidate, got {other:?}"),
        }
        assert_eq!(
            swarm.external_addresses().count(),
            0,
            "An observed address is not verified reachability"
        );
    }
    #[test]
    fn only_the_pinned_peer_on_a_direct_path_can_receive_probe_streams() {
        let expected = PeerId::random();
        let helper = PeerId::random();
        let direct = "/ip4/127.0.0.1/tcp/1234".parse().unwrap();
        let relayed = format!("/ip4/127.0.0.1/tcp/1234/p2p/{helper}/p2p-circuit/p2p/{expected}")
            .parse()
            .unwrap();
        assert!(allow_probe(Some(expected), expected, &direct));
        assert!(!allow_probe(Some(expected), expected, &relayed));
        assert!(!allow_probe(Some(expected), helper, &direct));
        assert!(!allow_probe(None, expected, &direct));
    }
}
