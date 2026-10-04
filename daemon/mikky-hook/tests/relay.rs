//! The relay against a real `mikkyd` (built by `cargo build -p mikkyd`):
//! a screen answers a permission, the relay prints Claude's decision.

use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use serde_json::{Value, json};
use tungstenite::Message;
use tungstenite::client::IntoClientRequest;

fn mikkyd() -> Option<PathBuf> {
    let exe = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../target/debug")
        .join(if cfg!(windows) {
            "mikkyd.exe"
        } else {
            "mikkyd"
        });
    exe.exists().then_some(exe)
}

fn relay(endpoint: &str, event: &Value) -> std::process::Child {
    let mut child = Command::new(env!("CARGO_BIN_EXE_mikky-hook"))
        .arg("PermissionRequest")
        .env("MIKKY_HOOK_ENDPOINT", endpoint)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(event.to_string().as_bytes())
        .unwrap();
    child
}

#[test]
fn a_screen_answers_the_terminal_session() {
    let Some(exe) = mikkyd() else {
        eprintln!("skipped: build mikkyd first (cargo build -p mikkyd)");
        return;
    };
    let mut daemon = Command::new(exe)
        .arg("--stdout-endpoint")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut line = String::new();
    BufReader::new(daemon.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    let endpoint: Value = serde_json::from_str(&line).unwrap();
    let endpoint_text = line.trim().to_owned();

    let ask = json!({
        "hook_event_name": "PermissionRequest",
        "session_id": "s-1",
        "cwd": "C:/projet",
        "tool_name": "Bash",
        "tool_input": {"command": "cargo test"},
    });

    // Once for nothing: the first start of a new executable can be slow
    // (the antivirus looks at it).
    relay(&endpoint_text, &json!({})).wait().unwrap();
    // No screen: no decision, at once.
    let started = Instant::now();
    let out = relay(&endpoint_text, &ask).wait_with_output().unwrap();
    assert!(out.stdout.is_empty());
    assert!(started.elapsed() < Duration::from_secs(2));

    // A screen says hello, then answers « allow ».
    let port = endpoint["port"].as_u64().unwrap();
    let mut request = format!("ws://127.0.0.1:{port}/")
        .into_client_request()
        .unwrap();
    request.headers_mut().insert(
        "authorization",
        format!("Bearer {}", endpoint["token"].as_str().unwrap())
            .parse()
            .unwrap(),
    );
    let (mut screen, _) = tungstenite::connect(request).unwrap();
    screen
        .send(Message::text(
            json!({"jsonrpc": "2.0", "id": 1, "method": "hello"}).to_string(),
        ))
        .unwrap();
    let child = relay(&endpoint_text, &ask);
    let id = loop {
        let Message::Text(text) = screen.read().unwrap() else {
            continue;
        };
        let msg: Value = serde_json::from_str(&text).unwrap();
        if msg["method"] == "hooks.changed" {
            if let Some(first) = msg["params"]["requests"].as_array().and_then(|r| r.first()) {
                assert_eq!(first["command"], "cargo test");
                assert_eq!(first["sessionId"], "s-1");
                break first["id"].as_u64().unwrap();
            }
        }
    };
    screen
        .send(Message::text(
            json!({"jsonrpc": "2.0", "id": 2, "method": "hooks.answer", "params": {"id": id, "decision": "allow"}}).to_string(),
        ))
        .unwrap();
    let out = child.wait_with_output().unwrap();
    let printed: Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_eq!(
        printed["hookSpecificOutput"]["hookEventName"],
        "PermissionRequest"
    );
    assert_eq!(
        printed["hookSpecificOutput"]["decision"]["behavior"],
        "allow"
    );

    drop(daemon.stdin.take());
    let _ = daemon.wait();
}
