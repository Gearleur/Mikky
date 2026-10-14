//! Claude Code's hooks (2026-10-04): a session started in a terminal or in
//! VS Code asks its permissions to Mikky through `mikky-hook`, which calls
//! `hook.event` here with the hook's JSON. The screens see the request
//! (`hooks.list`, notification `hooks.changed`) and answer it
//! (`hooks.answer`).
//!
//! Claude's questions (2026-10-13): its `AskUserQuestion` tool comes as a
//! `PermissionRequest` like any tool. It is listed with `kind: "question"`
//! and its questions; the screen answers with `answers` by question key, as
//! for an ACP form (`q1`, `q1_custom`); `mikkyd` turns them into Claude's
//! (by question text) and the relay allows the tool with them as its input.
//!
//! Claude calls that hook while it shows the request itself (tried in a
//! terminal, 2026-10-13): nobody waits on the other. Answered there, Claude
//! ends the hook (or the session moves on) and the request goes; answered
//! here first, Claude's own closes. (Until then the questions came to a
//! `PreToolUse` hook, before Claude could show them: it blocked both.)
//!
//! Never block Claude Code: no screen connected, a session `mikkyd` runs
//! itself (ACP asks it already), answers that do not fit the questions, or
//! no answer in time, and the hook gets nothing at once: Claude asks in its
//! terminal as if Mikky were not there. Any later event of the session (the
//! user answered in the terminal) drops its request from the screens.
//!
//! Every event also tells where the session runs (`hooks.origin`): the
//! window the relay found among its parent processes (a terminal, VS Code),
//! `TERM_PROGRAM`, `WT_SESSION`, `VSCODE_PID` and the folder. The screens
//! use it to bring that window forward (Ctrl + click on an agent).

pub mod messages;
pub(crate) mod questions;
mod session_request;
pub mod settings;

use std::collections::{HashMap, VecDeque};
use std::future::Future;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::time::Duration;

use serde_json::{Map, Value, json};
use tokio::sync::{broadcast, oneshot};

use questions::{by_text, fits, questions_of};

/// How long a permission stays on the screens; the hook gives up a little
/// later (110 s) and Claude's own timeout is 120 s (`claude_settings.rs`).
const WAIT: Duration = Duration::from_secs(105);

/// Sessions whose origin is kept (the oldest go first).
const ORIGINS: usize = 256;

/// Requests ended without Mikky that are kept to be told.
const SETTLED: usize = 32;

/// How a request ended without an answer from Mikky.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Settled {
    Elsewhere,
    Timeout,
}

impl Settled {
    fn word(self) -> &'static str {
        match self {
            Settled::Elsewhere => "elsewhere",
            Settled::Timeout => "timeout",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Kind {
    Permission,
    Question,
}

struct Pending {
    id: u64,
    session: String,
    kind: Kind,
    /// The questions as Claude asked them (a question only).
    questions: Value,
    shown: Value,
    /// What the hook's call returns: a permission's `decision`, a
    /// question's `answers`; None, the terminal.
    answer: Option<oneshot::Sender<Option<Value>>>,
}

pub struct Hooks {
    pub messages: messages::Messages,
    pending: Mutex<Vec<Pending>>,
    /// Requests that ended without an answer from Mikky, newest last
    /// ([`Hooks::settled`]).
    settled: Mutex<VecDeque<Value>>,
    origins: Mutex<(HashMap<String, Value>, VecDeque<String>)>,
    next: AtomicU64,
    screens: AtomicUsize,
    pub changes: broadcast::Sender<()>,
}

impl Default for Hooks {
    fn default() -> Self {
        Self {
            messages: messages::Messages::default(),
            pending: Mutex::new(Vec::new()),
            settled: Mutex::new(VecDeque::new()),
            origins: Mutex::new((HashMap::new(), VecDeque::new())),
            next: AtomicU64::new(1),
            screens: AtomicUsize::new(0),
            changes: broadcast::channel(16).0,
        }
    }
}

impl Hooks {
    /// A screen said hello; it leaves with its connection.
    pub fn screen_joined(&self) {
        self.screens.fetch_add(1, Ordering::Relaxed);
    }

    pub fn screen_left(&self) {
        let _ = self
            .screens
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |n| n.checked_sub(1));
    }

    /// The requests waiting, oldest first.
    pub fn list(&self) -> Value {
        Value::Array(
            self.pending
                .lock()
                .unwrap()
                .iter()
                .map(|p| p.shown.clone())
                .collect(),
        )
    }

    /// The requests that ended without an answer from Mikky, newest last
    /// (the last [`SETTLED`]): `{id, sessionId, how}`, `how` being
    /// `elsewhere` (answered where the session runs) or `timeout` (left to
    /// it, which asks again). The screens say so (« Répondu dans VS Code »).
    pub fn settled(&self) -> Value {
        Value::Array(self.settled.lock().unwrap().iter().cloned().collect())
    }

    fn settle(&self, id: u64, session: &str, how: Settled) {
        let mut settled = self.settled.lock().unwrap();
        settled.push_back(json!({"id": id, "sessionId": session, "how": how.word()}));
        while settled.len() > SETTLED {
            settled.pop_front();
        }
    }

    /// Where session `session` runs, as its hooks last told; null if no
    /// hook of it was seen since `mikkyd` started.
    pub fn origin(&self, session: &str) -> Value {
        self.origins
            .lock()
            .unwrap()
            .0
            .get(session)
            .cloned()
            .unwrap_or(Value::Null)
    }

    /// The user's answer to request `id`. A permission: `allow`, `deny`,
    /// or none (left to the terminal). A question: `answers` by question key
    /// (`q1`, `q1_custom`: [`by_text`]), or none (the terminal). False if it
    /// is gone, or if the answers do not fit its questions (it then
    /// stays).
    pub fn answer(&self, id: u64, decision: Option<&str>, answers: Option<&Value>) -> bool {
        let sender = {
            let mut pending = self.pending.lock().unwrap();
            let Some(i) = pending.iter().position(|p| p.id == id) else {
                return false;
            };
            let reply = match pending[i].kind {
                Kind::Permission => match decision {
                    Some("allow") => Some(json!("allow")),
                    Some("deny") => Some(json!("deny")),
                    _ => None,
                },
                Kind::Question => match answers {
                    Some(a) => {
                        let q = &pending[i].questions;
                        match by_text(q, a).filter(|t| fits(q, t)) {
                            Some(t) => Some(t),
                            None => return false,
                        }
                    }
                    None => None,
                },
            };
            pending.remove(i).answer.map(|s| (s, reply))
        };
        if let Some((s, reply)) = sender {
            let _ = s.send(reply);
        }
        let _ = self.changes.send(());
        true
    }

    /// One hook call. `own` tells if a session is one `mikkyd` runs;
    /// `closed` ends when the hook's connection goes. Returns
    /// `{"decision": "allow" | "deny" | null}`, or for a question
    /// `{"answers": {...}}`.
    pub async fn event(
        &self,
        payload: &Value,
        own: impl Fn(&str) -> bool,
        closed: impl Future<Output = ()>,
    ) -> Value {
        let none = json!({"decision": null});
        let event = payload["hook_event_name"].as_str().unwrap_or_default();
        let session = payload["session_id"]
            .as_str()
            .unwrap_or_default()
            .to_owned();
        let tool = payload["tool_name"].as_str().unwrap_or_default();
        self.remember_origin(&session, payload);
        let asks = event == "PermissionRequest" && tool == "AskUserQuestion";
        if event != "PermissionRequest" {
            // The session moved on: whatever it asked was answered there.
            self.drop_session(&session);
            if !session.is_empty()
                && !own(&session)
                && matches!(payload["mikky_agent"].as_str(), Some("claude" | "codex"))
                && (event == "PostToolUse"
                    || (event == "Stop" && payload["stop_hook_active"] != true))
            {
                return json!({"decision":null,"delivery":self.messages.offer_for(payload["mikky_agent"].as_str().unwrap(), &session)});
            }
            return none;
        }
        if session.is_empty() || own(&session) || self.screens.load(Ordering::Relaxed) == 0 {
            return none;
        }
        let input = &payload["tool_input"];
        let questions = if asks {
            match questions_of(input) {
                Some(q) => q,
                // Not a form Mikky can show: Claude asks in its terminal.
                None => return none,
            }
        } else {
            Value::Null
        };
        self.drop_session(&session);
        let id = self.next.fetch_add(1, Ordering::Relaxed);
        let (tx, rx) = oneshot::channel();
        let mut shown = json!({
            "id": id,
            "sessionId": session,
            "cwd": payload["cwd"],
            "tool": tool,
            "toolCallId": payload["tool_use_id"],
            "agent": payload["mikky_agent"].as_str().unwrap_or("claude"),
            "terminal": payload["term_program"],
            "at": chrono::Utc::now().to_rfc3339(),
        });
        if asks {
            shown["kind"] = json!("question");
            shown["title"] = questions[0]["question"].clone();
            shown["questions"] = questions.clone();
        } else {
            let command = command_of(input);
            shown["kind"] = json!("permission");
            shown["command"] = json!(command);
            shown["path"] = json!(
                input
                    .get("file_path")
                    .or_else(|| input.get("path"))
                    .or_else(|| input.get("notebook_path"))
                    .filter(|v| v.is_string())
            );
            shown["description"] = json!(input["description"].as_str());
            shown["title"] = json!(summary(
                tool,
                command.as_deref().or_else(|| [
                    input["file_path"].as_str(),
                    input["path"].as_str(),
                    input["url"].as_str(),
                    input["pattern"].as_str()
                ]
                .into_iter()
                .flatten()
                .next())
            ));
        }
        shown["event"] = session_request::event(&shown);
        self.pending.lock().unwrap().push(Pending {
            id,
            session: session.clone(),
            kind: if asks {
                Kind::Question
            } else {
                Kind::Permission
            },
            questions,
            shown,
            answer: Some(tx),
        });
        let _ = self.changes.send(());
        let (reply, gone) = tokio::select! {
            answer = rx => (answer.ok().flatten(), None),
            _ = tokio::time::sleep(WAIT) => (None, Some(Settled::Timeout)),
            // Claude ended the hook: answered where it runs.
            _ = closed => (None, Some(Settled::Elsewhere)),
        };
        // Answered, timed out or abandoned: off the screens.
        let removed = {
            let mut pending = self.pending.lock().unwrap();
            let before = pending.len();
            pending.retain(|p| p.id != id);
            before != pending.len()
        };
        if removed {
            if let Some(how) = gone {
                self.settle(id, &session, how);
            }
            let _ = self.changes.send(());
        }
        match reply {
            Some(answers) if asks => json!({"answers": answers}),
            reply => json!({"decision": reply}),
        }
    }

    /// Keeps where `session` runs: the latest of each field.
    fn remember_origin(&self, session: &str, payload: &Value) {
        if session.is_empty() {
            return;
        }
        let mut fresh = Map::new();
        for (key, field) in [
            ("cwd", "cwd"),
            ("agent", "mikky_agent"),
            ("termProgram", "term_program"),
            ("wtSession", "wt_session"),
            ("vscodePid", "vscode_pid"),
            ("windowPid", "window_pid"),
            ("windowHandle", "window_handle"),
            ("windowExe", "window_exe"),
        ] {
            let v = &payload[field];
            if v.is_string() || v.is_number() {
                fresh.insert(key.into(), v.clone());
            }
        }
        if fresh.is_empty() {
            return;
        }
        let mut guard = self.origins.lock().unwrap();
        let (map, order) = &mut *guard;
        if !map.contains_key(session) {
            order.push_back(session.to_owned());
            while order.len() > ORIGINS {
                if let Some(old) = order.pop_front() {
                    map.remove(&old);
                }
            }
        }
        let entry = map.entry(session.to_owned()).or_insert_with(|| json!({}));
        if let Some(obj) = entry.as_object_mut() {
            obj.extend(fresh);
        }
    }

    fn drop_session(&self, session: &str) {
        if session.is_empty() {
            return;
        }
        let dropped: Vec<_> = {
            let mut pending = self.pending.lock().unwrap();
            let (gone, kept): (Vec<_>, Vec<_>) =
                pending.drain(..).partition(|p| p.session == session);
            *pending = kept;
            gone
        };
        if dropped.is_empty() {
            return;
        }
        for mut p in dropped {
            // The session moved on: answered where it runs.
            self.settle(p.id, &p.session, Settled::Elsewhere);
            if let Some(s) = p.answer.take() {
                let _ = s.send(None);
            }
        }
        let _ = self.changes.send(());
    }
}

/// The command, as text: Claude gives a string, Codex may give its words.
fn command_of(input: &Value) -> Option<String> {
    match &input["command"] {
        Value::String(s) => Some(s.clone()),
        Value::Array(words) => Some(
            words
                .iter()
                .filter_map(Value::as_str)
                .collect::<Vec<_>>()
                .join(" "),
        ),
        _ => None,
    }
}

/// One line for the request: the command, the file, or the tool.
fn summary(tool: &str, text: Option<&str>) -> String {
    let one: String = text
        .unwrap_or_default()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    let short: String = one.chars().take(200).collect();
    if short.is_empty() {
        tool.to_owned()
    } else {
        format!("{tool} {short}")
    }
}

#[cfg(test)]
mod tests;
