//! `mikkyd`: the one that launches and follows agents (spec
//! `docs/superpowers/specs/2026-09-30-mikkyd-design.md`). The app is only a
//! screen on it.
//!
//! `mikkyd` alone: one per Windows session, endpoint in the credential
//! store, ends a minute after the last screen left (R1: agents still stop
//! with the app). `mikkyd --stdout-endpoint`: prints the endpoint and ends
//! when its stdin closes (tests).

#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod api;
mod endpoint;
mod job;
mod target;

use std::sync::Arc;
use std::time::Duration;

use tokio::io::AsyncReadExt;
use tokio::net::TcpListener;

/// How long `mikkyd` waits for a screen to come back (an app restart).
const IDLE: Duration = Duration::from_secs(60);

#[tokio::main]
async fn main() {
    let stdout_endpoint = std::env::args().any(|a| a == "--stdout-endpoint");
    if !stdout_endpoint && !endpoint::single_instance() {
        return;
    }
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("cannot listen on 127.0.0.1");
    let port = listener.local_addr().expect("no local address").port();
    let token = endpoint::new_token();
    let daemon = Arc::new(api::Daemon::default());
    tokio::spawn(api::serve(listener, token.clone(), daemon.clone()));

    if stdout_endpoint {
        println!("{}", endpoint::describe(port, &token));
        let mut rest = Vec::new();
        let _ = tokio::io::stdin().read_to_end(&mut rest).await;
    } else {
        if let Err(e) = endpoint::publish(port, &token) {
            eprintln!("mikkyd: cannot publish the endpoint: {e}");
            return;
        }
        daemon.idle(IDLE).await;
    }
    daemon.stop_all().await;
}
