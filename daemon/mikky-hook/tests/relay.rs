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
    relay_with(endpoint, event, &["PermissionRequest"])
}

fn relay_with(endpoint: &str, event: &Value, args: &[&str]) -> std::process::Child {
    let mut child = Command::new(env!("CARGO_BIN_EXE_mikky-hook"))
        .args(args)
        .env("MIKKY_HOOK_ENDPOINT", endpoint)
        // A terminal, even when the tests run inside Claude's app.
        .env_remove("CLAUDE_CODE_ENTRYPOINT")
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

/// The first request `mikkyd` lists to the screen (`hooks.changed`).
fn next_request<S: std::io::Read + std::io::Write>(
    screen: &mut tungstenite::WebSocket<S>,
) -> Value {
    loop {
        let Message::Text(text) = screen.read().unwrap() else {
            continue;
        };
        let msg: Value = serde_json::from_str(&text).unwrap();
        if msg["method"] == "hooks.changed"
            && let Some(first) = msg["params"]["requests"].as_array().and_then(|r| r.first())
        {
            return first.clone();
        }
    }
}

fn start_daemon(exe: PathBuf) -> (std::process::Child, String, Value) {
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
    (daemon, line.trim().to_owned(), endpoint)
}

type Screen = tungstenite::WebSocket<tungstenite::stream::MaybeTlsStream<std::net::TcpStream>>;

fn connect_screen(endpoint: &Value) -> Screen {
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
    let (screen, _) = tungstenite::connect(request).unwrap();
    if let tungstenite::stream::MaybeTlsStream::Plain(tcp) = screen.get_ref() {
        tcp.set_read_timeout(Some(Duration::from_secs(10))).unwrap();
    }
    screen
}

fn call(screen: &mut Screen, method: &str, params: Value) -> Value {
    screen
        .send(Message::text(
            json!({"jsonrpc":"2.0","id":99,"method":method,"params":params}).to_string(),
        ))
        .unwrap();
    loop {
        let Message::Text(text) = screen.read().unwrap() else {
            continue;
        };
        let answer: Value = serde_json::from_str(&text).unwrap();
        if answer["id"] == 99 {
            assert!(answer["error"].is_null(), "{answer}");
            return answer["result"].clone();
        }
    }
}

#[test]
fn a_screen_answers_the_terminal_session() {
    let Some(exe) = mikkyd() else {
        eprintln!("skipped: build mikkyd first (cargo build -p mikkyd)");
        return;
    };
    let (mut daemon, endpoint_text, endpoint) = start_daemon(exe);

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
    let mut screen = connect_screen(&endpoint);
    screen
        .send(Message::text(
            json!({"jsonrpc": "2.0", "id": 1, "method": "hello"}).to_string(),
        ))
        .unwrap();
    let child = relay(&endpoint_text, &ask);
    let first = next_request(&mut screen);
    assert_eq!(first["command"], "cargo test");
    assert_eq!(first["sessionId"], "s-1");
    let id = first["id"].as_u64().unwrap();
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

    // Claude's question: answered from the screen, then left to the terminal.
    let question = json!({
        "hook_event_name": "PermissionRequest",
        "session_id": "s-2",
        "cwd": "C:/projet",
        "tool_name": "AskUserQuestion",
        "tool_input": {"questions": [
            {"question": "Quels tests ?", "header": "Tests", "multiSelect": true, "options": [
                {"label": "Unitaires", "description": "Rapides"},
                {"label": "Bout en bout", "description": "Lents"},
            ]},
        ]},
    });
    let mut next_id = 3;
    let mut ask = |screen: &mut tungstenite::WebSocket<_>, answers: Value| {
        let child = relay_with(&endpoint_text, &question, &["PermissionRequest"]);
        let first = next_request(screen);
        assert_eq!(first["kind"], "question");
        assert_eq!(first["questions"][0]["options"][1]["label"], "Bout en bout");
        let id = first["id"].as_u64().unwrap();
        screen
            .send(Message::text(
                json!({"jsonrpc": "2.0", "id": next_id, "method": "hooks.answer", "params": {"id": id, "answers": answers}}).to_string(),
            ))
            .unwrap();
        next_id += 1;
        child.wait_with_output().unwrap().stdout
    };
    let out = ask(&mut screen, json!({"q1": ["Unitaires"]}));
    let printed: Value = serde_json::from_slice(&out).unwrap();
    let o = &printed["hookSpecificOutput"];
    assert_eq!(o["hookEventName"], "PermissionRequest");
    assert_eq!(o["decision"]["behavior"], "allow");
    let updated = &o["decision"]["updatedInput"];
    assert_eq!(updated["questions"], question["tool_input"]["questions"]);
    assert_eq!(updated["answers"], json!({"Quels tests ?": ["Unitaires"]}));
    // « Répondre dans le terminal »: nothing printed.
    assert!(ask(&mut screen, Value::Null).is_empty());
    // The old question hook (settings not written again yet): nothing
    // asked, nothing printed, at once.
    let started = Instant::now();
    let mut old = question.clone();
    old["hook_event_name"] = json!("PreToolUse");
    let out = relay_with(&endpoint_text, &old, &["--ask", "PreToolUse"])
        .wait_with_output()
        .unwrap();
    assert!(out.stdout.is_empty());
    assert!(started.elapsed() < Duration::from_secs(2));

    drop(daemon.stdin.take());
    let _ = daemon.wait();
}

#[test]
fn external_messages_are_printed_then_acknowledged_and_failures_are_silent() {
    let (mut daemon, endpoint, address) = start_daemon(mikkyd().expect("build mikkyd first"));
    let mut screen = connect_screen(&address);
    for (i, event) in ["PostToolUse", "Stop"].into_iter().enumerate() {
        call(
            &mut screen,
            "hooks.messages.send",
            json!({"agent":"claude","sessionId":"external","id":format!("mikky-{i}"),"text":"Prends aussi ce message"}),
        );
        let payload =
            json!({"hook_event_name":event,"session_id":"external","stop_hook_active":false});
        let start = Instant::now();
        let out = relay_with(&endpoint, &payload, &[event])
            .wait_with_output()
            .unwrap();
        assert!(start.elapsed() < Duration::from_secs(2));
        assert!(out.status.success());
        let printed: Value = serde_json::from_slice(&out.stdout).unwrap();
        if event == "Stop" {
            assert_eq!(printed["decision"], "block");
        } else {
            assert_eq!(printed["hookSpecificOutput"]["hookEventName"], event);
        }
        let messages = call(&mut screen, "hooks.messages.list", json!({}));
        assert!(
            messages
                .as_array()
                .unwrap()
                .iter()
                .all(|m| m["state"] == "delivered")
        );
        assert!(
            relay_with(&endpoint, &payload, &[event])
                .wait_with_output()
                .unwrap()
                .stdout
                .is_empty()
        );
    }
    call(
        &mut screen,
        "hooks.messages.send",
        json!({"agent":"claude","sessionId":"external","id":"mikky-pending","text":"Encore"}),
    );
    for (args, payload) in [
        (
            vec!["Stop"],
            json!({"session_id":"external","hook_event_name":"Stop","stop_hook_active":true}),
        ),
        (
            vec!["--agent", "codex", "Stop"],
            json!({"session_id":"external","hook_event_name":"Stop"}),
        ),
    ] {
        assert!(
            relay_with(&endpoint, &payload, &args)
                .wait_with_output()
                .unwrap()
                .stdout
                .is_empty()
        );
    }
    let messages = call(&mut screen, "hooks.messages.list", json!({}));
    assert_eq!(
        messages.as_array().unwrap().last().unwrap()["state"],
        "waitingForTool"
    );
    drop(daemon.stdin.take());
    daemon.wait().unwrap();
    let out = relay_with(
        &endpoint,
        &json!({"session_id":"external","hook_event_name":"Stop"}),
        &["Stop"],
    )
    .wait_with_output()
    .unwrap();
    assert!(out.stdout.is_empty());
    assert!(out.status.success());
}

#[test]
fn a_connected_but_unresponsive_daemon_cannot_hold_claude() {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let mut ws = tungstenite::accept(stream).unwrap();
        let _ = ws.read();
        std::thread::sleep(Duration::from_secs(2));
    });
    let start = Instant::now();
    let endpoint = json!({"port":port,"token":"isolated-test"}).to_string();
    let out = relay_with(
        &endpoint,
        &json!({"session_id":"external","hook_event_name":"Stop"}),
        &["Stop"],
    )
    .wait_with_output()
    .unwrap();
    assert!(start.elapsed() < Duration::from_millis(1500));
    assert!(out.stdout.is_empty());
    assert!(out.status.success());
    server.join().unwrap();
}
