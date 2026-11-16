use libp2p::{
    Multiaddr, PeerId,
    core::{Endpoint, transport::PortUse},
    swarm::{
        ConnectionDenied, ConnectionId, FromSwarm, NetworkBehaviour, THandler, THandlerInEvent,
        THandlerOutEvent, ToSwarm, dummy,
    },
};
use std::collections::VecDeque;
use std::task::{Context, Poll};

/// Preserve the external port the authenticated helper actually observed.
/// Identify's listen-port translation is not valid for every NAT mapping.
#[derive(Default)]
pub struct ObservedCandidates {
    queue: VecDeque<Multiaddr>,
}
impl ObservedCandidates {
    pub fn record(&mut self, address: Multiaddr) {
        if !address
            .iter()
            .any(|part| part == libp2p::core::multiaddr::Protocol::P2pCircuit)
            && self.queue.len() < 8
            && !self.queue.contains(&address)
        {
            self.queue.push_back(address);
        }
    }
}
impl NetworkBehaviour for ObservedCandidates {
    type ConnectionHandler = dummy::ConnectionHandler;
    type ToSwarm = std::convert::Infallible;
    fn handle_established_inbound_connection(
        &mut self,
        _: ConnectionId,
        _: PeerId,
        _: &Multiaddr,
        _: &Multiaddr,
    ) -> Result<THandler<Self>, ConnectionDenied> {
        Ok(dummy::ConnectionHandler)
    }
    fn handle_established_outbound_connection(
        &mut self,
        _: ConnectionId,
        _: PeerId,
        _: &Multiaddr,
        _: Endpoint,
        _: PortUse,
    ) -> Result<THandler<Self>, ConnectionDenied> {
        Ok(dummy::ConnectionHandler)
    }
    fn on_swarm_event(&mut self, _: FromSwarm) {}
    fn on_connection_handler_event(
        &mut self,
        _: PeerId,
        _: ConnectionId,
        event: THandlerOutEvent<Self>,
    ) {
        match event {}
    }
    fn poll(&mut self, _: &mut Context<'_>) -> Poll<ToSwarm<Self::ToSwarm, THandlerInEvent<Self>>> {
        match self.queue.pop_front() {
            Some(address) => Poll::Ready(ToSwarm::NewExternalAddrCandidate(address)),
            None => Poll::Pending,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn actual_mapped_port_reaches_the_hole_puncher_without_listen_port_translation() {
        let mut candidates = ObservedCandidates::default();
        candidates.record("/ip4/203.0.113.8/udp/26876/quic-v1".parse().unwrap());
        let waker = futures::task::noop_waker();
        let mut cx = Context::from_waker(&waker);
        match candidates.poll(&mut cx) {
            Poll::Ready(ToSwarm::NewExternalAddrCandidate(address)) => {
                assert_eq!(address.to_string(), "/ip4/203.0.113.8/udp/26876/quic-v1")
            }
            _ => panic!("Mapped external address was not supplied to DCUtR"),
        }
        candidates.record("/ip4/203.0.113.8/tcp/4001/p2p-circuit".parse().unwrap());
        assert!(
            candidates.poll(&mut cx).is_pending(),
            "Relay address is not a direct candidate"
        );
    }
}
