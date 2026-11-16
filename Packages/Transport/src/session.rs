use crate::{
    ClientEvent, DeviceConfig, client,
    runner::{emit, peer_at},
    tunnel::{ClientBridge, serve_stream},
};
use anyhow::{Result, bail};
use futures::StreamExt;
use libp2p::{
    Multiaddr, StreamProtocol, core::multiaddr::Protocol, identify, relay, swarm::SwarmEvent,
};
use serde_json::json;
use std::{collections::HashSet, time::Duration};

pub(crate) async fn run(config: DeviceConfig, helper: Multiaddr, host: bool) -> Result<bool> {
    let expected = config.expected.parse()?;
    let helper_peer =
        peer_at(&helper).ok_or_else(|| anyhow::anyhow!("Helper identity is missing"))?;
    if helper_peer == expected {
        bail!("Setup helper must be separate from paired device");
    }
    let mut swarm = client(config.identity()?, Some(expected), false)?;
    swarm.listen_on("/ip4/0.0.0.0/tcp/0".parse()?)?;
    swarm.listen_on("/ip4/0.0.0.0/udp/0/quic-v1".parse()?)?;
    let mut control = swarm.behaviour().streams.control();
    // The phone does not accept reverse service requests.
    let mut incoming = if host {
        Some(control.accept(StreamProtocol::new("/trunkline/forward/1"))?)
    } else {
        None
    };
    let mut flows = tokio::task::JoinSet::new();
    let mut bridge = None;
    let mut direct = HashSet::new();
    let mut relayed = HashSet::new();
    let mut reserved = false;
    let mut helper_connected = false;
    let mut last_attempt = tokio::time::Instant::now() - Duration::from_secs(60);
    let started = tokio::time::Instant::now();
    let mut tick = tokio::time::interval(Duration::from_millis(200));
    emit("session_starting", json!({"host":host,"direct_only":true}));
    loop {
        tokio::select! {
            _=tick.tick()=>{
                if crate::native::cancelled(){break;}
                if !host && direct.is_empty() && started.elapsed()>Duration::from_secs(90) {bail!("No direct path could be established. Keep the Mac online and retry.");}
                if last_attempt.elapsed()>Duration::from_secs(15) {
                    last_attempt=tokio::time::Instant::now();
                    if !helper_connected {let _=swarm.dial(helper.clone());}
                    else if host && !reserved {let _=swarm.listen_on(helper.clone().with(Protocol::P2pCircuit));}
                    else if !host && direct.is_empty() && relayed.is_empty() {let _=swarm.dial(helper.clone().with(Protocol::P2pCircuit).with(Protocol::P2p(expected)));}
                }
            },
            _=tokio::signal::ctrl_c()=>break,
            Some((peer,stream))=async {match incoming.as_mut(){Some(s)=>s.next().await,None=>std::future::pending().await}}=>{
                if peer==expected && flows.len()<64 {flows.spawn(async move{if let Err(e)=serve_stream(stream).await {emit("service_closed",json!({"reason":e.to_string()}));}});}
            },
            _=flows.join_next(),if !flows.is_empty()=>{},
            event=swarm.select_next_some()=>match event {
                SwarmEvent::Behaviour(ClientEvent::Identify(identify::Event::Received{peer_id,info,..})) if peer_id==helper_peer=>{
                    crate::record_helper_observation(&mut swarm,info.observed_addr);
                    if host && !reserved {let _=swarm.listen_on(helper.clone().with(Protocol::P2pCircuit));}
                    else if !host && direct.is_empty() && relayed.is_empty() {let _=swarm.dial(helper.clone().with(Protocol::P2pCircuit).with(Protocol::P2p(expected)));}
                },
                SwarmEvent::Behaviour(ClientEvent::Relay(relay::client::Event::ReservationReqAccepted{..}))=>{reserved=true;emit("remote_waiting",json!({"helper":helper.to_string()}));},
                SwarmEvent::ListenerClosed{addresses,..}=>{if addresses.iter().any(|a|a.iter().any(|p|p==Protocol::P2pCircuit)){reserved=false;}},
                SwarmEvent::ConnectionEstablished{peer_id,connection_id,endpoint,..}=>{
                    if peer_id==helper_peer {helper_connected=true;}
                    if peer_id==expected {
                        if endpoint.is_relayed(){relayed.insert(connection_id);}else{
                            direct.insert(connection_id);
                            for id in relayed.drain(){swarm.close_connection(id);}
                            if !host && bridge.is_none(){bridge=Some(ClientBridge::start(control.clone(),expected).await?);}
                            emit("tunnel_ready",json!({"direct_only":true,"host":host}));
                        }
                    }
                },
                SwarmEvent::ConnectionClosed{peer_id,connection_id,..}=>{
                    if peer_id==helper_peer {helper_connected=false;reserved=false;}
                    relayed.remove(&connection_id);
                    if direct.remove(&connection_id)&&direct.is_empty(){
                        bridge=None;flows.abort_all();emit("tunnel_lost",json!({"retry":true}));
                        if !host {bail!("Direct connection lost. Reconnect to your Mac.");}
                    }
                },
                SwarmEvent::Behaviour(ClientEvent::Dcutr(e))=>emit("hole_punch",json!({"success":e.result.is_ok()})),
                SwarmEvent::OutgoingConnectionError{error,..}=>emit("setup_retry",json!({"reason":error.to_string()})),
                _=>{},
            }
        }
    }
    drop(bridge);
    flows.abort_all();
    Ok(true)
}
