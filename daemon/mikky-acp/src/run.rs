//! One agent session driven through ACP (MVP spec §3.1, the Rust twin of
//! the Dart `AgentRun`): open it, prompt it, hold its permission requests
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
    pub outgoing: bool,
    pub at: String,
    pub message: Value,
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
    backlog: Vec<Arc<Traffic>>,
    subscribers: Vec<Sink>,
    /// Permission requests waiting for the user, oldest first.
    asked: Vec<(Value, Vec<PermissionOption>)>,
    /// Questions (form elicitations) waiting for the user, oldest first.
    questions: Vec<Value>,
    session_id: Option<String>,
    /// Prompts sent and not answered yet: a turn is on.
    prompts: usize,
    closed: bool,
}

impl State {
    /// Keeps a message and hands it on. A request the user must answer is
    /// held first, so that no one can answer it before it is known.
    fn record(&mut self, outgoing: bool, message: &Value) {
        if let (false, Some(id), Some(method)) = (outgoing, message.get("id"), message.get("method").and_then(Value::as_str)) {
            let params = message.get("params").unwrap_or(&Value::Null);
            if method == "session/request_permission" {
                let options = params
                    .get("options")
                    .and_then(Value::as_array)
                    .map(|o| {
                        o.iter()
                            .map(|o| PermissionOption {
                                id: o.get("optionId").cloned().unwrap_or(Value::Null),
                                kind: o.get("kind").and_then(Value::as_str).unwrap_or_default().to_owned(),
                            })
                            .collect()
                    })
                    .unwrap_or_default();
                self.asked.push((id.clone(), options));
            } else if held(method, params) {
                self.questions.push(id.clone());
            }
        }
        let t = Arc::new(Traffic {
            outgoing,
            at: chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Micros, true),
            message: message.clone(),
        });
        self.backlog.push(t.clone());
        self.subscribers.retain(|sink| sink(RunEvent::Traffic(t.clone())));
    }
}

/// Requests of the agent that Mikky holds for the user (permissions,
/// questions); any other gets an error.
fn held(method: &str, params: &Value) -> bool {
    method == "session/request_permission"
        || (method == "elicitation/create" && params.get("mode").and_then(Value::as_str) == Some("form"))
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
        let run = Run { conn, state, closed };
        let pump = run.clone();
        tokio::spawn(async move {
            while let Some(e) = events.recv().await {
                match e {
                    Event::Request { id, method, params } if !held(&method, &params) => {
                        pump.conn.respond_error(id, -32601, &format!("Method not found: {method}"));
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
        let mut s = self.state.lock().unwrap();
        for t in &s.backlog {
            if !sink(RunEvent::Traffic(t.clone())) {
                return;
            }
        }
        if s.closed {
            sink(RunEvent::Closed);
        } else {
            s.subscribers.push(sink);
        }
    }

    pub fn session_id(&self) -> Option<String> {
        self.state.lock().unwrap().session_id.clone()
    }

    pub fn alive(&self) -> bool {
        !self.state.lock().unwrap().closed
    }

    /// A turn is on (a prompt waits for its answer).
    pub fn working(&self) -> bool {
        self.state.lock().unwrap().prompts > 0
    }

    pub async fn wait_closed(&self) {
        let mut closed = self.closed.clone();
        let _ = closed.wait_for(|c| *c).await;
    }

    /// Handshake, then a new session in `cwd`, or `resume` one (the agent
    /// replays its thread), then the permission `mode`.
    pub async fn open(&self, cwd: &str, resume: Option<&str>, mode: Option<&str>) -> Result<String, RpcError> {
        self.conn
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
        let session_id = match resume {
            None => {
                let r = self.conn.request("session/new", json!({"cwd": cwd, "mcpServers": []})).await?;
                r.get("sessionId").and_then(Value::as_str).unwrap_or_default().to_owned()
            }
            Some(id) => {
                self.conn.request("session/load", json!({"sessionId": id, "cwd": cwd, "mcpServers": []})).await?;
                id.to_owned()
            }
        };
        self.state.lock().unwrap().session_id = Some(session_id.clone());
        if let Some(mode) = mode {
            self.conn.request("session/set_mode", json!({"sessionId": session_id, "modeId": mode})).await?;
        }
        Ok(session_id)
    }

    /// Any other request to the agent (set a mode, a model…).
    pub async fn request(&self, method: &str, params: Value) -> Result<Value, RpcError> {
        self.conn.request(method, params).await
    }

    /// Sends the user's message. While the agent works, it is slipped in
    /// (queued by the agent). Ends when the agent has answered it.
    pub async fn prompt(&self, text: &str) -> Result<Value, RpcError> {
        let session_id = {
            let mut s = self.state.lock().unwrap();
            s.prompts += 1;
            s.session_id.clone()
        };
        let r = self
            .conn
            .request("session/prompt", json!({"sessionId": session_id, "prompt": [{"type": "text", "text": text}]}))
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
        let pick = wanted.iter().find_map(|kind| options.iter().find(|o| o.kind == *kind));
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
        self.conn.notify("session/cancel", json!({"sessionId": session_id}));
        // After a cancel, ACP wants every open request answered « cancelled ».
        let (asked, questions) = {
            let mut s = self.state.lock().unwrap();
            (std::mem::take(&mut s.asked), std::mem::take(&mut s.questions))
        };
        for (id, _) in asked {
            self.conn.respond(id, json!({"outcome": {"outcome": "cancelled"}}));
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
mod tests {
    use super::*;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, DuplexStream, duplex};
    use tokio::sync::mpsc;

    /// A scripted agent on the other end of the pipes.
    struct Agent {
        input: BufReader<DuplexStream>,
        output: DuplexStream,
    }

    impl Agent {
        async fn next(&mut self) -> Value {
            let mut s = String::new();
            self.input.read_line(&mut s).await.unwrap();
            serde_json::from_str(&s).unwrap()
        }

        async fn send(&mut self, v: Value) {
            self.output.write_all(format!("{v}\n").as_bytes()).await.unwrap();
        }

        /// Answers the next request with `result`; returns it.
        async fn answer(&mut self, result: Value) -> Value {
            let r = self.next().await;
            self.send(json!({"jsonrpc": "2.0", "id": r["id"], "result": result})).await;
            r
        }
    }

    fn start() -> (Run, Agent) {
        let (client_in, agent_out) = duplex(1 << 16);
        let (agent_in, client_out) = duplex(1 << 16);
        (Run::start(client_in, client_out), Agent { input: BufReader::new(agent_in), output: agent_out })
    }

    async fn opened() -> (Run, Agent) {
        let (run, mut agent) = start();
        let open = tokio::spawn({
            let run = run.clone();
            async move { run.open("/tmp/x", None, Some("default")).await }
        });
        assert_eq!(agent.answer(json!({"protocolVersion": 1})).await["method"], "initialize");
        agent.answer(json!({"sessionId": "s1"})).await;
        let mode = agent.answer(json!({})).await;
        assert_eq!(mode["params"], json!({"sessionId": "s1", "modeId": "default"}));
        assert_eq!(open.await.unwrap().unwrap(), "s1");
        (run, agent)
    }

    fn subscribe(run: &Run) -> mpsc::UnboundedReceiver<RunEvent> {
        let (tx, rx) = mpsc::unbounded_channel();
        run.subscribe(Box::new(move |e| tx.send(e).is_ok()));
        rx
    }

    fn permission(id: &str) -> Value {
        json!({"jsonrpc": "2.0", "id": id, "method": "session/request_permission", "params": {"options": [
            {"optionId": "yes", "kind": "allow_once"},
            {"optionId": "always", "kind": "allow_always"},
            {"optionId": "no", "kind": "reject_once"},
        ]}})
    }

    /// Waits until the run holds what the agent just sent.
    async fn settle(run: &Run, n: usize) {
        for _ in 0..200 {
            let pending = {
                let s = run.state.lock().unwrap();
                s.asked.len() + s.questions.len()
            };
            if pending >= n {
                return;
            }
            tokio::time::sleep(std::time::Duration::from_millis(5)).await;
        }
        panic!("nothing pending");
    }

    #[tokio::test]
    async fn permissions_pick_the_option_the_user_meant() {
        let (run, mut agent) = opened().await;
        assert!(!run.answer(true, false, None));
        for (allow, always, want) in [(true, false, "yes"), (true, true, "always"), (false, false, "no")] {
            agent.send(permission("p")).await;
            settle(&run, 1).await;
            assert!(run.answer(allow, always, None));
            let r = agent.next().await;
            assert_eq!(r["result"]["outcome"], json!({"outcome": "selected", "optionId": want}));
        }
    }

    #[tokio::test]
    async fn questions_and_cancel() {
        let (run, mut agent) = opened().await;
        agent
            .send(json!({"jsonrpc": "2.0", "id": 7, "method": "elicitation/create", "params": {"mode": "form"}}))
            .await;
        settle(&run, 1).await;
        assert!(run.answer_question(Some(json!({"question_0": "Postgres"}))));
        assert_eq!(agent.next().await["result"], json!({"action": "accept", "content": {"question_0": "Postgres"}}));

        agent.send(permission("p2")).await;
        settle(&run, 1).await;
        run.cancel();
        assert_eq!(agent.next().await["method"], "session/cancel");
        assert_eq!(agent.next().await["result"], json!({"outcome": {"outcome": "cancelled"}}));
        assert!(!run.answer(true, false, None));
    }

    #[tokio::test]
    async fn subscribers_get_the_backlog_then_the_rest_then_closed() {
        let (run, mut agent) = opened().await;
        let mut rx = subscribe(&run);
        // initialize, session/new, set_mode: asked and answered.
        let mut backlog = vec![];
        for _ in 0..6 {
            let Some(RunEvent::Traffic(t)) = rx.recv().await else { panic!() };
            backlog.push(t);
        }
        assert!(backlog[0].outgoing && !backlog[1].outgoing);
        agent
            .send(json!({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": "s1"}}))
            .await;
        let RunEvent::Traffic(t) = rx.recv().await.unwrap() else { panic!() };
        assert_eq!(t.message["method"], "session/update");
        drop(agent);
        run.wait_closed().await;
        assert!(matches!(rx.recv().await, Some(RunEvent::Closed)));
        assert!(!run.alive());
        let mut late = subscribe(&run);
        let mut last = None;
        while let Some(e) = late.recv().await {
            last = Some(e);
        }
        assert!(matches!(last, Some(RunEvent::Closed)));
    }

    #[tokio::test]
    async fn unknown_requests_get_an_error() {
        let (_run, mut agent) = opened().await;
        agent.send(json!({"jsonrpc": "2.0", "id": 3, "method": "fs/read_text_file", "params": {}})).await;
        assert_eq!(agent.next().await["error"]["code"], -32601);
    }
}
