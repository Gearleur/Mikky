//! The API the screens use (spec §5): JSON-RPC 2.0 over a WebSocket on
//! 127.0.0.1, with the token in `Authorization: Bearer`.
//!
//! Requests: `hello`, `runs.list`, `run.start`, `run.open`, `run.request`,
//! `run.prompt`, `run.answer`, `run.answerQuestion`, `run.cancel`,
//! `run.stop`, `run.subscribe`. Notifications to the client:
//! `run.traffic` (every ACP message of a run, the past ones first on
//! subscribe) and `run.closed`.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use mikky_acp::{RpcError, Run, RunEvent, Traffic};
use serde_json::{Value, json};
use tokio::net::{TcpListener, TcpStream};
use tokio::process::Child;
use tokio::sync::{Notify, mpsc};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::tungstenite::handshake::server::{ErrorResponse, Request, Response};
use tokio_tungstenite::tungstenite::http::StatusCode;

use crate::endpoint::same_token;
use crate::job::Job;
use crate::target::{self, Host};

/// One agent `mikkyd` runs.
struct Agent {
    provider: String,
    host: String,
    cwd: String,
    run: Run,
    child: tokio::sync::Mutex<Child>,
    job: Option<Job>,
}

#[derive(Default)]
pub struct Daemon {
    agents: Mutex<HashMap<String, Arc<Agent>>>,
    next: AtomicU64,
    clients: AtomicUsize,
    /// Wakes the idle watch when a client comes or goes.
    clients_changed: Notify,
}

impl Daemon {
    fn agent(&self, params: &Value) -> Result<Arc<Agent>, RpcError> {
        let id = str_param(params, "run")?;
        self.agents.lock().unwrap().get(id).cloned().ok_or_else(|| RpcError::new(-32000, format!("no run {id}")))
    }

    /// Ends every agent (when `mikkyd` ends).
    pub async fn stop_all(&self) {
        let agents: Vec<_> = self.agents.lock().unwrap().values().cloned().collect();
        for a in agents {
            stop(&a).await;
        }
    }

    /// Returns once no screen has been connected for `grace`.
    pub async fn idle(&self, grace: Duration) {
        loop {
            if self.clients.load(Ordering::SeqCst) == 0 {
                tokio::select! {
                    _ = tokio::time::sleep(grace) => {
                        if self.clients.load(Ordering::SeqCst) == 0 {
                            return;
                        }
                    }
                    _ = self.clients_changed.notified() => {}
                }
            } else {
                self.clients_changed.notified().await;
            }
        }
    }
}

/// Serves screens on `listener` until the process ends.
pub async fn serve(listener: TcpListener, token: String, daemon: Arc<Daemon>) {
    loop {
        let Ok((stream, _)) = listener.accept().await else { continue };
        tokio::spawn(client(stream, token.clone(), daemon.clone()));
    }
}

async fn client(stream: TcpStream, token: String, daemon: Arc<Daemon>) {
    let check = |req: &Request, resp: Response| -> Result<Response, ErrorResponse> {
        let auth = req.headers().get("authorization").and_then(|v| v.to_str().ok()).unwrap_or("");
        // A browser page always sends an Origin: no web page may drive agents.
        let from_browser = req.headers().contains_key("origin");
        if from_browser || !same_token(auth.strip_prefix("Bearer ").unwrap_or(""), &token) {
            let mut e = ErrorResponse::new(None);
            *e.status_mut() = StatusCode::UNAUTHORIZED;
            return Err(e);
        }
        Ok(resp)
    };
    let Ok(ws) = tokio_tungstenite::accept_hdr_async(stream, check).await else { return };
    daemon.clients.fetch_add(1, Ordering::SeqCst);
    daemon.clients_changed.notify_one();

    let (mut sink, mut source) = ws.split();
    let (out, mut out_rx) = mpsc::unbounded_channel::<String>();
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
                tokio::spawn(handle(text.to_string(), out.clone(), daemon.clone()));
            }
            Message::Close(_) => break,
            _ => {}
        }
    }
    writer.abort();
    daemon.clients.fetch_sub(1, Ordering::SeqCst);
    daemon.clients_changed.notify_one();
}

async fn handle(text: String, out: mpsc::UnboundedSender<String>, daemon: Arc<Daemon>) {
    let Ok(req) = serde_json::from_str::<Value>(&text) else { return };
    let method = req.get("method").and_then(Value::as_str).unwrap_or_default();
    let params = req.get("params").cloned().unwrap_or_else(|| json!({}));
    let result = dispatch(&daemon, method, &params, &out).await;
    let Some(id) = req.get("id").cloned() else { return };
    let answer = match result {
        Ok(result) => json!({"jsonrpc": "2.0", "id": id, "result": result}),
        Err(e) => json!({"jsonrpc": "2.0", "id": id, "error": {"code": e.code, "message": e.message}}),
    };
    let _ = out.send(answer.to_string());
}

async fn dispatch(daemon: &Arc<Daemon>, method: &str, params: &Value, out: &mpsc::UnboundedSender<String>) -> Result<Value, RpcError> {
    match method {
        "hello" => Ok(json!({"version": env!("CARGO_PKG_VERSION"), "pid": std::process::id()})),
        "runs.list" => {
            let agents = daemon.agents.lock().unwrap();
            Ok(agents
                .iter()
                .map(|(id, a)| {
                    json!({
                        "run": id, "provider": a.provider, "host": a.host, "cwd": a.cwd,
                        "sessionId": a.run.session_id(), "alive": a.run.alive(), "working": a.run.working(),
                    })
                })
                .collect())
        }
        "run.start" => start(daemon, params),
        "run.open" => {
            let a = daemon.agent(params)?;
            let session = a
                .run
                .open(
                    str_param(params, "cwd")?,
                    params.get("resume").and_then(Value::as_str),
                    params.get("mode").and_then(Value::as_str),
                )
                .await?;
            Ok(json!({"sessionId": session}))
        }
        "run.request" => {
            let a = daemon.agent(params)?;
            a.run.request(str_param(params, "method")?, params.get("params").cloned().unwrap_or_else(|| json!({}))).await
        }
        "run.prompt" => daemon.agent(params)?.run.prompt(str_param(params, "text")?).await,
        "run.answer" => {
            let a = daemon.agent(params)?;
            let allow = params.get("allow").and_then(Value::as_bool).unwrap_or(false);
            let always = params.get("always").and_then(Value::as_bool).unwrap_or(false);
            Ok(json!(a.run.answer(allow, always, params.get("requestId").filter(|v| !v.is_null()))))
        }
        "run.answerQuestion" => {
            let a = daemon.agent(params)?;
            Ok(json!(a.run.answer_question(params.get("answers").filter(|v| !v.is_null()).cloned())))
        }
        "run.cancel" => {
            daemon.agent(params)?.run.cancel();
            Ok(Value::Null)
        }
        "run.stop" => {
            let a = daemon.agent(params)?;
            stop(&a).await;
            Ok(Value::Null)
        }
        "run.subscribe" => {
            let id = str_param(params, "run")?.to_owned();
            let a = daemon.agent(params)?;
            // Straight into this screen's queue, as it happens: the past
            // before the answer to subscribe, and each message before the
            // answer to the request it ends (a prompt's last words first).
            let out = out.clone();
            a.run.subscribe(Box::new(move |e| {
                let text = match e {
                    RunEvent::Traffic(t) => traffic(&id, &t),
                    RunEvent::Closed => notification("run.closed", json!({"run": id})),
                };
                out.send(text).is_ok()
            }));
            Ok(Value::Null)
        }
        _ => Err(RpcError::new(-32601, format!("Method not found: {method}"))),
    }
}

/// Starts an adapter (the app says which: `executable args` in `cwd` on
/// `host`, with `env`) and puts it in its own job.
fn start(daemon: &Arc<Daemon>, params: &Value) -> Result<Value, RpcError> {
    let provider = str_param(params, "provider")?.to_owned();
    let host_name = str_param(params, "host")?.to_owned();
    let executable = str_param(params, "executable")?;
    let cwd = str_param(params, "cwd")?.to_owned();
    let args: Vec<String> = params
        .get("args")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(Value::as_str).map(str::to_owned).collect())
        .unwrap_or_default();
    let env: Vec<(String, String)> = params
        .get("env")
        .and_then(Value::as_object)
        .map(|m| m.iter().filter_map(|(k, v)| Some((k.clone(), v.as_str()?.to_owned()))).collect())
        .unwrap_or_default();
    let host = match host_name.as_str() {
        "windows" => Host::Windows,
        "wsl" => Host::Wsl { distro: params.get("distro").and_then(Value::as_str).unwrap_or("Ubuntu").to_owned() },
        other => return Err(RpcError::new(-32602, format!("unknown host {other}"))),
    };

    let mut child = target::command(&host, executable, &args, &cwd, &env)
        .spawn()
        .map_err(|e| RpcError::new(-32000, format!("could not start {executable}: {e}")))?;
    let job = child.id().and_then(Job::for_process);
    let (stdin, stdout) = (child.stdin.take().unwrap(), child.stdout.take().unwrap());
    let run = Run::start(stdout, stdin);

    let id = format!("r{}", daemon.next.fetch_add(1, Ordering::Relaxed) + 1);
    let agent = Arc::new(Agent { provider, host: host_name, cwd, run: run.clone(), child: tokio::sync::Mutex::new(child), job });
    daemon.agents.lock().unwrap().insert(id.clone(), agent);
    // Once the adapter is gone, so is the agent (and, dropped, its job with
    // whatever it left running).
    let (daemon, run_id) = (daemon.clone(), id.clone());
    tokio::spawn(async move {
        run.wait_closed().await;
        daemon.agents.lock().unwrap().remove(&run_id);
    });
    Ok(json!({"run": id}))
}

/// Ends an agent and everything it started: cancel the turn, close its
/// stdin (which ends the adapter), then the job ends what is left.
async fn stop(a: &Agent) {
    if a.run.working() {
        a.run.cancel();
    }
    a.run.close();
    let mut child = a.child.lock().await;
    let _ = tokio::time::timeout(Duration::from_secs(3), child.wait()).await;
    match &a.job {
        Some(job) => job.terminate(),
        None => {
            let _ = child.start_kill();
        }
    }
}

fn traffic(run: &str, t: &Traffic) -> String {
    notification("run.traffic", json!({"run": run, "outgoing": t.outgoing, "at": t.at, "message": t.message}))
}

fn notification(method: &str, params: Value) -> String {
    json!({"jsonrpc": "2.0", "method": method, "params": params}).to_string()
}

fn str_param<'a>(params: &'a Value, key: &str) -> Result<&'a str, RpcError> {
    params.get(key).and_then(Value::as_str).ok_or_else(|| RpcError::new(-32602, format!("missing {key}")))
}
