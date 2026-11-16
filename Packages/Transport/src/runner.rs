use crate::{ClientEvent, client};
use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand, ValueEnum};
use futures::StreamExt;
use libp2p::{
    Multiaddr, PeerId, core::multiaddr::Protocol, identify, identity, kad, relay, swarm::SwarmEvent,
};
use serde_json::json;
use std::{
    collections::{HashMap, HashSet},
    path::PathBuf,
    time::Duration,
};

#[derive(Parser)]
#[command(about = "Temporary peer-assisted setup; probe streams are direct-only. No desktop data.")]
pub(crate) struct Args {
    #[command(subcommand)]
    pub(crate) command: Command,
}
#[derive(Subcommand)]
pub(crate) enum Command {
    /// Look for a willing helper on the public IPFS/libp2p network. No data records are published.
    Discover {
        #[arg(long, default_value = "/dnsaddr/bootstrap.libp2p.io")]
        bootstrap: Multiaddr,
        #[arg(long,default_value_t=60,value_parser=clap::value_parser!(u64).range(5..=120))]
        seconds: u64,
    },
    /// Verify a specific helper accepts a Circuit Relay v2 reservation.
    CheckHelper {
        #[arg(long)]
        helper: Multiaddr,
        #[arg(long,default_value_t=30,value_parser=clap::value_parser!(u64).range(5..=120))]
        seconds: u64,
    },
    /// Generate separate private device identities with mutually pinned peer IDs.
    Pair { directory: PathBuf },
    /// Run the direct-only application transport until stopped.
    Session {
        #[arg(long)]
        config: PathBuf,
        #[arg(long)]
        helper: Multiaddr,
        #[arg(long, value_enum)]
        mode: Mode,
    },
    /// Run one side of a bounded direct-path experiment.
    Probe {
        #[arg(long)]
        config: PathBuf,
        #[arg(long)]
        helper: Multiaddr,
        #[arg(long, value_enum)]
        mode: Mode,
        #[arg(long,default_value_t=90,value_parser=clap::value_parser!(u64).range(5..=300))]
        seconds: u64,
    },
}
#[derive(Clone, Copy, ValueEnum)]
pub(crate) enum Mode {
    Listen,
    Dial,
}

pub(crate) fn emit(event: &str, fields: serde_json::Value) {
    let value = json!({"event":event,"details":fields});
    println!("{}", value);
    crate::native::deliver(&value);
}
pub(crate) fn peer_at(address: &Multiaddr) -> Option<PeerId> {
    address.iter().find_map(|p| {
        if let Protocol::P2p(peer) = p {
            Some(peer)
        } else {
            None
        }
    })
}
fn usable_public(address: &Multiaddr) -> bool {
    address.iter().any(|p| match p {
        Protocol::Ip4(ip) => {
            !ip.is_private()
                && !ip.is_loopback()
                && !ip.is_link_local()
                && !ip.is_unspecified()
                && !ip.is_multicast()
        }
        Protocol::Dns(_) | Protocol::Dns4(_) | Protocol::Dns6(_) => true,
        _ => false,
    }) && !address.iter().any(|p| {
        matches!(
            p,
            Protocol::P2pCircuit | Protocol::WebTransport | Protocol::Ws(_) | Protocol::Wss(_)
        )
    })
}

pub(crate) async fn run(args: Args) -> Result<bool> {
    if let Command::Session {
        config,
        helper,
        mode,
    } = &args.command
    {
        return crate::session::run(
            crate::DeviceConfig::load(config)?,
            helper.clone(),
            matches!(mode, Mode::Listen),
        )
        .await;
    }
    if let Command::Pair { directory } = &args.command {
        crate::pair(directory)?;
        emit(
            "paired",
            json!({"directory":directory,"private_files":["mac.json","phone.json"]}),
        );
        return Ok(true);
    }
    let (key, expected, helper, mode, seconds, discover) = match args.command {
        Command::Discover { bootstrap, seconds } => (
            identity::Keypair::generate_ed25519(),
            None,
            bootstrap,
            None,
            seconds,
            true,
        ),
        Command::CheckHelper { helper, seconds } => (
            identity::Keypair::generate_ed25519(),
            None,
            helper,
            None,
            seconds,
            false,
        ),
        Command::Probe {
            config,
            helper,
            mode,
            seconds,
        } => {
            let config = crate::DeviceConfig::load(&config)?;
            (
                config.identity()?,
                Some(config.expected.parse()?),
                helper,
                Some(mode),
                seconds,
                false,
            )
        }
        Command::Pair { .. } | Command::Session { .. } => unreachable!(),
    };
    if !discover && peer_at(&helper).is_none() {
        bail!("Helper address must include its /p2p/ identity");
    }
    let mut swarm = client(key, expected, discover)?;
    swarm.listen_on("/ip4/0.0.0.0/tcp/0".parse()?)?;
    swarm.listen_on("/ip4/0.0.0.0/udp/0/quic-v1".parse()?)?;
    emit(
        "started",
        json!({"local_peer":swarm.local_peer_id().to_string(),"expected_peer":expected.map(|p|p.to_string()),"seconds":seconds,"direct_only":true}),
    );
    swarm
        .dial(helper.clone())
        .context("Could not start helper connection")?;
    let deadline = tokio::time::sleep(Duration::from_secs(seconds));
    tokio::pin!(deadline);
    let mut queried = false;
    let mut setup_started = false;
    let mut attempted = HashSet::new();
    let mut helper_addresses = HashMap::new();
    let mut identified = 0;
    let mut reservations = 0;
    let mut direct_replies = 0;
    let mut dcutr_successes = 0;
    let mut rtts = Vec::new();
    let mut relayed_connections = HashSet::new();
    let mut direct_connections = HashSet::new();
    let mut reservation_listeners = Vec::new();
    let mut helper_disconnected = false;
    let mut cancellation_tick = tokio::time::interval(Duration::from_millis(100));
    loop {
        tokio::select! {
            _=cancellation_tick.tick()=>if crate::native::cancelled(){break;},
            _=&mut deadline=>break,
            _=tokio::signal::ctrl_c()=>break,
            event=swarm.select_next_some()=>match event {
                SwarmEvent::Behaviour(ClientEvent::Identify(identify::Event::Received{peer_id,info,..}))=>{
                    identified+=1;
                    if discover {
                        let is_kad=info.protocols.iter().any(|p|p.as_ref()=="/ipfs/kad/1.0.0");
                        if is_kad {
                            let kad=swarm.behaviour_mut().discovery.as_mut().unwrap();
                            for addr in &info.listen_addrs { if usable_public(addr){kad.add_address(&peer_id,addr.clone());} }
                            if !queried {kad.get_closest_peers(PeerId::random());queried=true;}
                        }
                        if info.protocols.iter().any(|p|p.as_ref()=="/libp2p/circuit/relay/0.2.0/hop") && attempted.len()<4 && !attempted.contains(&peer_id)
                            && let Some(addr)=info.listen_addrs.iter().find(|a|usable_public(a)) {
                                let mut addr=addr.clone();
                                if peer_at(&addr).is_none(){addr.push(Protocol::P2p(peer_id));}
                                attempted.insert(peer_id);helper_addresses.insert(peer_id,addr.clone());
                                emit("helper_candidate",json!({"address":addr.to_string(),"advertised_addresses":info.listen_addrs.iter().map(|a|a.to_string()).collect::<Vec<_>>()}));
                                match swarm.listen_on(addr.with(Protocol::P2pCircuit)) {
                                    Ok(id)=>reservation_listeners.push(id),
                                    Err(error)=>emit("reservation_error",json!({"error":error.to_string()})),
                                }
                        }
                    } else if Some(peer_id)==peer_at(&helper) && !setup_started {
                        setup_started=true;
                        emit("helper_identified",json!({"addresses":info.listen_addrs.iter().map(|a|a.to_string()).collect::<Vec<_>>(),"observed_address":info.observed_addr.to_string()}));
                        crate::record_helper_observation(&mut swarm,info.observed_addr);
                        match mode {
                            Some(Mode::Dial)=>swarm.dial(helper.clone().with(Protocol::P2pCircuit).with(Protocol::P2p(expected.unwrap())))?,
                            _=>{reservation_listeners.push(swarm.listen_on(helper.clone().with(Protocol::P2pCircuit))?);},
                        }
                    }
                },
                SwarmEvent::Behaviour(ClientEvent::Relay(relay::client::Event::ReservationReqAccepted{relay_peer_id,..}))=>{
                    reservations+=1;
                    let address=helper_addresses.get(&relay_peer_id).unwrap_or(&helper);
                    emit("helper_reserved",json!({"helper":address.to_string(),"peer":relay_peer_id.to_string(),"external_path_verified":false}));
                    if mode.is_none(){break;}
                },
                SwarmEvent::Behaviour(ClientEvent::Dcutr(event))=>{
                    let success=event.result.is_ok();
                    if success {dcutr_successes+=1;}
                    emit("hole_punch",json!({"success":success,"peer":event.remote_peer_id.to_string(),"result":format!("{:?}",event.result)}));
                },
                SwarmEvent::ConnectionEstablished{peer_id,connection_id,endpoint,..}=>{
                    if Some(peer_id)==expected {
                        if endpoint.is_relayed(){relayed_connections.insert(connection_id);}else{direct_connections.insert(connection_id);}
                        emit("paired_connection",json!({"relayed":endpoint.is_relayed(),"connection":connection_id.to_string(),"endpoint":format!("{endpoint:?}")}));
                    }
                },
                SwarmEvent::ConnectionClosed{connection_id,..}=>{
                    relayed_connections.remove(&connection_id);direct_connections.remove(&connection_id);
                },
                SwarmEvent::Behaviour(ClientEvent::Probe(event))=>{
                    if let Ok(rtt)=event.result {
                        if Some(event.peer)!=expected || !direct_connections.contains(&event.connection){bail!("Direct-path invariant failed");}
                        direct_replies+=1;rtts.push(rtt.as_secs_f64()*1000.0);
                        if direct_replies==1 {
                            emit("direct_verified",json!({"rtt_ms":rtt.as_secs_f64()*1000.0,"connection":event.connection.to_string()}));
                            for id in relayed_connections.drain(){swarm.close_connection(id);}
                            for id in reservation_listeners.drain(..){swarm.remove_listener(id);}
                            if let Some(peer)=peer_at(&helper){let _=swarm.disconnect_peer_id(peer);}
                            helper_disconnected=true;
                            emit("helper_released",json!({"direct_session_continues":true}));
                        }
                        if direct_replies>=10 {break;}
                    }
                },
                SwarmEvent::OutgoingConnectionError{error,..}=>emit("dial_error",json!({"error":error.to_string()})),
                SwarmEvent::ListenerError{error,..}=>emit("listener_error",json!({"error":error.to_string()})),
                SwarmEvent::Behaviour(ClientEvent::Discovery(kad::Event::OutboundQueryProgressed{result:kad::QueryResult::GetClosestPeers(result),..}))=>{
                    emit("discovery_query",json!({"success":result.is_ok()}));
                },
                _=>{},
            }
        }
    }
    emit(
        "finished",
        json!({"identified_peers":identified,"helper_reservations":reservations,"direct_replies":direct_replies,
        "hole_punch_successes":dcutr_successes,"rtt_ms":rtts,"helper_disconnected":helper_disconnected,
        "session_traffic_over_relay":false,"phone_cellular_verified":false}),
    );
    Ok(if mode.is_some() {
        direct_replies > 0
    } else {
        reservations > 0
    })
}
