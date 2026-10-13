//! `mikky-hook`: the command Claude Code runs on each hook event (written
//! in `~/.claude/settings.json` by `mikkyd`, see `claude_settings.rs`).
//!
//! Reads the hook's JSON on stdin and hands it to `mikkyd` (`hook.event`),
//! found like the app finds it: port and token in the Windows credential
//! store, WebSocket on 127.0.0.1 with the token. Only `PermissionRequest`
//! waits for an answer, to print Claude's decision, or for Claude's
//! questions (`AskUserQuestion`) the answers as the tool's input. Claude
//! calls it while it shows the request itself (2026-10-13): whoever answers
//! first, there or in Mikky, wins, and nobody waits on the other.
//!
//! Each event also says where the session runs: the window found among the
//! relay's parent processes (a terminal, VS Code), so that Mikky can bring
//! it forward (`origin.rs`).
//!
//! Never block Claude Code: no `mikkyd`, no connection within 300 ms, no
//! answer within the budget, anything unexpected — nothing printed, exit
//! 0, and Claude asks in its terminal as if Mikky were not installed.
//!
//! Usage: `mikky-hook [--agent codex] <EventName>` (the name is also read
//! from the JSON). `--ask` was the questions' `PreToolUse` hook until
//! 2026-10-13: it held them before Claude could show them, so it now does
//! nothing until Mikky writes the hooks again.

mod delivery;
mod origin;

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::sync::mpsc;
use std::time::Duration;

use serde_json::{Value, json};
use tungstenite::Message;
use tungstenite::client::IntoClientRequest;

const CONNECT: Duration = Duration::from_millis(300);
/// An event nobody waits on: connect and send, no more.
const FIRE_AND_FORGET: Duration = Duration::from_secs(2);
/// The injection path must stay well inside Claude's 10 s hook timeout.
const DELIVERY: Duration = Duration::from_millis(300);
/// A permission on the screens (mikkyd gives up at 105 s; Claude's own
/// timeout for this hook is 120 s).
const DECISION: Duration = Duration::from_secs(110);
/// Longest stdin read; longest string forwarded (Mikky shows far less).
const MAX_INPUT: u64 = 4 << 20;
const MAX_FIELD: usize = 2000;
/// Big and never shown.
const DROPPED: &[&str] = &["tool_response", "transcript_path"];

/// One hook call, as read.
struct Event {
    payload: Value,
    name: String,
    /// Claude's question (`AskUserQuestion`), whose input is kept whole.
    question: Option<Value>,
}

fn main() {
    let Some(event) = read_event() else {
        std::process::exit(0)
    };
    let agent = event.payload["mikky_agent"]
        .as_str()
        .unwrap_or_default()
        .to_owned();
    let session = event.payload["session_id"]
        .as_str()
        .unwrap_or_default()
        .to_owned();
    let injects = agent == "claude" && matches!(event.name.as_str(), "PostToolUse" | "Stop");
    let budget = if event.name == "PermissionRequest" {
        DECISION
    } else if injects {
        DELIVERY
    } else {
        FIRE_AND_FORGET
    };
    let waits = budget != FIRE_AND_FORGET;
    // Every blocking call in a worker: past the budget, we just leave.
    let (tx, rx) = mpsc::channel();
    let payload = event.payload;
    std::thread::spawn(move || {
        let _ = tx.send(talk(payload, waits, budget));
    });
    let result = rx.recv_timeout(budget).ok().flatten();
    let out = match &result {
        Some(result) if injects => delivery::output(&event.name, &agent, &result["delivery"]),
        Some(result) => match &event.question {
            Some(input) => answers_json(input, &result["answers"]),
            None => result["decision"].as_str().and_then(decision_json),
        },
        _ => None,
    };
    if let Some(out) = out {
        let mut stdout = std::io::stdout();
        if writeln!(stdout, "{out}").is_ok()
            && stdout.flush().is_ok()
            && injects
            && let Some(token) = result
                .as_ref()
                .and_then(|r| r["delivery"]["delivery"].as_str())
                .map(str::to_owned)
        {
            let (tx, rx) = mpsc::channel();
            std::thread::spawn(move || {
                let _ = tx.send(talk_call(
                    "hooks.messages.ack",
                    json!({"sessionId":session,"delivery":token}),
                    true,
                    DELIVERY,
                ));
            });
            let _ = rx.recv_timeout(DELIVERY);
        }
    }
    std::process::exit(0);
}

/// Claude Code's PermissionRequest output (https://code.claude.com/docs/en/hooks).
/// Anything else prints nothing: silence is the safe answer.
fn decision_json(decision: &str) -> Option<String> {
    let decision = match decision {
        "allow" => json!({"behavior": "allow"}),
        "deny" => json!({"behavior": "deny", "message": "Refusé depuis Mikky"}),
        _ => return None,
    };
    Some(
        json!({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}})
            .to_string(),
    )
}

/// The answers to Claude's questions, as its PermissionRequest output: the
/// tool is allowed with its own input plus `answers` (by question text: a
/// string, or a list of labels for a multiple choice; see
/// https://code.claude.com/docs/en/agent-sdk/user-input). Answers that do
/// not answer each question print nothing: Claude's own question stays.
fn answers_json(input: &Value, answers: &Value) -> Option<String> {
    let questions = input["questions"].as_array()?;
    let answers = answers.as_object()?;
    if questions.is_empty() || questions.len() != answers.len() {
        return None;
    }
    let answered = |q: &Value| match answers.get(q["question"].as_str()?)? {
        Value::String(s) => Some(!s.trim().is_empty()),
        Value::Array(picks) => Some(!picks.is_empty() && picks.iter().all(Value::is_string)),
        _ => None,
    };
    if !questions.iter().all(|q| answered(q) == Some(true)) {
        return None;
    }
    let mut input = input.as_object()?.clone();
    input.insert("answers".into(), Value::Object(answers.clone()));
    Some(
        json!({"hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": {"behavior": "allow", "updatedInput": input},
        }})
        .to_string(),
    )
}

fn read_event() -> Option<Event> {
    let mut raw = Vec::new();
    std::io::stdin()
        .take(MAX_INPUT)
        .read_to_end(&mut raw)
        .ok()?;
    let raw = raw.strip_prefix(&[0xEF, 0xBB, 0xBF][..]).unwrap_or(&raw);
    let mut payload: Value = serde_json::from_slice(raw).ok()?;
    let map = payload.as_object_mut()?;
    // `mikky-hook [--agent codex] [--ask] <EventName>`: no agent is Claude
    // Code.
    let (mut agent, mut ask, mut arg_event) = (String::from("claude"), false, None);
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if arg == "--agent" {
            agent = args.next().unwrap_or(agent);
        } else if arg == "--ask" {
            ask = true;
        } else if arg_event.is_none() {
            arg_event = Some(arg);
        }
    }
    let event = map
        .get("hook_event_name")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .or(arg_event)?;
    // The old question hook: Claude asks itself (see the top).
    if ask {
        return None;
    }
    let question = (event == "PermissionRequest"
        && map.get("tool_name").and_then(Value::as_str) == Some("AskUserQuestion"))
    .then(|| map.get("tool_input").filter(|v| v.is_object()).cloned())
    .flatten();
    map.insert("hook_event_name".into(), json!(event));
    map.insert("mikky_agent".into(), json!(agent));
    for field in DROPPED {
        map.remove(*field);
    }
    if map
        .get("cwd")
        .and_then(Value::as_str)
        .is_none_or(str::is_empty)
        && let Ok(cwd) = std::env::current_dir()
    {
        map.insert("cwd".into(), json!(cwd.to_string_lossy()));
    }
    // Which terminal: context for the screens, never a filter.
    for (key, var) in [
        ("term_program", "TERM_PROGRAM"),
        ("wt_session", "WT_SESSION"),
        ("vscode_pid", "VSCODE_PID"),
        // `cli` in a terminal, `claude-vscode`, `claude-desktop` (Claude's
        // app: `mikkyd` never holds its requests).
        ("entrypoint", "CLAUDE_CODE_ENTRYPOINT"),
    ] {
        if let Ok(v) = std::env::var(var) {
            map.insert(key.into(), json!(v));
        }
    }
    if let Some(w) = origin::window() {
        map.insert("window_pid".into(), json!(w.pid));
        map.insert("window_handle".into(), json!(w.handle));
        map.insert("window_exe".into(), json!(w.exe));
    }
    shorten(&mut payload);
    // A question goes whole: its texts are the keys of its answers.
    if let (Some(input), Some(map)) = (&question, payload.as_object_mut()) {
        map.insert("tool_input".into(), input.clone());
    }
    Some(Event {
        payload,
        name: event,
        question,
    })
}

/// Caps every string: a Write can carry a whole file.
fn shorten(value: &mut Value) {
    match value {
        Value::String(s) if s.len() > MAX_FIELD => {
            let mut end = MAX_FIELD;
            while !s.is_char_boundary(end) {
                end -= 1;
            }
            s.truncate(end);
            s.push('…');
        }
        Value::Array(items) => items.iter_mut().for_each(shorten),
        Value::Object(map) => map.values_mut().for_each(shorten),
        _ => {}
    }
}

/// Sends the event; for a permission or a question, waits for `mikkyd`'s
/// result (`{"decision"}` or `{"answers"}`).
fn talk(payload: Value, waits: bool, budget: Duration) -> Option<Value> {
    talk_call("hook.event", json!({"payload":payload}), waits, budget)
}

fn talk_call(method: &str, params: Value, waits: bool, budget: Duration) -> Option<Value> {
    let (port, token) = endpoint()?;
    let stream =
        TcpStream::connect_timeout(&SocketAddr::from(([127, 0, 0, 1], port)), CONNECT).ok()?;
    stream.set_write_timeout(Some(FIRE_AND_FORGET)).ok()?;
    stream
        .set_read_timeout(Some(if waits { budget } else { FIRE_AND_FORGET }))
        .ok()?;
    let mut request = format!("ws://127.0.0.1:{port}/")
        .into_client_request()
        .ok()?;
    request
        .headers_mut()
        .insert("authorization", format!("Bearer {token}").parse().ok()?);
    let (mut ws, _) = tungstenite::client(request, stream).ok()?;
    let call = json!({"jsonrpc": "2.0", "id": 1, "method": method, "params": params});
    ws.send(Message::text(call.to_string())).ok()?;
    if !waits {
        // Let mikkyd read it before the connection goes.
        let _ = ws.read();
        let _ = ws.close(None);
        return None;
    }
    loop {
        let Message::Text(text) = ws.read().ok()? else {
            continue;
        };
        let answer: Value = serde_json::from_str(&text).ok()?;
        if answer["id"] == 1 {
            let _ = ws.close(None);
            return Some(answer["result"].clone());
        }
    }
}

/// Port and token of `mikkyd`: `MIKKY_HOOK_ENDPOINT` (tests: what
/// `mikkyd --stdout-endpoint` prints), else this session's, from the
/// credential store.
fn endpoint() -> Option<(u16, String)> {
    let parse = |bytes: &[u8]| -> Option<(u16, String)> {
        let v: Value = serde_json::from_slice(bytes).ok()?;
        Some((
            u16::try_from(v["port"].as_u64()?).ok()?,
            v["token"].as_str()?.to_owned(),
        ))
    };
    match std::env::var("MIKKY_HOOK_ENDPOINT") {
        Ok(e) => parse(e.as_bytes()),
        Err(_) => parse(&stored_endpoint()?),
    }
}

/// Written by `endpoint.rs` for this Windows session.
#[cfg(windows)]
fn stored_endpoint() -> Option<Vec<u8>> {
    use windows_sys::Win32::Security::Credentials::{
        CRED_TYPE_GENERIC, CREDENTIALW, CredFree, CredReadW,
    };
    let target: Vec<u16> = "Mikky/mikkyd"
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();
    let mut cred: *mut CREDENTIALW = std::ptr::null_mut();
    if unsafe { CredReadW(target.as_ptr(), CRED_TYPE_GENERIC, 0, &mut cred) } == 0 || cred.is_null()
    {
        return None;
    }
    let blob = unsafe {
        let c = &*cred;
        std::slice::from_raw_parts(c.CredentialBlob, c.CredentialBlobSize as usize).to_vec()
    };
    unsafe { CredFree(cred.cast()) };
    Some(blob)
}

/// Off Windows, not yet: `mikkyd` publishes no endpoint there (R2).
#[cfg(not(windows))]
fn stored_endpoint() -> Option<Vec<u8>> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_known_decisions_print() {
        assert_eq!(
            decision_json("allow").unwrap(),
            r#"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#
        );
        assert!(decision_json("deny").unwrap().contains("\"deny\""));
        assert!(decision_json("").is_none());
        assert!(decision_json("always").is_none());
    }

    #[test]
    fn answers_go_back_as_the_tool_input() {
        let input = json!({"questions": [
            {"question": "Quelle base ?", "header": "Base", "multiSelect": false,
             "options": [{"label": "SQLite", "description": ""}, {"label": "Postgres", "description": ""}]},
            {"question": "Quels tests ?", "header": "Tests", "multiSelect": true,
             "options": [{"label": "Unitaires", "description": ""}, {"label": "Bout en bout", "description": ""}]},
        ], "metadata": {"source": "x"}});
        let answers =
            json!({"Quelle base ?": "SQLite", "Quels tests ?": ["Unitaires", "Bout en bout"]});
        let out: Value = serde_json::from_str(&answers_json(&input, &answers).unwrap()).unwrap();
        let o = &out["hookSpecificOutput"];
        assert_eq!(o["hookEventName"], "PermissionRequest");
        assert_eq!(o["decision"]["behavior"], "allow");
        let updated = &o["decision"]["updatedInput"];
        assert_eq!(updated["questions"], input["questions"]);
        assert_eq!(updated["metadata"], input["metadata"]);
        assert_eq!(updated["answers"], answers);
        // Nothing, or not every question: silence.
        for wrong in [
            Value::Null,
            json!({}),
            json!({"Quelle base ?": "SQLite"}),
            json!({"Quelle base ?": "", "Quels tests ?": ["Unitaires"]}),
            json!({"Quelle base ?": "SQLite", "Quels tests ?": []}),
            json!({"Quelle base ?": "SQLite", "Autre ?": "x"}),
            json!({"Quelle base ?": 3, "Quels tests ?": "x"}),
        ] {
            assert!(answers_json(&input, &wrong).is_none(), "{wrong}");
        }
        assert!(answers_json(&json!({}), &answers).is_none());
    }

    #[test]
    fn long_strings_are_cut_on_a_char() {
        let mut v = json!({"a": "é".repeat(3000), "b": ["x".repeat(5000)]});
        shorten(&mut v);
        assert!(v["a"].as_str().unwrap().len() <= MAX_FIELD + 3);
        assert!(v["b"][0].as_str().unwrap().ends_with('…'));
    }
}
