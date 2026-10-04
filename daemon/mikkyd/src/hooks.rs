//! Claude Code's hooks (2026-10-04): a session started in a terminal or in
//! VS Code asks its permissions to Mikky through `mikky-hook`, which calls
//! `hook.event` here with the hook's JSON. The screens see the request
//! (`hooks.list`, notification `hooks.changed`) and answer it
//! (`hooks.answer`).
//!
//! Never block Claude Code: no screen connected, a session `mikkyd` runs
//! itself (ACP asks it already), a question form, or no answer in time,
//! and the hook gets no decision at once: Claude asks in its terminal as if
//! Mikky were not there. Any later event of the session (the user answered
//! in the terminal) drops its request from the screens.

use std::future::Future;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::time::Duration;

use serde_json::{Value, json};
use tokio::sync::{broadcast, oneshot};

/// How long a request stays on the screens; the hook gives up a little
/// later (110 s) and Claude's own timeout is 120 s (`claude_settings.rs`).
const WAIT: Duration = Duration::from_secs(105);

struct Pending {
    id: u64,
    session: String,
    shown: Value,
    answer: Option<oneshot::Sender<Option<String>>>,
}

pub struct Hooks {
    pending: Mutex<Vec<Pending>>,
    next: AtomicU64,
    screens: AtomicUsize,
    pub changes: broadcast::Sender<()>,
}

impl Default for Hooks {
    fn default() -> Self {
        Self {
            pending: Mutex::new(Vec::new()),
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

    /// The user's answer to request `id`: `allow`, `deny`, or none (left
    /// to the terminal). False if it is gone.
    pub fn answer(&self, id: u64, decision: Option<&str>) -> bool {
        let decision = match decision {
            Some("allow") => Some("allow".to_owned()),
            Some("deny") => Some("deny".to_owned()),
            _ => None,
        };
        let sender = {
            let mut pending = self.pending.lock().unwrap();
            let Some(i) = pending.iter().position(|p| p.id == id) else {
                return false;
            };
            pending.remove(i).answer
        };
        if let Some(s) = sender {
            let _ = s.send(decision);
        }
        let _ = self.changes.send(());
        true
    }

    /// One hook call. `own` tells if a session is one `mikkyd` runs;
    /// `closed` ends when the hook's connection goes. Returns
    /// `{"decision": "allow" | "deny" | null}`.
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
        if event != "PermissionRequest" {
            // The session moved on: whatever it asked was answered there.
            self.drop_session(&session);
            return none;
        }
        let tool = payload["tool_name"].as_str().unwrap_or_default();
        if session.is_empty()
            || tool == "AskUserQuestion"
            || own(&session)
            || self.screens.load(Ordering::Relaxed) == 0
        {
            return none;
        }
        self.drop_session(&session);
        let id = self.next.fetch_add(1, Ordering::Relaxed);
        let (tx, rx) = oneshot::channel();
        let input = &payload["tool_input"];
        let command = command_of(input);
        let shown = json!({
            "id": id,
            "sessionId": session,
            "cwd": payload["cwd"],
            "tool": tool,
            "command": command,
            "path": input.get("file_path").or_else(|| input.get("path")).or_else(|| input.get("notebook_path")).filter(|v| v.is_string()),
            "description": input["description"].as_str(),
            "title": summary(tool, command.as_deref().or_else(|| [input["file_path"].as_str(), input["path"].as_str(), input["url"].as_str(), input["pattern"].as_str()].into_iter().flatten().next())),
            "agent": payload["mikky_agent"].as_str().unwrap_or("claude"),
            "terminal": payload["term_program"],
            "at": chrono::Utc::now().to_rfc3339(),
        });
        self.pending.lock().unwrap().push(Pending {
            id,
            session,
            shown,
            answer: Some(tx),
        });
        let _ = self.changes.send(());
        let decision = tokio::select! {
            answer = rx => answer.ok().flatten(),
            _ = tokio::time::sleep(WAIT) => None,
            _ = closed => None,
        };
        // Answered, timed out or abandoned: off the screens.
        let removed = {
            let mut pending = self.pending.lock().unwrap();
            let before = pending.len();
            pending.retain(|p| p.id != id);
            before != pending.len()
        };
        if removed {
            let _ = self.changes.send(());
        }
        json!({"decision": decision})
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
            if let Some(s) = p.answer.take() {
                let _ = s.send(None);
            }
        }
        let _ = self.changes.send(());
    }
}

/// One line for the request: the command, the file, or the tool.
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
mod tests {
    use super::*;
    use std::sync::Arc;

    fn ask(session: &str, command: &str) -> Value {
        json!({
            "hook_event_name": "PermissionRequest",
            "session_id": session,
            "cwd": "C:/p",
            "tool_name": "Bash",
            "tool_input": {"command": command},
        })
    }

    #[test]
    fn codex_commands_come_as_words() {
        let words = json!({"command": ["bash", "-lc", "cargo  test"]});
        assert_eq!(command_of(&words).as_deref(), Some("bash -lc cargo  test"));
        assert_eq!(
            summary("shell", command_of(&words).as_deref()),
            "shell bash -lc cargo test"
        );
        assert_eq!(command_of(&json!({"file_path": "a"})), None);
        assert_eq!(summary("Edit", None), "Edit");
    }

    #[tokio::test]
    async fn nobody_watching_never_waits() {
        let hooks = Hooks::default();
        let r = hooks
            .event(&ask("s", "ls"), |_| false, std::future::pending())
            .await;
        assert_eq!(r, json!({"decision": null}));
    }

    #[tokio::test]
    async fn own_sessions_and_questions_go_their_way() {
        let hooks = Hooks::default();
        hooks.screen_joined();
        let r = hooks
            .event(&ask("mine", "ls"), |s| s == "mine", std::future::pending())
            .await;
        assert_eq!(r["decision"], Value::Null);
        let mut q = ask("s", "");
        q["tool_name"] = json!("AskUserQuestion");
        let r = hooks.event(&q, |_| false, std::future::pending()).await;
        assert_eq!(r["decision"], Value::Null);
        assert_eq!(hooks.list(), json!([]));
    }

    #[tokio::test]
    async fn a_screen_answers() {
        let hooks = Arc::new(Hooks::default());
        hooks.screen_joined();
        let mut changes = hooks.changes.subscribe();
        let h = hooks.clone();
        let call = tokio::spawn(async move {
            h.event(&ask("s", "cargo   test"), |_| false, std::future::pending())
                .await
        });
        changes.recv().await.unwrap();
        let list = hooks.list();
        assert_eq!(list[0]["title"], "Bash cargo test");
        assert_eq!(list[0]["command"], "cargo   test");
        let id = list[0]["id"].as_u64().unwrap();
        assert!(hooks.answer(id, Some("allow")));
        assert_eq!(call.await.unwrap(), json!({"decision": "allow"}));
        assert_eq!(hooks.list(), json!([]));
        assert!(!hooks.answer(id, Some("deny")));
    }

    #[tokio::test]
    async fn answered_in_the_terminal_or_gone() {
        let hooks = Arc::new(Hooks::default());
        hooks.screen_joined();
        let mut changes = hooks.changes.subscribe();
        let h = hooks.clone();
        let call = tokio::spawn(async move {
            h.event(&ask("s", "ls"), |_| false, std::future::pending())
                .await
        });
        changes.recv().await.unwrap();
        // The session goes on: answered in its terminal.
        let next = json!({"hook_event_name": "PostToolUse", "session_id": "s"});
        hooks.event(&next, |_| false, std::future::pending()).await;
        assert_eq!(call.await.unwrap()["decision"], Value::Null);
        assert_eq!(hooks.list(), json!([]));

        // The hook's connection closed.
        let (tx, rx) = oneshot::channel::<()>();
        let h = hooks.clone();
        let call = tokio::spawn(async move {
            h.event(&ask("t", "ls"), |_| false, async {
                let _ = rx.await;
            })
            .await
        });
        changes.recv().await.unwrap();
        drop(tx);
        assert_eq!(call.await.unwrap()["decision"], Value::Null);
        assert_eq!(hooks.list(), json!([]));
    }
}
