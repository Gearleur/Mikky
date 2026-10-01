//! JSON-RPC 2.0 over newline-delimited JSON, as ACP uses on an adapter's
//! stdin / stdout. Knows nothing of ACP methods (the Rust twin of the Dart
//! `AcpConnection`).

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::sync::{mpsc, oneshot};

/// An error answer from the agent, or the agent gone.
#[derive(Debug, Clone, PartialEq)]
pub struct RpcError {
    pub code: i64,
    pub message: String,
}

impl RpcError {
    pub fn new(code: i64, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    fn closed() -> Self {
        Self::new(-32000, "agent closed")
    }
}

impl std::fmt::Display for RpcError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} ({})", self.message, self.code)
    }
}

impl std::error::Error for RpcError {}

/// Sees every message, either way (`outgoing`, message), in wire order,
/// right when it is read or written: before the request it answers
/// completes, so whoever follows the traffic never lags behind.
pub type TrafficHook = Arc<dyn Fn(bool, &Value) + Send + Sync>;

/// What comes out of a connection besides the traffic.
#[derive(Debug)]
pub enum Event {
    /// A request from the agent, to answer with [Connection::respond]. The
    /// hook saw it first.
    Request {
        id: Value,
        method: String,
        params: Value,
    },
    /// The agent's output ended.
    Closed,
}

type Pending = oneshot::Sender<Result<Value, RpcError>>;

struct Inner {
    /// Lines to write; `None` once closed, which ends the writer and so
    /// closes the adapter's stdin.
    out: Mutex<Option<mpsc::UnboundedSender<String>>>,
    events: mpsc::UnboundedSender<Event>,
    hook: TrafficHook,
    pending: Mutex<HashMap<u64, Pending>>,
    next_id: AtomicU64,
    closed: AtomicBool,
}

#[derive(Clone)]
pub struct Connection {
    inner: Arc<Inner>,
}

impl Connection {
    /// Talks JSON-RPC on `input` / `output` (the adapter's stdout / stdin);
    /// `hook` sees every message.
    pub fn new<R, W>(
        input: R,
        output: W,
        hook: TrafficHook,
    ) -> (Connection, mpsc::UnboundedReceiver<Event>)
    where
        R: AsyncRead + Unpin + Send + 'static,
        W: AsyncWrite + Unpin + Send + 'static,
    {
        let (events, events_rx) = mpsc::unbounded_channel();
        let (out, out_rx) = mpsc::unbounded_channel();
        let inner = Arc::new(Inner {
            out: Mutex::new(Some(out)),
            events,
            hook,
            pending: Mutex::new(HashMap::new()),
            next_id: AtomicU64::new(0),
            closed: AtomicBool::new(false),
        });
        tokio::spawn(write_loop(output, out_rx));
        tokio::spawn(read_loop(input, inner.clone()));
        (Connection { inner }, events_rx)
    }

    /// Sends a request; its `result`, or the agent's error.
    pub async fn request(&self, method: &str, params: Value) -> Result<Value, RpcError> {
        if self.is_closed() {
            return Err(RpcError::closed());
        }
        let id = self.inner.next_id.fetch_add(1, Ordering::Relaxed);
        let (tx, rx) = oneshot::channel();
        self.inner.pending.lock().unwrap().insert(id, tx);
        self.send(json!({"jsonrpc": "2.0", "id": id, "method": method, "params": params}));
        rx.await.unwrap_or_else(|_| Err(RpcError::closed()))
    }

    pub fn notify(&self, method: &str, params: Value) {
        self.send(json!({"jsonrpc": "2.0", "method": method, "params": params}));
    }

    /// Answers the agent's request `id`.
    pub fn respond(&self, id: Value, result: Value) {
        self.send(json!({"jsonrpc": "2.0", "id": id, "result": result}));
    }

    pub fn respond_error(&self, id: Value, code: i64, message: &str) {
        self.send(json!({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}));
    }

    /// Stops writing: the adapter's stdin closes, which ends it.
    pub fn close(&self) {
        self.inner.out.lock().unwrap().take();
    }

    pub fn is_closed(&self) -> bool {
        self.inner.closed.load(Ordering::Relaxed)
    }

    fn send(&self, message: Value) {
        if self.is_closed() {
            return;
        }
        let out = self.inner.out.lock().unwrap();
        let Some(out) = out.as_ref() else { return };
        // Under the lock: the hook sees messages in the order they are
        // written.
        (self.inner.hook)(true, &message);
        let _ = out.send(message.to_string());
    }
}

async fn write_loop<W: AsyncWrite + Unpin>(
    mut output: W,
    mut lines: mpsc::UnboundedReceiver<String>,
) {
    while let Some(mut line) = lines.recv().await {
        line.push('\n');
        if output.write_all(line.as_bytes()).await.is_err() || output.flush().await.is_err() {
            break;
        }
    }
    let _ = output.shutdown().await;
}

async fn read_loop<R: AsyncRead + Unpin>(input: R, inner: Arc<Inner>) {
    let mut input = BufReader::new(input);
    let mut buf = Vec::new();
    loop {
        buf.clear();
        match input.read_until(b'\n', &mut buf).await {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
        // Lenient: an adapter may print a stray non-UTF-8 byte.
        let line = String::from_utf8_lossy(&buf);
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        // Not JSON: a log line some adapters print on stdout.
        let Ok(message) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        if !message.is_object() {
            continue;
        }
        let method = message
            .get("method")
            .and_then(Value::as_str)
            .map(str::to_owned);
        let id = message.get("id").cloned();
        let params = message.get("params").cloned().unwrap_or(Value::Null);
        let answer = match &method {
            None => Some((
                message.get("result").cloned(),
                message.get("error").cloned(),
            )),
            Some(_) => None,
        };
        (inner.hook)(false, &message);
        match (method, id) {
            (None, Some(id)) => {
                let Some(tx) = id
                    .as_u64()
                    .and_then(|id| inner.pending.lock().unwrap().remove(&id))
                else {
                    continue;
                };
                let (result, error) = answer.unwrap();
                let _ = tx.send(match error {
                    Some(e) => Err(RpcError::new(
                        e.get("code").and_then(Value::as_i64).unwrap_or(-32000),
                        e.get("message").and_then(Value::as_str).unwrap_or(""),
                    )),
                    None => Ok(result.unwrap_or(Value::Null)),
                });
            }
            (Some(method), Some(id)) => {
                let _ = inner.events.send(Event::Request { id, method, params });
            }
            // Notifications are only traffic.
            _ => {}
        }
    }
    inner.closed.store(true, Ordering::Relaxed);
    inner.out.lock().unwrap().take();
    for (_, tx) in inner.pending.lock().unwrap().drain() {
        let _ = tx.send(Err(RpcError::closed()));
    }
    let _ = inner.events.send(Event::Closed);
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::duplex;

    type Seen = Arc<Mutex<Vec<(bool, Value)>>>;

    /// A connection, what its hook saw, and the agent's end of the pipes.
    fn pair() -> (
        Connection,
        mpsc::UnboundedReceiver<Event>,
        Seen,
        tokio::io::DuplexStream,
        tokio::io::DuplexStream,
    ) {
        let (client_in, agent_out) = duplex(1 << 16);
        let (agent_in, client_out) = duplex(1 << 16);
        let seen: Seen = Arc::default();
        let hook = {
            let seen = seen.clone();
            Arc::new(move |outgoing: bool, m: &Value| {
                seen.lock().unwrap().push((outgoing, m.clone()))
            })
        };
        let (c, events) = Connection::new(client_in, client_out, hook);
        (c, events, seen, agent_in, agent_out)
    }

    async fn read_line(r: &mut BufReader<tokio::io::DuplexStream>) -> Value {
        let mut s = String::new();
        r.read_line(&mut s).await.unwrap();
        serde_json::from_str(&s).unwrap()
    }

    #[tokio::test]
    async fn request_gets_its_result_and_traffic_goes_both_ways() {
        let (c, _events, seen, agent_in, mut agent_out) = pair();
        let mut agent_in = BufReader::new(agent_in);
        let call = tokio::spawn({
            let c = c.clone();
            async move { c.request("initialize", json!({"protocolVersion": 1})).await }
        });
        let sent = read_line(&mut agent_in).await;
        assert_eq!(sent["method"], "initialize");
        agent_out
            .write_all(b"not json\n{\"jsonrpc\":\"2.0\",\"id\":0,\"result\":{\"ok\":true}}\n")
            .await
            .unwrap();
        assert_eq!(call.await.unwrap().unwrap(), json!({"ok": true}));
        // Seen before the call completed, both ways, the noise left out.
        let seen = seen.lock().unwrap();
        assert_eq!(seen.len(), 2);
        assert!(seen[0].0 && !seen[1].0);
        assert_eq!(seen[1].1["id"], 0);
    }

    #[tokio::test]
    async fn agent_requests_come_out_and_errors_fail_the_call() {
        let (c, mut events, _seen, _agent_in, mut agent_out) = pair();
        let call = tokio::spawn({
            let c = c.clone();
            async move { c.request("session/prompt", json!({})).await }
        });
        agent_out
            .write_all(b"{\"jsonrpc\":\"2.0\",\"id\":\"p1\",\"method\":\"session/request_permission\",\"params\":{\"x\":1}}\n")
            .await
            .unwrap();
        loop {
            if let Event::Request { id, method, params } = events.recv().await.unwrap() {
                assert_eq!(
                    (id, method.as_str(), params),
                    (json!("p1"), "session/request_permission", json!({"x": 1}))
                );
                break;
            }
        }
        agent_out
            .write_all(b"{\"jsonrpc\":\"2.0\",\"id\":0,\"error\":{\"code\":-32603,\"message\":\"boom\"}}\n")
            .await
            .unwrap();
        assert_eq!(call.await.unwrap(), Err(RpcError::new(-32603, "boom")));
    }

    #[tokio::test]
    async fn the_agent_gone_fails_what_waits() {
        let (c, mut events, _seen, _agent_in, agent_out) = pair();
        let call = tokio::spawn({
            let c = c.clone();
            async move { c.request("session/prompt", json!({})).await }
        });
        tokio::task::yield_now().await;
        drop(agent_out);
        assert_eq!(call.await.unwrap(), Err(RpcError::closed()));
        while let Some(e) = events.recv().await {
            if matches!(e, Event::Closed) {
                assert!(c.is_closed());
                return;
            }
        }
        panic!("no Closed");
    }
}
