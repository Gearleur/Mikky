//! The API the screens use (spec §5): JSON-RPC 2.0 over a WebSocket on
//! 127.0.0.1, with the token in `Authorization: Bearer`.
//!
//! Each family of methods has its file: `run.*` and `runs.*` (`runs.rs`),
//! `hook.event` and `hooks.*` (`hooks.rs`), `tools.*` (`tools.rs`),
//! `sessions.*` and `state.*` (`sessions.rs`); a request for WSL goes to
//! its engine (`wsl.rs`). Here: the connection, `hello`, `autostart.*`
//! and `daemon.shutdown`. Notifications to the client: `run.traffic` (every
//! ACP message of a run, the past ones first on subscribe), `run.closed`,
//! `hooks.changed`, `sessions.changed`, `state.changed`.

use std::collections::HashMap;
use std::sync::atomic::AtomicU64;
use std::sync::{Arc, Mutex};

use futures_util::{SinkExt, StreamExt};
use mikky_acp::RpcError;
use serde_json::{Value, json};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{Notify, mpsc};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::tungstenite::handshake::server::{ErrorResponse, Request, Response};
use tokio_tungstenite::tungstenite::http::StatusCode;

use crate::system::endpoint::same_token;
use runs::{Agent, stop};

/// What every file of the API uses.
mod prelude {
    pub(super) use std::sync::Arc;

    pub(super) use mikky_acp::RpcError;
    pub(super) use serde_json::{Value, json};

    pub(super) use super::{Daemon, Out, RpcResult, not_found, str_param};
}

mod hooks;
mod runs;
mod sessions;
mod tools;
mod wsl;

/// Where a screen's answers and notifications go.
type Out = mpsc::UnboundedSender<String>;
type RpcResult = Result<Value, RpcError>;

pub struct Daemon {
    store: crate::store::Store,
    sessions: crate::sessions::watch::Sessions,
    agents: Mutex<HashMap<String, Arc<Agent>>>,
    next: AtomicU64,
    instance: String,
    shutdown: Notify,
    allow_wsl: bool,
    wsl: tokio::sync::Mutex<Option<Arc<crate::system::wsl::Proxy>>>,
    preparing: tokio::sync::Mutex<()>,
    logins: crate::tools::login::Logins,
    pub hooks: crate::hooks::Hooks,
}

impl Daemon {
    pub fn new(
        store: crate::store::Store,
        sessions: crate::sessions::watch::Sessions,
        allow_wsl: bool,
    ) -> Self {
        Self {
            store,
            sessions,
            agents: Mutex::new(HashMap::new()),
            next: AtomicU64::new(0),
            instance: crate::system::endpoint::new_token()[..16].into(),
            shutdown: Notify::new(),
            allow_wsl,
            wsl: tokio::sync::Mutex::new(None),
            preparing: tokio::sync::Mutex::new(()),
            logins: crate::tools::login::Logins::default(),
            hooks: crate::hooks::Hooks::default(),
        }
    }
    async fn wsl(
        &self,
        out: &mpsc::UnboundedSender<String>,
    ) -> Result<Arc<crate::system::wsl::Proxy>, RpcError> {
        let mut proxy = self.wsl.lock().await;
        if !proxy.as_ref().is_some_and(|p| p.alive()) {
            *proxy = Some(crate::system::wsl::Proxy::start().await?);
        }
        let proxy = proxy.as_ref().unwrap().clone();
        proxy.subscribe(out);
        Ok(proxy)
    }
    fn agent(&self, params: &Value) -> Result<Arc<Agent>, RpcError> {
        let id = str_param(params, "run")?;
        self.agents
            .lock()
            .unwrap()
            .get(id)
            .cloned()
            .ok_or_else(|| RpcError::new(-32000, format!("no run {id}")))
    }

    /// Ends every agent (when `mikkyd` ends).
    pub async fn stop_all(&self) {
        let agents: Vec<_> = self.agents.lock().unwrap().values().cloned().collect();
        futures_util::future::join_all(agents.iter().map(|a| stop(a))).await;
    }

    pub async fn wait_shutdown(&self) {
        self.shutdown.notified().await;
    }
}

/// Serves screens on `listener` until the process ends.
pub async fn serve(listener: TcpListener, token: String, daemon: Arc<Daemon>) {
    loop {
        let Ok((stream, _)) = listener.accept().await else {
            continue;
        };
        tokio::spawn(client(stream, token.clone(), daemon.clone()));
    }
}

async fn client(stream: TcpStream, token: String, daemon: Arc<Daemon>) {
    // The handshake callback type is set by tungstenite.
    #[allow(clippy::result_large_err)]
    let check = |req: &Request, resp: Response| -> Result<Response, ErrorResponse> {
        let auth = req
            .headers()
            .get("authorization")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("");
        // A browser page always sends an Origin: no web page may drive agents.
        let from_browser = req.headers().contains_key("origin");
        if from_browser || !same_token(auth.strip_prefix("Bearer ").unwrap_or(""), &token) {
            let mut e = ErrorResponse::new(None);
            *e.status_mut() = StatusCode::UNAUTHORIZED;
            return Err(e);
        }
        Ok(resp)
    };
    let Ok(ws) = tokio_tungstenite::accept_hdr_async(stream, check).await else {
        return;
    };

    let (mut sink, mut source) = ws.split();
    let (out, mut out_rx) = mpsc::unbounded_channel::<String>();
    let watching = watch_notifications(&daemon, out.clone());
    // A screen (it says hello): requests from Claude's hooks may wait for
    // it. Hook relays never do.
    let mut screen = false;
    let writer = tokio::spawn(async move {
        while let Some(text) = out_rx.recv().await {
            if sink.send(Message::text(text)).await.is_err() {
                break;
            }
        }
        let _ = sink.close().await;
    });
    while let Some(Ok(msg)) = source.next().await {
        match msg {
            Message::Text(text) => {
                if !screen && text.contains("\"hello\"") {
                    screen = true;
                    daemon.hooks.screen_joined();
                }
                tokio::spawn(handle(text.to_string(), out.clone(), daemon.clone()));
            }
            Message::Close(_) => break,
            _ => {}
        }
    }
    writer.abort();
    watching.abort();
    if screen {
        daemon.hooks.screen_left();
    }
}

pub fn watch_notifications(
    daemon: &Arc<Daemon>,
    notices: mpsc::UnboundedSender<String>,
) -> tokio::task::JoinHandle<()> {
    let mut changes = daemon.sessions.changes.subscribe();
    let mut state = daemon.store.changes.subscribe();
    let mut hooks = daemon.hooks.changes.subscribe();
    let daemon = daemon.clone();
    tokio::spawn(async move {
        loop {
            let update = tokio::select! {
                result = hooks.recv() => {
                    if matches!(result, Err(tokio::sync::broadcast::error::RecvError::Closed)) { break; }
                    if notices.send(notification("hooks.changed", json!({"requests": daemon.hooks.list()}))).is_err() { break; }
                    None
                }
                result = changes.recv() => Some(result),
                result = state.recv() => {
                    if matches!(result, Err(tokio::sync::broadcast::error::RecvError::Closed)) { break; }
                    if notices.send(notification("state.changed", json!({}))).is_err() { break; }
                    None
                }
            };
            let Some(update) = update else {
                continue;
            };
            let params = match update {
                Ok(session) => session,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => json!({"rescan": true}),
                Err(_) => break,
            };
            if notices
                .send(notification("sessions.changed", params))
                .is_err()
            {
                break;
            }
        }
    })
}

pub async fn handle(text: String, out: mpsc::UnboundedSender<String>, daemon: Arc<Daemon>) {
    let Ok(req) = serde_json::from_str::<Value>(&text) else {
        return;
    };
    let method = req
        .get("method")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let params = req.get("params").cloned().unwrap_or_else(|| json!({}));
    let result = dispatch(&daemon, method, &params, &out).await;
    let Some(id) = req.get("id").cloned() else {
        return;
    };
    let answer = match result {
        Ok(result) => json!({"jsonrpc": "2.0", "id": id, "result": result}),
        Err(e) => {
            json!({"jsonrpc": "2.0", "id": id, "error": {"code": e.code, "message": e.message}})
        }
    };
    let _ = out.send(answer.to_string());
}

async fn dispatch(
    daemon: &Arc<Daemon>,
    method: &str,
    params: &Value,
    out: &mpsc::UnboundedSender<String>,
) -> Result<Value, RpcError> {
    if wsl::targets_wsl(daemon, params) {
        return wsl::forward(daemon, method, params, out).await;
    }
    match method.split('.').next().unwrap_or_default() {
        "run" | "runs" => return runs::dispatch(daemon, method, params, out).await,
        "hook" | "hooks" => return hooks::dispatch(daemon, method, params, out).await,
        "tools" => return tools::dispatch(daemon, method, params, out).await,
        "sessions" | "state" => return sessions::dispatch(daemon, method, params, out).await,
        _ => {}
    }
    match method {
        "autostart.status" => crate::system::autostart::configure(None).await,
        "autostart.set" => {
            crate::system::autostart::configure(Some(
                params
                    .get("enabled")
                    .and_then(Value::as_bool)
                    .ok_or_else(|| RpcError::new(-32602, "missing enabled"))?,
            ))
            .await
        }
        "hello" => Ok(
            json!({"version": env!("CARGO_PKG_VERSION"), "protocol": 3, "persistent": true, "pid": std::process::id()}),
        ),
        "daemon.shutdown" => {
            daemon.stop_all().await;
            daemon.shutdown.notify_one();
            Ok(Value::Null)
        }
        _ => Err(not_found(method)),
    }
}

fn not_found(method: &str) -> RpcError {
    RpcError::new(-32601, format!("Method not found: {method}"))
}

fn notification(method: &str, params: Value) -> String {
    json!({"jsonrpc": "2.0", "method": method, "params": params}).to_string()
}

fn str_param<'a>(params: &'a Value, key: &str) -> Result<&'a str, RpcError> {
    params
        .get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| RpcError::new(-32602, format!("missing {key}")))
}
