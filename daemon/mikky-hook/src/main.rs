//! `mikky-hook`: the command Claude Code runs on each hook event (written
//! in `~/.claude/settings.json` by `mikkyd`, see `claude_settings.rs`).
//!
//! Reads the hook's JSON on stdin and hands it to `mikkyd` (`hook.event`),
//! found like the app finds it: port and token in the Windows credential
//! store, WebSocket on 127.0.0.1 with the token. Only `PermissionRequest`
//! waits for an answer, to print Claude's decision; and `--ask`, Claude's
//! questions (`AskUserQuestion` in `PreToolUse`), to print the answers as
//! the tool's input.
//!
//! Each event also says where the session runs: the window found among the
//! relay's parent processes (a terminal, VS Code), so that Mikky can bring
//! it forward (`origin.rs`).
//!
//! Never block Claude Code: no `mikkyd`, no connection within 300 ms, no
//! answer within the budget, anything unexpected — nothing printed, exit
//! 0, and Claude asks in its terminal as if Mikky were not installed.
//!
//! Usage: `mikky-hook [--agent codex] [--ask] <EventName>` (the name is
//! also read from the JSON).

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
/// A permission on the screens (mikkyd gives up at 105 s; Claude's own
/// timeout for this hook is 120 s).
const DECISION: Duration = Duration::from_secs(110);
/// A question (mikkyd gives up at 120 s; Claude's timeout is 130 s).
const ANSWERS: Duration = Duration::from_secs(125);
/// Longest stdin read; longest string forwarded (Mikky shows far less).
const MAX_INPUT: u64 = 4 << 20;
const MAX_FIELD: usize = 2000;
/// Big and never shown.
const DROPPED: &[&str] = &["tool_response", "transcript_path"];

/// One hook call, as read.
struct Event {
    payload: Value,
    name: String,
    /// `--ask`: Claude's question, whose input is kept whole here.
    question: Option<Value>,
}

fn main() {
    let Some(event) = read_event() else {
        std::process::exit(0)
    };
    let budget = if event.question.is_some() {
        ANSWERS
    } else if event.name == "PermissionRequest" {
        DECISION
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
    let out = match rx.recv_timeout(budget) {
        Ok(Some(result)) => match &event.question {
            Some(input) => answers_json(input, &result["answers"]),
            None => result["decision"].as_str().and_then(decision_json),
        },
        _ => None,
    };
    if let Some(out) = out {
        let mut stdout = std::io::stdout();
        let _ = writeln!(stdout, "{out}");
        let _ = stdout.flush();
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

/// The answers to Claude's questions, as its PreToolUse output: the tool
/// runs with its own input plus `answers` (by question text: a string, or
/// a list of labels for a multiple choice; see
/// https://code.claude.com/docs/en/agent-sdk/user-input). Answers that do
/// not answer each question print nothing: Claude asks in its terminal.
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
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": input,
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
    // The question hook only answers Claude's question tool.
    let question = if ask {
        if event != "PreToolUse"
            || map.get("tool_name").and_then(Value::as_str) != Some("AskUserQuestion")
        {
            return None;
        }
        Some(map.get("tool_input").filter(|v| v.is_object())?.clone())
    } else {
        None
    };
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
    let call =
        json!({"jsonrpc": "2.0", "id": 1, "method": "hook.event", "params": {"payload": payload}});
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
        let answers = json!({"Quelle base ?": "SQLite", "Quels tests ?": ["Unitaires", "Bout en bout"]});
        let out: Value = serde_json::from_str(&answers_json(&input, &answers).unwrap()).unwrap();
        let o = &out["hookSpecificOutput"];
        assert_eq!(o["hookEventName"], "PreToolUse");
        assert_eq!(o["permissionDecision"], "allow");
        assert_eq!(o["updatedInput"]["questions"], input["questions"]);
        assert_eq!(o["updatedInput"]["metadata"], input["metadata"]);
        assert_eq!(o["updatedInput"]["answers"], answers);
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
