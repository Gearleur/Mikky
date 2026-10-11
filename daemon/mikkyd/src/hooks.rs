//! Claude Code's hooks (2026-10-04): a session started in a terminal or in
//! VS Code asks its permissions to Mikky through `mikky-hook`, which calls
//! `hook.event` here with the hook's JSON. The screens see the request
//! (`hooks.list`, notification `hooks.changed`) and answer it
//! (`hooks.answer`).
//!
//! Claude's questions (2026-10-08): Claude Code 2.1.85 and later sends its
//! `AskUserQuestion` tool to a `PreToolUse` hook (matcher
//! `AskUserQuestion`, `mikky-hook --ask`). It is listed with `kind:
//! "question"` and its questions; the screen answers with `answers` (by
//! question text: a label or free text, a list of labels for a multiple
//! choice), and the relay gives them to Claude as the tool's input. The
//! `PermissionRequest` Claude may also send for that tool makes no card.
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

use std::collections::{HashMap, VecDeque};
use std::future::Future;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::time::Duration;

use serde_json::{Map, Value, json};
use tokio::sync::{broadcast, oneshot};

/// How long a permission stays on the screens; the hook gives up a little
/// later (110 s) and Claude's own timeout is 120 s (`claude_settings.rs`).
const WAIT: Duration = Duration::from_secs(105);

/// A question: the relay waits 125 s, Claude 130 s.
const QUESTION_WAIT: Duration = Duration::from_secs(120);

/// Sessions whose origin is kept (the oldest go first).
const ORIGINS: usize = 256;

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
    pending: Mutex<Vec<Pending>>,
    origins: Mutex<(HashMap<String, Value>, VecDeque<String>)>,
    next: AtomicU64,
    screens: AtomicUsize,
    pub changes: broadcast::Sender<()>,
}

impl Default for Hooks {
    fn default() -> Self {
        Self {
            pending: Mutex::new(Vec::new()),
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
    /// or none (left to the terminal). A question: `answers`, or none (the
    /// terminal). False if it is gone, or if the answers do not fit its
    /// questions (it then stays).
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
                    Some(a) if fits(&pending[i].questions, a) => Some(a.clone()),
                    Some(_) => return false,
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
        let asks = event == "PreToolUse" && tool == "AskUserQuestion";
        if event != "PermissionRequest" && !asks {
            // The session moved on: whatever it asked was answered there.
            self.drop_session(&session);
            return none;
        }
        if session.is_empty()
            // Asked by the PreToolUse hook already (or left to the terminal).
            || (!asks && tool == "AskUserQuestion")
            || own(&session)
            || self.screens.load(Ordering::Relaxed) == 0
        {
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
        self.pending.lock().unwrap().push(Pending {
            id,
            session,
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
        let reply = tokio::select! {
            answer = rx => answer.ok().flatten(),
            _ = tokio::time::sleep(if asks { QUESTION_WAIT } else { WAIT }) => None,
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
            if let Some(s) = p.answer.take() {
                let _ = s.send(None);
            }
        }
        let _ = self.changes.send(());
    }
}

/// The questions of an `AskUserQuestion` input, as the screens get them:
/// `question`, `header`, `options` (`label`, `description`),
/// `multiSelect`. None if it is not a form of 1 to 4 questions, each with
/// a text and labelled options (Claude asks in its terminal then).
fn questions_of(input: &Value) -> Option<Value> {
    let items = input["questions"].as_array()?;
    if items.is_empty() || items.len() > 4 {
        return None;
    }
    let mut out = Vec::new();
    for q in items {
        let text = q["question"].as_str().filter(|t| !t.trim().is_empty())?;
        let mut options = Vec::new();
        for o in q["options"].as_array()? {
            let label = o["label"].as_str().filter(|l| !l.is_empty())?;
            options.push(json!({
                "label": label,
                "description": o["description"].as_str().unwrap_or_default(),
            }));
        }
        if options.is_empty() {
            return None;
        }
        out.push(json!({
            "question": text,
            "header": q["header"].as_str().unwrap_or_default(),
            "options": options,
            "multiSelect": q["multiSelect"].as_bool().unwrap_or(false),
        }));
    }
    // Claude keys its answers by question text: two alike cannot be told
    // apart.
    let mut texts: Vec<_> = out.iter().map(|q| &q["question"]).collect();
    texts.sort_by_key(|t| t.as_str());
    texts.dedup();
    (texts.len() == out.len()).then_some(Value::Array(out))
}

/// True when `answers` answers each question once, by its text: free text
/// or a label (a non-empty string), or for a multiple choice a non-empty
/// list of distinct labels. Nothing else.
fn fits(questions: &Value, answers: &Value) -> bool {
    let (Some(questions), Some(answers)) = (questions.as_array(), answers.as_object()) else {
        return false;
    };
    if questions.is_empty() || questions.len() != answers.len() {
        return false;
    }
    questions.iter().all(|q| {
        let Some(text) = q["question"].as_str() else {
            return false;
        };
        let labels: Vec<&str> = q["options"]
            .as_array()
            .map(|o| o.iter().filter_map(|o| o["label"].as_str()).collect())
            .unwrap_or_default();
        match answers.get(text) {
            Some(Value::String(s)) => !s.trim().is_empty(),
            Some(Value::Array(picks)) if q["multiSelect"] == true => {
                let picks: Vec<&str> = picks.iter().filter_map(Value::as_str).collect();
                let mut seen = picks.clone();
                seen.sort_unstable();
                seen.dedup();
                !picks.is_empty()
                    && seen.len() == picks.len()
                    && picks.len() == answers[text].as_array().map(Vec::len).unwrap_or_default()
                    && picks.iter().all(|p| labels.contains(p))
            }
            _ => false,
        }
    })
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

    /// Hooks with a screen there, and what they say when their list changes.
    fn with_screen() -> (Arc<Hooks>, broadcast::Receiver<()>) {
        let hooks = Arc::new(Hooks::default());
        hooks.screen_joined();
        let changes = hooks.changes.subscribe();
        (hooks, changes)
    }

    /// [event] sent to [hooks]: the call ends with what the hook prints.
    fn waiting(hooks: &Arc<Hooks>, event: Value) -> tokio::task::JoinHandle<Value> {
        let h = hooks.clone();
        tokio::spawn(async move { h.event(&event, |_| false, std::future::pending()).await })
    }

    fn ask(session: &str, command: &str) -> Value {
        json!({
            "hook_event_name": "PermissionRequest",
            "session_id": session,
            "cwd": "C:/p",
            "tool_name": "Bash",
            "tool_input": {"command": command},
        })
    }

    /// Claude's AskUserQuestion, as its PreToolUse hook sends it.
    fn question(session: &str) -> Value {
        json!({
            "hook_event_name": "PreToolUse",
            "session_id": session,
            "cwd": "C:/p",
            "tool_name": "AskUserQuestion",
            "tool_input": {"questions": [
                {"question": "Quelle base ?", "header": "Base", "multiSelect": false, "options": [
                    {"label": "SQLite", "description": "Un fichier"},
                    {"label": "Postgres", "description": "Un serveur"},
                ]},
                {"question": "Quels tests ?", "header": "Tests", "multiSelect": true, "options": [
                    {"label": "Unitaires", "description": ""},
                    {"label": "Bout en bout", "description": ""},
                ]},
            ]},
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
        let r = hooks
            .event(&question("s"), |_| false, std::future::pending())
            .await;
        assert_eq!(r, json!({"decision": null}));
    }

    #[tokio::test]
    async fn own_sessions_and_question_permissions_go_their_way() {
        let hooks = Hooks::default();
        hooks.screen_joined();
        let r = hooks
            .event(&ask("mine", "ls"), |s| s == "mine", std::future::pending())
            .await;
        assert_eq!(r["decision"], Value::Null);
        let r = hooks
            .event(&question("mine"), |s| s == "mine", std::future::pending())
            .await;
        assert_eq!(r["decision"], Value::Null);
        // The PermissionRequest Claude may send for its question: no card.
        let mut q = ask("s", "");
        q["tool_name"] = json!("AskUserQuestion");
        let r = hooks.event(&q, |_| false, std::future::pending()).await;
        assert_eq!(r["decision"], Value::Null);
        // A form Mikky cannot show: the terminal.
        let mut odd = question("s");
        odd["tool_input"] = json!({"questions": []});
        let r = hooks.event(&odd, |_| false, std::future::pending()).await;
        assert_eq!(r["decision"], Value::Null);
        assert_eq!(hooks.list(), json!([]));
    }

    #[tokio::test]
    async fn a_screen_answers() {
        let (hooks, mut changes) = with_screen();
        let call = waiting(&hooks, ask("s", "cargo   test"));
        changes.recv().await.unwrap();
        let list = hooks.list();
        assert_eq!(list[0]["kind"], "permission");
        assert_eq!(list[0]["title"], "Bash cargo test");
        assert_eq!(list[0]["command"], "cargo   test");
        let id = list[0]["id"].as_u64().unwrap();
        // Answers are for questions only: a permission ignores them.
        assert!(hooks.answer(id, Some("allow"), Some(&json!({"x": "y"}))));
        assert_eq!(call.await.unwrap(), json!({"decision": "allow"}));
        assert_eq!(hooks.list(), json!([]));
        assert!(!hooks.answer(id, Some("deny"), None));
    }

    #[tokio::test]
    async fn a_screen_answers_a_question() {
        let (hooks, mut changes) = with_screen();
        let call = waiting(&hooks, question("s"));
        changes.recv().await.unwrap();
        let list = hooks.list();
        assert_eq!(list[0]["kind"], "question");
        assert_eq!(list[0]["title"], "Quelle base ?");
        assert_eq!(list[0]["questions"][0]["header"], "Base");
        assert_eq!(list[0]["questions"][1]["multiSelect"], true);
        assert_eq!(
            list[0]["questions"][0]["options"][1],
            json!({"label": "Postgres", "description": "Un serveur"})
        );
        let id = list[0]["id"].as_u64().unwrap();
        // Answers that do not fit: refused, the question stays.
        for wrong in [
            json!({"Quelle base ?": "SQLite"}),
            json!({"Quelle base ?": ["SQLite"], "Quels tests ?": ["Unitaires"]}),
            json!({"Quelle base ?": "SQLite", "Quels tests ?": ["Autre"]}),
            json!({"Quelle base ?": " ", "Quels tests ?": ["Unitaires"]}),
            json!({"Quelle base ?": "SQLite", "Quels tests ?": []}),
        ] {
            assert!(!hooks.answer(id, None, Some(&wrong)), "{wrong}");
        }
        assert_eq!(hooks.list().as_array().unwrap().len(), 1);
        // A label, free text, several labels.
        let answers = json!({"Quelle base ?": "DuckDB, en fait", "Quels tests ?": ["Unitaires", "Bout en bout"]});
        assert!(hooks.answer(id, Some("allow"), Some(&answers)));
        assert_eq!(call.await.unwrap(), json!({"answers": answers}));
        assert_eq!(hooks.list(), json!([]));
    }

    #[tokio::test]
    async fn a_question_left_to_the_terminal() {
        let (hooks, mut changes) = with_screen();
        let call = waiting(&hooks, question("s"));
        changes.recv().await.unwrap();
        let id = hooks.list()[0]["id"].as_u64().unwrap();
        // « Répondre dans le terminal », or an answer meant for a permission.
        assert!(hooks.answer(id, Some("allow"), None));
        assert_eq!(call.await.unwrap(), json!({"decision": null}));
    }

    #[tokio::test]
    async fn answered_in_the_terminal_or_gone() {
        let (hooks, mut changes) = with_screen();
        let call = waiting(&hooks, ask("s", "ls"));
        changes.recv().await.unwrap();
        // The session goes on: answered in its terminal.
        let next = json!({"hook_event_name": "PostToolUse", "session_id": "s"});
        hooks.event(&next, |_| false, std::future::pending()).await;
        assert_eq!(call.await.unwrap()["decision"], Value::Null);
        assert_eq!(hooks.list(), json!([]));

        // The same for a question.
        let call = waiting(&hooks, question("q"));
        while hooks.list() == json!([]) {
            changes.recv().await.unwrap();
        }
        let next = json!({"hook_event_name": "UserPromptSubmit", "session_id": "q"});
        hooks.event(&next, |_| false, std::future::pending()).await;
        assert_eq!(call.await.unwrap(), json!({"decision": null}));

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

    #[tokio::test]
    async fn every_event_tells_where_the_session_runs() {
        let hooks = Hooks::default();
        assert_eq!(hooks.origin("s"), Value::Null);
        let first = json!({
            "hook_event_name": "UserPromptSubmit",
            "session_id": "s",
            "cwd": "C:/p",
            "mikky_agent": "claude",
            "term_program": "vscode",
            "vscode_pid": "4242",
            "window_pid": 4242,
            "window_handle": 132_456,
            "window_exe": "Code.exe",
        });
        hooks.event(&first, |_| false, std::future::pending()).await;
        // A later event without the window keeps it.
        let next = json!({"hook_event_name": "Stop", "session_id": "s", "cwd": "C:/q"});
        hooks.event(&next, |_| false, std::future::pending()).await;
        assert_eq!(
            hooks.origin("s"),
            json!({
                "cwd": "C:/q",
                "agent": "claude",
                "termProgram": "vscode",
                "vscodePid": "4242",
                "windowPid": 4242,
                "windowHandle": 132_456,
                "windowExe": "Code.exe",
            })
        );
        // Bounded: the oldest sessions go.
        for i in 0..ORIGINS {
            let e = json!({"hook_event_name": "Stop", "session_id": format!("x{i}"), "cwd": "C:/"});
            hooks.event(&e, |_| false, std::future::pending()).await;
        }
        assert_eq!(hooks.origin("s"), Value::Null);
        assert_eq!(hooks.origin("x1")["cwd"], "C:/");
    }

    #[test]
    fn questions_are_kept_only_when_mikky_can_show_them() {
        let q = questions_of(&question("s")["tool_input"]).unwrap();
        assert_eq!(q.as_array().unwrap().len(), 2);
        assert!(questions_of(&json!({})).is_none());
        assert!(
            questions_of(&json!({"questions": [{"question": "A ?", "options": []}]})).is_none()
        );
        assert!(
            questions_of(&json!({"questions": [{"question": "", "options": [{"label": "a"}]}]}))
                .is_none()
        );
        let twice = json!({"questions": [
            {"question": "A ?", "options": [{"label": "a"}]},
            {"question": "A ?", "options": [{"label": "b"}]},
        ]});
        assert!(questions_of(&twice).is_none());
    }
}
