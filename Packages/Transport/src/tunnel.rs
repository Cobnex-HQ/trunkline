use crate::allow_probe;
use anyhow::{Result, bail};
use either::Either;
use libp2p::{
    Multiaddr, PeerId, StreamProtocol,
    core::{Endpoint, transport::PortUse},
    swarm::{
        ConnectionDenied, ConnectionId, FromSwarm, NetworkBehaviour, THandler, THandlerInEvent,
        THandlerOutEvent, ToSwarm, dummy,
    },
};
use std::{
    sync::Arc,
    task::{Context, Poll},
    time::Duration,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream, UdpSocket},
    task::JoinSet,
};
use tokio_util::compat::FuturesAsyncReadCompatExt;
const PROTOCOL: StreamProtocol = StreamProtocol::new("/trunkline/forward/1");
pub const TCP_PORTS: &[u16] = &[47995, 47989, 47984, 48010];
pub const UDP_PORTS: &[u16] = &[47998, 47999, 48000];
pub struct DirectStreams {
    expected: Option<PeerId>,
    inner: libp2p_stream::Behaviour,
}
impl DirectStreams {
    pub fn new(expected: Option<PeerId>) -> Self {
        Self {
            expected,
            inner: libp2p_stream::Behaviour::new(),
        }
    }
}
impl DirectStreams {
    pub fn control(&self) -> libp2p_stream::Control {
        self.inner.new_control()
    }
}
impl NetworkBehaviour for DirectStreams {
    type ConnectionHandler = Either<
        <libp2p_stream::Behaviour as NetworkBehaviour>::ConnectionHandler,
        dummy::ConnectionHandler,
    >;
    type ToSwarm = ();
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
        // Never tell the stream scheduler about relay or unpaired connections.
        // Otherwise it could select one when opening an outbound stream.
        if let FromSwarm::ConnectionEstablished(e) = event
            && (self.expected != Some(e.peer_id) || e.endpoint.is_relayed())
        {
            return;
        }
        self.inner.on_swarm_event(event);
    }
    fn on_connection_handler_event(
        &mut self,
        _peer: PeerId,
        _id: ConnectionId,
        event: THandlerOutEvent<Self>,
    ) {
        match event {
            Either::Left(never) => match never {},
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

// Only the fixed companion and streaming services are reachable. In particular,
// the Sunshine management API, SSH, and arbitrary LAN destinations are absent.
pub async fn serve_stream(stream: libp2p::swarm::Stream) -> Result<()> {
    let mut stream = stream.compat();
    let mut header = [0; 3];
    tokio::time::timeout(Duration::from_secs(5), stream.read_exact(&mut header)).await??;
    let port = u16::from_be_bytes([header[1], header[2]]);
    match header[0] {
        1 if TCP_PORTS.contains(&port) => {
            let mut socket = tokio::time::timeout(
                Duration::from_secs(5),
                TcpStream::connect(("127.0.0.1", port)),
            )
            .await??;
            socket.set_nodelay(true)?;
            stream.write_all(&[0]).await?;
            tokio::io::copy_bidirectional(&mut socket, &mut stream).await?;
        }
        2 if UDP_PORTS.contains(&port) => {
            let socket = UdpSocket::bind(("127.0.0.1", 0)).await?;
            socket.connect(("127.0.0.1", port)).await?;
            stream.write_all(&[0]).await?;
            udp_pipe(stream, &socket, None).await?;
        }
        _ => {
            stream.write_all(&[1]).await?;
            bail!("Service is not permitted");
        }
    }
    Ok(())
}
async fn open(
    mut control: libp2p_stream::Control,
    peer: PeerId,
    kind: u8,
    port: u16,
) -> Result<tokio_util::compat::Compat<libp2p::swarm::Stream>> {
    tokio::time::timeout(Duration::from_secs(8), async move {
        let mut stream = control.open_stream(peer, PROTOCOL).await?.compat();
        let p = port.to_be_bytes();
        stream.write_all(&[kind, p[0], p[1]]).await?;
        let status = stream.read_u8().await?;
        if status != 0 {
            bail!("Peer refused service");
        }
        Ok(stream)
    })
    .await?
}
pub async fn forward_tcp(
    control: libp2p_stream::Control,
    peer: PeerId,
    port: u16,
    mut socket: TcpStream,
) -> Result<()> {
    socket.set_nodelay(true)?;
    let mut stream = open(control, peer, 1, port).await?;
    tokio::io::copy_bidirectional(&mut socket, &mut stream).await?;
    Ok(())
}
// Each UDP service has an independent QUIC stream. No queue grows without bound:
// a stalled lane is closed instead of retaining seconds of obsolete video.
// This first bridge preserves packet boundaries but still retransmits lost data;
// it is not an unreliable QUIC DATAGRAM transport or a latency benchmark.
async fn udp_pipe(
    stream: tokio_util::compat::Compat<libp2p::swarm::Stream>,
    socket: &UdpSocket,
    destination: Option<std::net::SocketAddr>,
) -> Result<()> {
    let (mut read, mut write) = tokio::io::split(stream);
    let destination = destination.map(std::sync::Mutex::new);
    let outgoing = async {
        let mut bytes = vec![0; 65535];
        loop {
            let n = if let Some(destination) = &destination {
                let (n, from) = socket.recv_from(&mut bytes).await?;
                *destination.lock().unwrap() = from;
                n
            } else {
                socket.recv(&mut bytes).await?
            };
            tokio::time::timeout(Duration::from_secs(2), async {
                write.write_u16(n as u16).await?;
                write.write_all(&bytes[..n]).await?;
                write.flush().await
            })
            .await??;
        }
        #[allow(unreachable_code)]
        Ok::<(), anyhow::Error>(())
    };
    let incoming = async {
        let mut bytes = vec![0; 65535];
        loop {
            let n = read.read_u16().await? as usize;
            read.read_exact(&mut bytes[..n]).await?;
            let address = destination.as_ref().map(|d| *d.lock().unwrap());
            if let Some(address) = address {
                socket.send_to(&bytes[..n], address).await?;
            } else {
                socket.send(&bytes[..n]).await?;
            }
        }
        #[allow(unreachable_code)]
        Ok::<(), anyhow::Error>(())
    };
    tokio::select! {r=outgoing=>r,r=incoming=>r}
}
pub async fn forward_udp(
    control: libp2p_stream::Control,
    peer: PeerId,
    port: u16,
    socket: Arc<UdpSocket>,
) -> Result<()> {
    // Moonlight owns one socket per service. Follow its local endpoint when a
    // desktop is reopened without reconnecting the companion session.
    let mut first = vec![0; 65535];
    let (n, address) = socket.recv_from(&mut first).await?;
    let mut stream = open(control, peer, 2, port).await?;
    stream.write_u16(n as u16).await?;
    stream.write_all(&first[..n]).await?;
    stream.flush().await?;
    udp_pipe(stream, &socket, Some(address)).await
}

/// All sockets bind loopback. Dropping this owner aborts listeners and connections.
pub struct ClientBridge {
    tasks: JoinSet<()>,
}
impl ClientBridge {
    pub async fn start(control: libp2p_stream::Control, peer: PeerId) -> Result<Self> {
        let mut tasks = JoinSet::new();
        // Bind everything before reporting ready; a partial bridge is unusable.
        let mut tcp = Vec::new();
        let mut udp = Vec::new();
        for &port in TCP_PORTS {
            tcp.push((port, TcpListener::bind(("127.0.0.1", port)).await?));
        }
        for &port in UDP_PORTS {
            udp.push((port, Arc::new(UdpSocket::bind(("127.0.0.1", port)).await?)));
        }
        for (port, listener) in tcp {
            let control = control.clone();
            tasks.spawn(async move {
                let mut flows=JoinSet::new();
                loop {tokio::select!{
                    result=listener.accept()=>match result {
                        Ok((socket,_)) if flows.len()<32=>{let c=control.clone();flows.spawn(async move{let _=forward_tcp(c,peer,port,socket).await;});},
                        Ok(_)=>{},Err(_)=>break,
                    },
                    _=flows.join_next(),if !flows.is_empty()=>{},
                }}
            });
        }
        for (port, socket) in udp {
            let control = control.clone();
            tasks.spawn(async move {
                loop {
                    let _ = forward_udp(control.clone(), peer, port, socket.clone()).await;
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }
            });
        }
        Ok(Self { tasks })
    }
}
impl Drop for ClientBridge {
    fn drop(&mut self) {
        self.tasks.abort_all();
    }
}
