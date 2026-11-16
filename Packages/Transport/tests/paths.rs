use futures::StreamExt;
use libp2p::{
    Multiaddr, PeerId,
    core::{Endpoint, multiaddr::Protocol, transport::PortUse, upgrade::UpgradeInfo},
    identity,
    swarm::{
        ConnectionHandler, ConnectionId, NetworkBehaviour, SwarmEvent,
        dial_opts::{DialOpts, PeerCondition},
    },
};
use std::time::Duration;
use trunkline_p2p_probe::{ClientEvent, DirectPing, client, local_helper};

#[test]
fn relay_and_unpaired_connections_do_not_negotiate_the_probe_protocol() {
    let paired = PeerId::random();
    let helper = PeerId::random();
    let local: Multiaddr = "/ip4/127.0.0.1/tcp/1".parse().unwrap();
    let relay: Multiaddr = format!("{local}/p2p/{helper}/p2p-circuit").parse().unwrap();
    let remote: Multiaddr = format!("/p2p/{paired}").parse().unwrap();
    let mut gate = DirectPing::new(Some(paired));
    let blocked = gate
        .handle_established_inbound_connection(
            ConnectionId::new_unchecked(1),
            paired,
            &relay,
            &remote,
        )
        .unwrap();
    assert_eq!(
        blocked.listen_protocol().upgrade().protocol_info().count(),
        0
    );
    for (peer, address) in [(paired, &relay), (helper, &local)] {
        let blocked = gate
            .handle_established_outbound_connection(
                ConnectionId::new_unchecked(2),
                peer,
                address,
                Endpoint::Dialer,
                PortUse::Reuse,
            )
            .unwrap();
        assert_eq!(
            blocked.listen_protocol().upgrade().protocol_info().count(),
            0
        );
    }
    let allowed = gate
        .handle_established_outbound_connection(
            ConnectionId::new_unchecked(3),
            paired,
            &local,
            Endpoint::Dialer,
            PortUse::Reuse,
        )
        .unwrap();
    assert_eq!(
        allowed.listen_protocol().upgrade().protocol_info().count(),
        1
    );
}

async fn scenario(upgrade: bool) {
    let mut helper = local_helper().unwrap();
    helper
        .listen_on("/ip4/127.0.0.1/tcp/0".parse().unwrap())
        .unwrap();
    let helper_addr = loop {
        if let SwarmEvent::NewListenAddr { address, .. } = helper.select_next_some().await {
            helper.add_external_address(address.clone());
            break address.with(Protocol::P2p(*helper.local_peer_id()));
        }
    };
    let ka = identity::Keypair::generate_ed25519();
    let kb = identity::Keypair::generate_ed25519();
    let aid = ka.public().to_peer_id();
    let bid = kb.public().to_peer_id();
    let mut a = client(ka, Some(bid), false).unwrap();
    let mut b = client(kb, Some(aid), false).unwrap();
    if !upgrade {
        a.behaviour_mut().dcutr = None.into();
        b.behaviour_mut().dcutr = None.into();
    }
    a.listen_on("/ip4/127.0.0.1/tcp/0".parse().unwrap())
        .unwrap();
    b.listen_on("/ip4/127.0.0.1/tcp/0".parse().unwrap())
        .unwrap();
    a.listen_on(helper_addr.clone().with(Protocol::P2pCircuit))
        .unwrap();
    let mut a_addr = None;
    let mut a_direct = None;
    let mut b_direct = None;
    let mut saw_relay = false;
    let mut upgrades = 0;
    let mut replies = 0;
    let mut stage = 0;
    let mut stage_at = tokio::time::Instant::now();
    let mut tick = tokio::time::interval(Duration::from_millis(100));
    loop {
        tokio::select! {
            _=helper.select_next_some()=>{},
            event=a.select_next_some()=>match event {
                SwarmEvent::NewListenAddr{address,..}=>{
                    if address.iter().any(|p|p==Protocol::P2pCircuit) {
                        b.dial(helper_addr.clone().with(Protocol::P2pCircuit).with(Protocol::P2p(aid))).unwrap();
                    } else {
                        a_addr=Some(address.with(Protocol::P2p(aid)));
                    }
                },
                SwarmEvent::ConnectionEstablished{peer_id,endpoint,connection_id,..} if peer_id==bid=>{
                    if endpoint.is_relayed(){saw_relay=true;stage_at=tokio::time::Instant::now();}else{a_direct=Some(connection_id);}
                },
                SwarmEvent::Behaviour(ClientEvent::Dcutr(event)) if event.result.is_ok()=>upgrades+=1,
                SwarmEvent::Behaviour(ClientEvent::Dcutr(event))=>eprintln!("A upgrade: {event:?}"),
                SwarmEvent::OutgoingConnectionError{error,..}=>eprintln!("A dial: {error}"),
                SwarmEvent::Behaviour(ClientEvent::Probe(event)) if event.result.is_ok()=>{
                    assert_eq!(Some(event.connection),a_direct,"Probe ran over a relayed connection");replies+=1;
                },
                _=>{},
            },
            event=b.select_next_some()=>match event {
                SwarmEvent::ConnectionEstablished{peer_id,endpoint,connection_id,..} if peer_id==aid&&!endpoint.is_relayed()=>b_direct=Some(connection_id),
                SwarmEvent::Behaviour(ClientEvent::Dcutr(event)) if event.result.is_ok()=>upgrades+=1,
                SwarmEvent::Behaviour(ClientEvent::Dcutr(event))=>eprintln!("B upgrade: {event:?}"),
                SwarmEvent::OutgoingConnectionError{error,..}=>eprintln!("B dial: {error}"),
                SwarmEvent::Behaviour(ClientEvent::Probe(event)) if event.result.is_ok()=>{
                    assert_eq!(Some(event.connection),b_direct,"Probe ran over a relayed connection");replies+=1;
                },
                _=>{},
            },
            _=tick.tick()=>{
                if upgrade&&replies>=4 {
                    assert!(saw_relay,"Setup did not use the helper");
                    assert!(upgrades>0,"A direct connection alone is not DCUtR evidence");
                    // Stop polling the helper and disconnect it; direct traffic must continue.
                    let _=a.disconnect_peer_id(*helper.local_peer_id());
                    let _=b.disconnect_peer_id(*helper.local_peer_id());
                    let baseline=replies;
                    let continued=tokio::time::timeout(Duration::from_secs(4),async {
                        let mut n=0;
                        while n<4 {
                            tokio::select! {
                                event=a.select_next_some()=>if let SwarmEvent::Behaviour(ClientEvent::Probe(e))=event && e.result.is_ok(){n+=1;},
                                event=b.select_next_some()=>if let SwarmEvent::Behaviour(ClientEvent::Probe(e))=event && e.result.is_ok(){n+=1;},
                            }
                        }
                        n
                    }).await.expect("Direct session depended on helper staying connected");
                    assert!(baseline+continued>=8);return;
                }
                if !upgrade&&saw_relay&&stage==0&&stage_at.elapsed()>Duration::from_secs(2) {
                    assert_eq!(replies,0,"Relay-only connection carried probes");
                    b.dial(DialOpts::peer_id(aid).condition(PeerCondition::Always).addresses(vec![a_addr.clone().unwrap()]).build()).unwrap();
                    stage=1;
                }
                if !upgrade&&stage==1&&replies>=4 {
                    a.close_connection(a_direct.unwrap());b.close_connection(b_direct.unwrap());
                    stage=2;stage_at=tokio::time::Instant::now();
                }
                if !upgrade&&stage==2&&stage_at.elapsed()>Duration::from_millis(500) {
                    replies=0;stage=3;stage_at=tokio::time::Instant::now();
                }
                if !upgrade&&stage==3&&stage_at.elapsed()>Duration::from_secs(2) {
                    assert_eq!(replies,0,"Direct failure fell back to the remaining relay path");return;
                }
            },
        }
    }
}

#[tokio::test]
async fn relay_setup_upgrades_and_direct_probes_survive_helper_disconnect() {
    tokio::time::timeout(Duration::from_secs(25), scenario(true))
        .await
        .expect("DCUtR loopback scenario timed out");
}

#[tokio::test]
async fn relay_only_and_lost_direct_paths_never_carry_probe_traffic() {
    tokio::time::timeout(Duration::from_secs(25), scenario(false))
        .await
        .expect("Direct-only gate scenario timed out");
}
