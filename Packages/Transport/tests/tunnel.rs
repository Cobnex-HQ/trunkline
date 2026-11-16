use futures::StreamExt;
use libp2p::{
    PeerId, StreamProtocol,
    core::{Endpoint, transport::PortUse, upgrade::UpgradeInfo},
    identity,
    swarm::{ConnectionHandler, ConnectionId, NetworkBehaviour, SwarmEvent},
};
use std::time::Duration;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream, UdpSocket},
};
use trunkline_p2p_probe::{
    client,
    tunnel::{DirectStreams, forward_tcp, forward_udp, serve_stream},
};

#[test]
fn application_protocol_is_absent_on_relay_and_unpaired_connections() {
    let peer = PeerId::random();
    let helper = PeerId::random();
    let mut gate = DirectStreams::new(Some(peer));
    let mut control = gate.control();
    let _incoming = control
        .accept(StreamProtocol::new("/trunkline/forward/1"))
        .unwrap();
    let direct = "/ip4/127.0.0.1/tcp/1".parse().unwrap();
    let relay = format!("/ip4/127.0.0.1/tcp/1/p2p/{helper}/p2p-circuit")
        .parse()
        .unwrap();
    for (p, a) in [(peer, &relay), (helper, &direct)] {
        let h = gate
            .handle_established_outbound_connection(
                ConnectionId::new_unchecked(1),
                p,
                a,
                Endpoint::Dialer,
                PortUse::Reuse,
            )
            .unwrap();
        assert_eq!(h.listen_protocol().upgrade().protocol_info().count(), 0);
    }
    let h = gate
        .handle_established_inbound_connection(
            ConnectionId::new_unchecked(2),
            peer,
            &relay,
            &format!("/p2p/{peer}").parse().unwrap(),
        )
        .unwrap();
    assert_eq!(h.listen_protocol().upgrade().protocol_info().count(), 0);
    let h = gate
        .handle_established_outbound_connection(
            ConnectionId::new_unchecked(3),
            peer,
            &direct,
            Endpoint::Dialer,
            PortUse::Reuse,
        )
        .unwrap();
    assert_eq!(h.listen_protocol().upgrade().protocol_info().count(), 1);
}

// Real sockets and encrypted libp2p streams: catches payload truncation, framing,
// wrong return endpoint, and accidental access to unapproved local services.
#[tokio::test]
async fn direct_tunnel_carries_tcp_and_udp_and_rejects_arbitrary_ports() {
    tokio::time::timeout(Duration::from_secs(15),async {
  let akey=identity::Keypair::generate_ed25519();let bkey=identity::Keypair::generate_ed25519();
  let aid=akey.public().to_peer_id();let bid=bkey.public().to_peer_id();
  let mut a=client(akey,Some(bid),false).unwrap();let mut b=client(bkey,Some(aid),false).unwrap();
  let mut ac=a.behaviour().streams.control();let mut incoming=ac.accept(StreamProtocol::new("/trunkline/forward/1")).unwrap();
  let bc=b.behaviour().streams.control();
  a.listen_on("/ip4/127.0.0.1/udp/0/quic-v1".parse().unwrap()).unwrap();
  let addr=loop {if let SwarmEvent::NewListenAddr{address,..}=a.select_next_some().await{break address;}};
  b.dial(addr).unwrap();
  loop{tokio::select!{e=a.select_next_some()=>{if matches!(e,SwarmEvent::ConnectionEstablished{..}){break;}},_=b.select_next_some()=>{}}}
  let pump=tokio::spawn(async move{loop{tokio::select!{_=a.select_next_some()=>{},_=b.select_next_some()=>{},Some((_,s))=incoming.next()=>{tokio::spawn(async move{let _=serve_stream(s).await;});}}}});
  let tcp=TcpListener::bind(("127.0.0.1",47995)).await.unwrap();
  let echo=tokio::spawn(async move{let(mut s,_)=tcp.accept().await.unwrap();let(mut r,mut w)=s.split();tokio::io::copy(&mut r,&mut w).await.unwrap();});
  let local=TcpListener::bind(("127.0.0.1",0)).await.unwrap();let port=local.local_addr().unwrap().port();
  let c=bc.clone();let bridge=tokio::spawn(async move{let(s,_)=local.accept().await.unwrap();forward_tcp(c,aid,47995,s).await.unwrap();});
  let mut socket=TcpStream::connect(("127.0.0.1",port)).await.unwrap();
  let data=vec![0xA5;256*1024];socket.write_all(&data).await.unwrap();socket.shutdown().await.unwrap();let mut got=Vec::new();socket.read_to_end(&mut got).await.unwrap();assert_eq!(got,data);bridge.await.unwrap();echo.await.unwrap();
  let udp=UdpSocket::bind(("127.0.0.1",47998)).await.unwrap();
  let echo=tokio::spawn(async move{let mut buf=[0;65535];for _ in 0..4{let(n,addr)=udp.recv_from(&mut buf).await.unwrap();udp.send_to(&buf[..n],addr).await.unwrap();}});
  let local=std::sync::Arc::new(UdpSocket::bind(("127.0.0.1",0)).await.unwrap());let addr=local.local_addr().unwrap();
  let c=bc.clone();let udp_bridge=tokio::spawn(async move{forward_udp(c,aid,47998,local).await.unwrap();});
  let s=UdpSocket::bind(("127.0.0.1",0)).await.unwrap();s.connect(addr).await.unwrap();
  for data in [vec![1;1],vec![2;1400],vec![3;8192]]{s.send(&data).await.unwrap();let mut buf=vec![0;65535];let n=s.recv(&mut buf).await.unwrap();assert_eq!(&buf[..n],data);}
  let reopened = UdpSocket::bind(("127.0.0.1", 0)).await.unwrap();
  reopened.send_to(b"new desktop socket", addr).await.unwrap();
  let mut reply = [0; 64];
  let n = tokio::time::timeout(Duration::from_secs(2), reopened.recv(&mut reply)).await
      .expect("Reopened desktop replies went to the old UDP socket").unwrap();
  assert_eq!(&reply[..n], b"new desktop socket");
  echo.await.unwrap();udp_bridge.abort();
  use tokio_util::compat::FuturesAsyncReadCompatExt;
  let mut c=bc;let mut s=c.open_stream(aid,StreamProtocol::new("/trunkline/forward/1")).await.unwrap().compat();
  s.write_all(&[1,0,22]).await.unwrap();let mut result=[0];let n=s.read(&mut result).await.unwrap();assert!(n==0||result[0]!=0,"SSH/arbitrary local service was exposed");
  pump.abort();
 }).await.expect("Tunnel integration timed out");
}
