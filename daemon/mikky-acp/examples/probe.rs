//! R0 probe: starts an ACP adapter from Rust, opens a session and prints what
//! the agent sends for a few seconds. No prompt, so it costs nothing.
//!
//! cargo run --example probe -- <adapter index.js> [folder]

use std::path::PathBuf;
use std::time::Duration;

use mikky_acp::acp::schema::ProtocolVersion;
use mikky_acp::acp::schema::v1::{InitializeRequest, NewSessionRequest, SessionNotification};
use mikky_acp::acp::{self, Agent, ConnectionTo};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let adapter = args.next().expect("usage: probe <adapter index.js> [folder]");
    let cwd = args.next().map(PathBuf::from).unwrap_or(std::env::current_dir()?);

    let (_child, transport) = mikky_acp::spawn("node", &[&adapter], &cwd)?;
    acp::Client
        .builder()
        .on_receive_notification(
            async move |n: SessionNotification, _cx| {
                println!("update: {:?}", n.update);
                Ok(())
            },
            acp::on_receive_notification!(),
        )
        .connect_with(transport, |connection: ConnectionTo<Agent>| async move {
            let init = connection
                .send_request(InitializeRequest::new(ProtocolVersion::V1))
                .block_task()
                .await?;
            println!("agent: {:?}", init.agent_info);
            let session = connection
                .send_request(NewSessionRequest::new(cwd.clone()))
                .block_task()
                .await?;
            println!("session: {}", session.session_id);
            println!("modes: {:?}", session.modes.map(|m| m.available_modes.into_iter().map(|m| m.id).collect::<Vec<_>>()));
            tokio::time::sleep(Duration::from_secs(3)).await;
            Ok(())
        })
        .await?;
    Ok(())
}
