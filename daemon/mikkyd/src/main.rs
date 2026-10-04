//! `mikkyd`: the one that launches and follows agents (spec
//! `docs/superpowers/specs/2026-09-30-mikkyd-design.md`). The app is only a
//! screen on it.
//!
//! `mikkyd` alone: one per Windows session, endpoint in the credential
//! store, keeps working after the last screen leaves.
//! `mikkyd --stdout-endpoint`: prints the endpoint and ends
//! when its stdin closes (tests).

#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod api;
mod autostart;
mod claude_settings;
mod endpoint;
mod hooks;
mod job;
#[cfg(unix)]
mod linux;
mod login;
mod session_reader;
mod store;
mod target;
mod tools;
mod watch;
mod wsl;

use std::sync::Arc;

use tokio::io::AsyncReadExt;
use tokio::net::TcpListener;

#[tokio::main]
async fn main() {
    if let Some(mode) = std::env::args().skip_while(|a| a != "--autostart").nth(1) {
        let enabled = match mode.as_str() {
            "enable" => Some(true), "disable" => Some(false), "status" => None,
            _ => { eprintln!("Expected enable, disable or status"); std::process::exit(2); }
        };
        match autostart::configure(enabled).await {
            Ok(value) => println!("{value}"),
            Err(e) => { eprintln!("{}",e.message); std::process::exit(1); }
        }
        return;
    }
    #[cfg(unix)]
    if std::env::args().any(|a| a == "--bridge") {
        if let Err(e) = linux::bridge().await {
            eprintln!("{e}");
            std::process::exit(1);
        }
        return;
    }
    let stdout_endpoint = std::env::args().any(|a| a == "--stdout-endpoint");
    if !stdout_endpoint && !endpoint::single_instance() {
        return;
    }
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("cannot listen on 127.0.0.1");
    let port = listener.local_addr().expect("no local address").port();
    let token = endpoint::new_token();
    let data = if cfg!(windows) {
        std::env::var_os("APPDATA")
            .map(std::path::PathBuf::from)
            .map(|p| p.join("Mikky").join("mikky.db"))
    } else {
        std::env::var_os("HOME")
            .map(std::path::PathBuf::from)
            .map(|p| p.join(".local/share/mikky/mikky.db"))
    };
    let store = store::Store::open(if stdout_endpoint {
        None
    } else {
        data.as_deref()
    })
    .expect("cannot open Mikky state");
    let watch_home = std::env::args()
        .skip_while(|a| a != "--watch-home")
        .nth(1)
        .map(std::path::PathBuf::from)
        .or_else(|| {
            if stdout_endpoint {
                None
            } else {
                std::env::var_os("USERPROFILE")
                    .or_else(|| std::env::var_os("HOME"))
                    .map(std::path::PathBuf::from)
            }
        });
    let sessions = match watch_home {
        Some(home) => watch::Sessions::start(home).expect("cannot watch sessions"),
        None => watch::Sessions::empty(),
    };
    let daemon = Arc::new(api::Daemon::new(
        store,
        sessions,
        cfg!(windows) && (!stdout_endpoint || std::env::args().any(|a| a == "--with-wsl")),
    ));
    #[cfg(unix)]
    if !stdout_endpoint {
        if let Err(e) = linux::serve(daemon).await {
            eprintln!("{e}");
            std::process::exit(1);
        }
        return;
    }
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
        // The desktop is a client. Closing it must never cancel work or
        // decide a pending permission. No idle timer / background polling.
        daemon.wait_shutdown().await;
    }
    daemon.stop_all().await;
}
