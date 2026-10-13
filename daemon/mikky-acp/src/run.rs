//! One agent session driven through ACP: open it, prompt it, hold its permission requests
//! and questions until someone answers, cancel it. Every message is kept
//! and handed to subscribers as raw traffic.

use std::sync::{Arc, Mutex};

use serde_json::{Value, json};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::sync::watch;

use crate::connection::{Connection, Event, RpcError};

/// One message, either way, with when it passed (RFC 3339, UTC).
#[derive(Debug)]
pub struct Traffic {
    pub sequence: u64,
    #[cfg(test)]
    pub outgoing: bool,
    #[cfg(test)]
    pub message: Value,
    pub events: Vec<Value>,
}

#[derive(Debug, Clone)]
pub enum RunEvent {
    Traffic(Arc<Traffic>),
    Closed,
}

/// Where a subscriber gets the run's events, called in order right when
/// they happen (so keep it quick). False: it is gone, drop it.
pub type Sink = Box<dyn Fn(RunEvent) -> bool + Send>;

struct PermissionOption {
    id: Value,
    kind: String,
}

#[derive(Default)]
struct State {
    reader: crate::reader::Reader,
    backlog: Vec<Arc<Traffic>>,
    subscribers: Vec<Sink>,
    /// Permission requests waiting for the user, oldest first.
    asked: Vec<(Value, Vec<PermissionOption>)>,
    /// Questions (form elicitations) waiting for the user, oldest first.
    questions: Vec<Value>,
    session_id: Option<String>,
    /// Prompts sent and not answered yet: a turn is on.
    prompts: usize,
    steering: bool,
    closed: bool,
}

impl State {
    /// Keeps a message and hands it on. A request the user must answer is
    /// held first, so that no one can answer it before it is known.
    fn record(&mut self, outgoing: bool, message: &Value) {
        if let (false, Some(id), Some(method)) = (
            outgoing,
            message.get("id"),
            message.get("method").and_then(Value::as_str),
        ) {
            let params = message.get("params").unwrap_or(&Value::Null);
            if method == "session/request_permission" {
                let options = params
                    .get("options")
                    .and_then(Value::as_array)
                    .map(|o| {
                        o.iter()
                            .map(|o| PermissionOption {
                                id: o.get("optionId").cloned().unwrap_or(Value::Null),
                                kind: o
                                    .get("kind")
                                    .and_then(Value::as_str)
                                    .unwrap_or_default()
                                    .to_owned(),
                            })
                            .collect()
                    })
                    .unwrap_or_default();
                self.asked.push((id.clone(), options));
            } else if held(method, params) {
                self.questions.push(id.clone());
            }
        }
        let at = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Micros, true);
        let events = self.reader.read(message, outgoing, &at);
        let t = Arc::new(Traffic {
            sequence: self.backlog.len() as u64 + 1,
            #[cfg(test)]
            outgoing,
            #[cfg(test)]
            message: message.clone(),
            events,
        });
        self.backlog.push(t.clone());
        self.subscribers
            .retain(|sink| sink(RunEvent::Traffic(t.clone())));
    }
}

/// Requests of the agent that Mikky holds for the user (permissions,
/// questions); any other gets an error.
fn held(method: &str, params: &Value) -> bool {
    method == "session/request_permission"
        || (method == "elicitation/create"
            && params.get("mode").and_then(Value::as_str) == Some("form"))
}

#[derive(Clone)]
pub struct Run {
    conn: Connection,
    state: Arc<Mutex<State>>,
    closed: watch::Receiver<bool>,
}

impl Run {
    /// Talks ACP with the adapter on `input` / `output` (its stdout / stdin).
    pub fn start<R, W>(input: R, output: W) -> Run
    where
        R: AsyncRead + Unpin + Send + 'static,
        W: AsyncWrite + Unpin + Send + 'static,
    {
        let state = Arc::new(Mutex::new(State::default()));
        let hook = {
            let state = state.clone();
            Arc::new(move |outgoing: bool, m: &Value| state.lock().unwrap().record(outgoing, m))
        };
        let (conn, mut events) = Connection::new(input, output, hook);
        let (closed_tx, closed) = watch::channel(false);
        let run = Run {
            conn,
            state,
            closed,
        };
        let pump = run.clone();
        tokio::spawn(async move {
            while let Some(e) = events.recv().await {
                match e {
                    Event::Request { id, method, params } if !held(&method, &params) => {
                        pump.conn
                            .respond_error(id, -32601, &format!("Method not found: {method}"));
                    }
                    Event::Request { .. } => {}
                    Event::Closed => break,
                }
            }
            pump.on_closed();
            let _ = closed_tx.send(true);
        });
        run
    }

    /// Hands `sink` everything so far, then what comes (atomically: nothing
    /// missed, nothing twice), then [RunEvent::Closed].
    pub fn subscribe(&self, sink: Sink) {
        self.subscribe_after(0, sink);
    }

    /// Replay only missed messages after a transport interruption.
    pub fn subscribe_after(&self, after: u64, sink: Sink) {
        self.subscribe_page(after, usize::MAX, sink);
    }

    /// Replay a bounded page; only the final page installs the live sink.
    pub fn subscribe_page(&self, after: u64, limit: usize, sink: Sink) -> (u64, bool) {
        let mut s = self.state.lock().unwrap();
        let start = (after as usize).min(s.backlog.len());
        let end = start.saturating_add(limit).min(s.backlog.len());
        for t in &s.backlog[start..end] {
            if !sink(RunEvent::Traffic(t.clone())) {
                return (start as u64, true);
            }
        }
        if end < s.backlog.len() {
            return (end as u64, true);
        }
        if s.closed {
            sink(RunEvent::Closed);
        } else {
            s.subscribers.push(sink);
        }
        (end as u64, false)
    }

    pub fn session_id(&self) -> Option<String> {
        self.state.lock().unwrap().session_id.clone()
    }

    pub fn alive(&self) -> bool {
        !self.state.lock().unwrap().closed
    }

    /// A turn is on (a prompt waits for its answer).
    pub fn working(&self) -> bool {
        let s = self.state.lock().unwrap();
        !s.closed && (s.prompts > 0 || s.reader.detached_working())
    }

    pub async fn wait_closed(&self) {
        let mut closed = self.closed.clone();
        let _ = closed.wait_for(|c| *c).await;
    }

    /// Handshake, then a new session in `cwd`, or `resume` one (the agent
    /// replays its thread), then the permission `mode`.
    pub async fn open(
        &self,
        cwd: &str,
        resume: Option<&str>,
        mode: Option<&str>,
    ) -> Result<String, RpcError> {
        let initialized = self
            .conn
            .request(
                "initialize",
                json!({
                    "protocolVersion": 1,
                    "clientCapabilities": {
                        "fs": {"readTextFile": false, "writeTextFile": false},
                        "terminal": false,
                        // Mikky shows forms: Claude may then use its question
                        // tool (the adapter forbids it to clients without this).
                        "elicitation": {"form": {}},
                    },
                    "clientInfo": {"name": "mikky", "version": env!("CARGO_PKG_VERSION")},
                }),
            )
            .await?;
        self.state.lock().unwrap().steering = initialized["_meta"]["steering"]["supported"] == true;
        let session_id = match resume {
            None => {
                let r = self
                    .conn
                    .request("session/new", json!({"cwd": cwd, "mcpServers": []}))
                    .await?;
                r.get("sessionId")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_owned()
            }
            Some(id) => {
                self.conn
                    .request(
                        "session/load",
                        json!({"sessionId": id, "cwd": cwd, "mcpServers": []}),
                    )
                    .await?;
                id.to_owned()
            }
        };
        self.state.lock().unwrap().session_id = Some(session_id.clone());
        if let Some(mode) = mode {
            self.conn
                .request(
                    "session/set_mode",
                    json!({"sessionId": session_id, "modeId": mode}),
                )
                .await?;
        }
        Ok(session_id)
    }

    /// Any other request to the agent (set a mode, a model…).
    pub async fn request(&self, method: &str, params: Value) -> Result<Value, RpcError> {
        self.conn.request(method, params).await
    }

    /// Injects into the active turn when supported. Explicit refusal (including
    /// an idle Claude) falls back to a normal prompt. A started Codex turn must
    /// never be sent again: that adapter currently ignores idleBehavior.
    pub async fn steer(&self, text: &str) -> Result<Value, RpcError> {
        let supported = self.state.lock().unwrap().steering;
        if supported && self.working() {
            let result = self
                .conn
                .request(
                    "_session/steering",
                    json!({
                        "sessionId": self.session_id(),
                        "prompt": [{"type": "text", "text": text}],
                        "_meta": {"steering": {"idleBehavior": "promptRequired"}},
                    }),
                )
                .await;
            match result {
                Ok(r) if r["outcome"] == "injected" || r["outcome"] == "startedNewTurn" => {
                    return Ok(r);
                }
                Ok(r) if r["outcome"] == "failed" || r["outcome"] == "promptRequired" => {}
                Err(e) if matches!(e.code, -32602..=-32600) => {}
                Err(e) => return Err(e),
                Ok(_) => return Err(RpcError::new(-32603, "Unknown steering outcome")),
            }
        }
        self.prompt(text).await
    }

    /// Sends a normal prompt, queued behind any active turn by the adapter.
    /// Ends when the agent has answered it.
    pub async fn prompt(&self, text: &str) -> Result<Value, RpcError> {
        let session_id = {
            let mut s = self.state.lock().unwrap();
            s.prompts += 1;
            s.session_id.clone()
        };
        let r = self
            .conn
            .request(
                "session/prompt",
                json!({"sessionId": session_id, "prompt": [{"type": "text", "text": text}]}),
            )
            .await;
        self.state.lock().unwrap().prompts -= 1;
        r
    }

    /// Answers the oldest permission request (or `request_id`). `always`:
    /// the agent's « always allow » option when it has one. False if none.
    pub fn answer(&self, allow: bool, always: bool, request_id: Option<&Value>) -> bool {
        let asked = {
            let mut s = self.state.lock().unwrap();
            let at = match request_id {
                Some(id) => s.asked.iter().position(|(i, _)| i == id),
                None => (!s.asked.is_empty()).then_some(0),
            };
            match at {
                Some(at) => s.asked.remove(at),
                None => return false,
            }
        };
        let (id, options) = asked;
        let wanted: &[&str] = match (allow, always) {
            (true, true) => &["allow_always", "allow_once"],
            (true, false) => &["allow_once", "allow_always"],
            (false, _) => &["reject_once", "reject_always"],
        };
        let pick = wanted
            .iter()
            .find_map(|kind| options.iter().find(|o| o.kind == *kind));
        self.conn.respond(
            id,
            match pick {
                Some(o) => json!({"outcome": {"outcome": "selected", "optionId": o.id}}),
                None => json!({"outcome": {"outcome": "cancelled"}}),
            },
        );
        true
    }

    /// Answers the oldest question: `answers` by question key, or `None`
    /// when the user declined. False if none is pending.
    pub fn answer_question(&self, answers: Option<Value>) -> bool {
        let id = {
            let mut s = self.state.lock().unwrap();
            if s.questions.is_empty() {
                return false;
            }
            s.questions.remove(0)
        };
        self.conn.respond(
            id,
            match answers {
                Some(content) => json!({"action": "accept", "content": content}),
                None => json!({"action": "decline"}),
            },
        );
        true
    }

    /// Stops the current turn; the session stays open for the next message.
    pub fn cancel(&self) {
        let session_id = self.session_id();
        self.conn
            .notify("session/cancel", json!({"sessionId": session_id}));
        // After a cancel, ACP wants every open request answered « cancelled ».
        let (asked, questions) = {
            let mut s = self.state.lock().unwrap();
            (
                std::mem::take(&mut s.asked),
                std::mem::take(&mut s.questions),
            )
        };
        for (id, _) in asked {
            self.conn
                .respond(id, json!({"outcome": {"outcome": "cancelled"}}));
        }
        for id in questions {
            self.conn.respond(id, json!({"action": "cancel"}));
        }
    }

    /// Closes the adapter's stdin, which ends it.
    pub fn close(&self) {
        self.conn.close();
    }

    fn on_closed(&self) {
        let mut s = self.state.lock().unwrap();
        s.closed = true;
        s.asked.clear();
        s.questions.clear();
        for sink in s.subscribers.drain(..) {
            sink(RunEvent::Closed);
        }
    }
}

#[cfg(test)]
mod tests;
