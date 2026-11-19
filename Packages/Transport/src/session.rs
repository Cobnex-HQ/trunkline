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
    let started = tokio::time::Instant::now();
    let mut next_attempt = started;
    let mut attempts: u32 = 0;
    let mut tick = tokio::time::interval(Duration::from_millis(200));
    emit("session_starting", json!({"host":host,"direct_only":true}));
    // Keep the listener registered across select iterations. Recreating
    // ctrl_c() can lose a signal between dropping and resubscribing.
    let mut interrupt = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())?;
    loop {
        tokio::select! {
            _=tick.tick()=>{
                if crate::native::cancelled(){break;}
                if !host && direct.is_empty() && started.elapsed()>=Duration::from_secs(45) {
                    bail!("Couldn’t reach your Mac. Check that it is awake, online and sharing. These networks may block a direct connection. Tap Connect to retry.");
                }
                let needs_setup = direct.is_empty() && (!helper_connected || (host && !reserved) || (!host && relayed.is_empty()));
                if needs_setup && (host || attempts < 5) && tokio::time::Instant::now() >= next_attempt {
                    attempts = attempts.saturating_add(1);
                    // A client gets five setup attempts, spaced by 2, 4, 8
                    // and 16 seconds, within one non-renewable deadline.
                    // The host remains available and caps its delay at 30s.
                    let delay = Duration::from_secs(2_u64.pow(attempts.min(5)).min(if host { 30 } else { 16 }));
                    next_attempt=tokio::time::Instant::now()+delay;
                    if !host { emit("setup_attempt", json!({"attempt":attempts,"maximum_attempts":5,"next_delay_seconds":if attempts < 5 {Some(delay.as_secs())} else {None}})); }
                    if !helper_connected {let _=swarm.dial(helper.clone());}
                    else if host && !reserved {let _=swarm.listen_on(helper.clone().with(Protocol::P2pCircuit));}
                    else if !host && direct.is_empty() && relayed.is_empty() {let _=swarm.dial(helper.clone().with(Protocol::P2pCircuit).with(Protocol::P2p(expected)));}
                }
            },
            _=interrupt.recv()=>break,
            Some((peer,stream))=async {match incoming.as_mut(){Some(s)=>s.next().await,None=>std::future::pending().await}}=>{
                if peer==expected && flows.len()<64 {flows.spawn(async move{if let Err(e)=serve_stream(stream).await {emit("service_closed",json!({"reason":e.to_string()}));}});}
            },
            _=flows.join_next(),if !flows.is_empty()=>{},
            event=swarm.select_next_some()=>match event {
                SwarmEvent::Behaviour(ClientEvent::Identify(identify::Event::Received{peer_id,info,..})) if peer_id==helper_peer=>{
                    crate::record_helper_observation(&mut swarm,info.observed_addr);
                    // Identify may repeat. Only the scheduled path above may
                    // retry, otherwise these events bypass the attempt budget.
                },
                SwarmEvent::Behaviour(ClientEvent::Relay(relay::client::Event::ReservationReqAccepted{..}))=>{
                    reserved=true;
                    if host { attempts=0;next_attempt=tokio::time::Instant::now(); }
                    emit("remote_waiting",json!({"helper":helper.to_string()}));
                },
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
                SwarmEvent::Behaviour(ClientEvent::Dcutr(e))=>{
                    emit("hole_punch",json!({"success":e.result.is_ok()}));
                    // A failed hole punch leaves a setup-only circuit behind.
                    // Retire it so it cannot suppress the next bounded attempt.
                    if !host && e.result.is_err() && direct.is_empty() {
                        for id in relayed.drain(){swarm.close_connection(id);}
                    }
                },
                SwarmEvent::OutgoingConnectionError{error,..}=>emit("setup_retry",json!({"reason":error.to_string()})),
                _=>{},
            }
        }
    }
    drop(bridge);
    flows.abort_all();
    Ok(true)
}
