use libp2p::PeerId;
use std::{
    io::{BufRead, BufReader},
    process::{Child, Command, Stdio},
    sync::mpsc,
    time::{Duration, Instant},
};

struct Session {
    child: Child,
    directory: std::path::PathBuf,
}
impl Drop for Session {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.directory);
    }
}

// Exercise the shipped session command, not a second implementation of its
// retry policy. The offline helper uses only loopback and temporary identities.
fn offline_session(mode: &str) -> (Session, mpsc::Receiver<(Instant, String)>) {
    let directory = std::env::temp_dir().join(format!("trunkline-retry-{}", PeerId::random()));
    trunkline_p2p_probe::pair(&directory).unwrap();
    let socket = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = socket.local_addr().unwrap().port();
    drop(socket);
    let helper = format!("/ip4/127.0.0.1/tcp/{port}/p2p/{}", PeerId::random());
    let child = Command::new(env!("CARGO_BIN_EXE_trunkline-p2p-probe"))
        .args(["session", "--config"])
        .arg(directory.join("phone.json"))
        .args(["--helper", &helper, "--mode", mode])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut session = Session { child, directory };
    let output = session.child.stdout.take().unwrap();
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        for line in BufReader::new(output).lines().map_while(Result::ok) {
            if tx.send((Instant::now(), line)).is_err() {
                break;
            }
        }
    });
    (session, rx)
}

#[test]
fn unreachable_helper_backs_off_and_exits_without_manual_cancellation() {
    let (mut session, rx) = offline_session("dial");
    let started = Instant::now();
    let mut attempts = Vec::new();
    loop {
        let remaining = Duration::from_secs(48).saturating_sub(started.elapsed());
        match rx.recv_timeout(remaining) {
            Ok((at, line)) => {
                let value: serde_json::Value = serde_json::from_str(&line).unwrap();
                if value["event"] == "setup_attempt" {
                    attempts.push(at);
                }
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
            Err(mpsc::RecvTimeoutError::Timeout) => {
                panic!("Unreachable Mac left the session connecting beyond its setup budget")
            }
        }
    }
    assert!(
        !session.child.wait().unwrap().success(),
        "An unreachable Mac must report failure"
    );
    assert_eq!(
        attempts.len(),
        5,
        "Retries must be bounded, not loop forever"
    );
    for (interval, minimum) in attempts.windows(2).zip([2.0, 4.0, 8.0, 16.0]) {
        let seconds = interval[1].duration_since(interval[0]).as_secs_f64();
        assert!(
            seconds >= minimum - 0.3 && seconds < minimum + 1.5,
            "Expected exponential backoff near {minimum}s, got {seconds}s"
        );
    }
    assert!(started.elapsed() < Duration::from_secs(48));
}

#[test]
fn cancellation_stops_backoff_without_waiting_for_the_deadline() {
    let (mut session, rx) = offline_session("dial");
    loop {
        let (_, line) = rx.recv_timeout(Duration::from_secs(3)).unwrap();
        let event: serde_json::Value = serde_json::from_str(&line).unwrap();
        if event["event"] == "setup_retry" {
            break;
        }
    }
    assert!(
        Command::new("kill")
            .args(["-INT", &session.child.id().to_string()])
            .status()
            .unwrap()
            .success()
    );
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        match rx.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
            Ok((_, line)) => {
                let event: serde_json::Value = serde_json::from_str(&line).unwrap();
                assert_ne!(
                    event["event"], "setup_attempt",
                    "Cancellation started another retry"
                );
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
            Err(_) => panic!("Cancellation left the worker running"),
        }
    }
    assert!(session.child.wait().unwrap().success());
}

#[test]
fn host_keeps_listening_after_the_client_setup_deadline() {
    let (mut session, rx) = offline_session("listen");
    let started = Instant::now();
    while started.elapsed() < Duration::from_secs(46) {
        assert!(
            session.child.try_wait().unwrap().is_none(),
            "Client timeout stopped host availability"
        );
        match rx.recv_timeout(Duration::from_millis(200)) {
            Err(mpsc::RecvTimeoutError::Disconnected) => panic!("Host worker exited"),
            _ => {}
        }
    }
    assert!(session.child.try_wait().unwrap().is_none());
}
