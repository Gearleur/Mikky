//! The API the screens use (spec §5): JSON-RPC 2.0 over a WebSocket on
//! 127.0.0.1, with the token in `Authorization: Bearer`.
//!
//! Requests: `hello`, `runs.list`, `run.start`, `run.open`, `run.request`,
//! `run.prompt`, `run.answer`, `run.answerQuestion`, `run.cancel`,
//! `run.stop`, `run.subscribe`; Claude Code's hooks (`hooks.rs`):
//! `hook.event` (from `mikky-hook`), `hooks.list`, `hooks.answer`,
//! `hooks.status`, `hooks.preview`, `hooks.write`. Notifications to the
//! client: `run.traffic` (every ACP message of a run, the past ones first
//! on subscribe), `run.closed`, `hooks.changed`.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
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
    /// PID of the ACP adapter started on this daemon's host, not of its children.
    adapter_pid: Option<u32>,
    run: Run,
    child: tokio::sync::Mutex<Child>,
    job: Option<Job>,
}

pub struct Daemon {
    store: crate::store::Store,
    sessions: crate::watch::Sessions,
    agents: Mutex<HashMap<String, Arc<Agent>>>,
    next: AtomicU64,
    instance: String,
    shutdown: Notify,
    allow_wsl: bool,
    wsl: tokio::sync::Mutex<Option<Arc<crate::wsl::Proxy>>>,
    preparing: tokio::sync::Mutex<()>,
    logins: crate::login::Logins,
    pub hooks: crate::hooks::Hooks,
}

impl Daemon {
    pub fn new(
        store: crate::store::Store,
        sessions: crate::watch::Sessions,
        allow_wsl: bool,
    ) -> Self {
        Self {
            store,
            sessions,
            agents: Mutex::new(HashMap::new()),
            next: AtomicU64::new(0),
            instance: crate::endpoint::new_token()[..16].into(),
            shutdown: Notify::new(),
            allow_wsl,
            wsl: tokio::sync::Mutex::new(None),
            preparing: tokio::sync::Mutex::new(()),
            logins: crate::login::Logins::default(),
            hooks: crate::hooks::Hooks::default(),
        }
    }
    async fn wsl(
        &self,
        out: &mpsc::UnboundedSender<String>,
    ) -> Result<Arc<crate::wsl::Proxy>, RpcError> {
        let mut proxy = self.wsl.lock().await;
        if !proxy.as_ref().is_some_and(|p| p.alive()) {
            *proxy = Some(crate::wsl::Proxy::start().await?);
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
    if daemon.allow_wsl
        && (params["host"] == "wsl"
            || params["run"]
                .as_str()
                .is_some_and(|s| s.starts_with("wsl:"))
            || params["path"]
                .as_str()
                .is_some_and(|s| s.starts_with("\\\\wsl.localhost\\Ubuntu\\")))
    {
        let mut remote = params.clone();
        if remote["host"] == "wsl" {
            remote["host"] = json!("windows");
        }
        if let Some(id) = params["run"].as_str().and_then(|s| s.strip_prefix("wsl:")) {
            remote["run"] = json!(id);
        }
        if let Some(path) = params["path"]
            .as_str()
            .and_then(|s| s.strip_prefix("\\\\wsl.localhost\\Ubuntu"))
        {
            remote["path"] = json!(path.replace('\\', "/"));
        }
        let proxy = daemon.wsl(out).await?;
        if method == "tools.login" {
            proxy.login_sink(str_param(params, "login")?, out);
        }
        let mut result = proxy.request(method, remote).await?;
        if method == "run.start" || method == "tools.launch" {
            crate::wsl::prefix(&mut result);
        }
        if method == "sessions.read" {
            crate::wsl::prefix(&mut result["session"]);
        }
        return Ok(result);
    }
    match method {
        "tools.login" => {
            daemon
                .logins
                .start(
                    str_param(params, "provider")?,
                    str_param(params, "login")?.to_owned(),
                    out.clone(),
                )
                .await
        }
        "tools.cancelLogin" => {
            daemon.logins.cancel(str_param(params, "login")?);
            Ok(Value::Null)
        }
        "tools.status" => Ok(crate::tools::status().await),
        "hook.event" => {
            let payload = params.get("payload").cloned().unwrap_or(Value::Null);
            let own = |session: &str| {
                daemon
                    .agents
                    .lock()
                    .unwrap()
                    .values()
                    .any(|a| a.run.session_id().as_deref() == Some(session))
            };
            let out = out.clone();
            Ok(daemon.hooks.event(&payload, own, async move { out.closed().await }).await)
        }
        "hooks.list" => Ok(daemon.hooks.list()),
        "hooks.answer" => {
            let id = params
                .get("id")
                .and_then(Value::as_u64)
                .ok_or_else(|| RpcError::new(-32602, "missing id"))?;
            Ok(json!(daemon.hooks.answer(id, params.get("decision").and_then(Value::as_str))))
        }
        "hooks.status" => Ok(crate::claude_settings::status()),
        "hooks.preview" => crate::claude_settings::preview(params["install"].as_bool().unwrap_or(true))
            .map_err(|e| RpcError::new(-32000, e)),
        "hooks.write" => crate::claude_settings::write(
            params["install"].as_bool().unwrap_or(true),
            str_param(params, "fingerprint")?,
        )
        .map_err(|e| RpcError::new(-32000, e)),
        "tools.auth" => crate::tools::auth(str_param(params, "provider")?).await,
        "tools.launch" => {
            let _prepare = daemon.preparing.lock().await;
            crate::tools::prepare().await?;
            let command =
                crate::tools::launch(str_param(params, "provider")?, str_param(params, "cwd")?)
                    .await?;
            start(daemon, &command)
        }
        "autostart.status" => crate::autostart::configure(None).await,
        "autostart.set" => {
            crate::autostart::configure(Some(
                params
                    .get("enabled")
                    .and_then(Value::as_bool)
                    .ok_or_else(|| RpcError::new(-32602, "missing enabled"))?,
            ))
            .await
        }
        "sessions.list" => {
            let mut list = daemon.sessions.list();
            if daemon.allow_wsl {
                if let Ok(proxy) = daemon.wsl(out).await {
                    if let Ok(Value::Array(mut remote)) = proxy.request(method, json!({})).await {
                        for item in &mut remote {
                            crate::wsl::prefix(item);
                        }
                        list.as_array_mut().unwrap().extend(remote);
                    }
                }
            }
            Ok(list)
        }
        "sessions.delete" => {
            daemon
                .sessions
                .delete(std::path::Path::new(str_param(params, "path")?))
                .map_err(|e| RpcError::new(-32000, e))?;
            Ok(Value::Null)
        }
        "sessions.read" => daemon
            .sessions
            .read(
                std::path::Path::new(str_param(params, "path")?),
                params.get("after").and_then(Value::as_u64).unwrap_or(0) as usize,
                params
                    .get("generation")
                    .and_then(Value::as_u64)
                    .unwrap_or(0),
            )
            .ok_or_else(|| RpcError::new(-32000, "unknown session")),
        "state.get" => daemon
            .store
            .read()
            .await
            .map_err(|e| RpcError::new(-32000, e)),
        "state.patch" => daemon
            .store
            .patch(params.clone())
            .await
            .map_err(|e| RpcError::new(-32000, e)),
        "hello" => Ok(
            json!({"version": env!("CARGO_PKG_VERSION"), "protocol": 3, "persistent": true, "pid": std::process::id()}),
        ),
        "runs.stopAll" => {
            daemon.stop_all().await;
            if daemon.allow_wsl {
                daemon.wsl(out).await?.request(method, json!({})).await?;
            }
            Ok(Value::Null)
        }
        "daemon.shutdown" => {
            daemon.stop_all().await;
            daemon.shutdown.notify_one();
            Ok(Value::Null)
        }
        "runs.list" => {
            let remote = if daemon.allow_wsl {
                // A missing WSL installation does not prevent Windows work.
                match daemon.wsl(out).await {
                    Ok(proxy) => proxy
                        .request(method, json!({}))
                        .await
                        .unwrap_or(json!([{"unavailable":true}])),
                    Err(e) => json!([{"unavailable":true,"message":e.message}]),
                }
            } else {
                json!([])
            };
            let agents = daemon.agents.lock().unwrap();
            let mut list: Vec<Value> = agents
                .iter()
                .map(|(id, a)| {
                    json!({
                        "run": id, "provider": a.provider, "host": a.host, "cwd": a.cwd,
                        "adapterPid": a.adapter_pid,
                        "sessionId": a.run.session_id(), "alive": a.run.alive(), "working": a.run.working(),
                    })
                })
                .collect();
            if let Value::Array(mut remote) = remote {
                for item in &mut remote {
                    crate::wsl::prefix(item);
                }
                list.extend(remote);
            }
            Ok(json!(list))
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
            a.run
                .request(
                    str_param(params, "method")?,
                    params.get("params").cloned().unwrap_or_else(|| json!({})),
                )
                .await
        }
        "run.prompt" => {
            daemon
                .agent(params)?
                .run
                .prompt(str_param(params, "text")?)
                .await
        }
        "run.answer" => {
            let a = daemon.agent(params)?;
            let allow = params
                .get("allow")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let always = params
                .get("always")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            Ok(json!(a.run.answer(
                allow,
                always,
                params.get("requestId").filter(|v| !v.is_null())
            )))
        }
        "run.answerQuestion" => {
            let a = daemon.agent(params)?;
            Ok(json!(a.run.answer_question(
                params.get("answers").filter(|v| !v.is_null()).cloned()
            )))
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
            let (next, more) = a.run.subscribe_page(
                params.get("after").and_then(Value::as_u64).unwrap_or(0),
                256,
                Box::new(move |e| {
                    let text = match e {
                        RunEvent::Traffic(t) => traffic(&id, &t),
                        RunEvent::Closed => notification("run.closed", json!({"run": id})),
                    };
                    out.send(text).is_ok()
                }),
            );
            Ok(json!({"next":next,"more":more}))
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
        .map(|a| {
            a.iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default();
    let env: Vec<(String, String)> = params
        .get("env")
        .and_then(Value::as_object)
        .map(|m| {
            m.iter()
                .filter_map(|(k, v)| Some((k.clone(), v.as_str()?.to_owned())))
                .collect()
        })
        .unwrap_or_default();
    let host = match host_name.as_str() {
        "windows" => Host::Windows,
        "wsl" => Host::Wsl {
            distro: params
                .get("distro")
                .and_then(Value::as_str)
                .unwrap_or("Ubuntu")
                .to_owned(),
        },
        other => return Err(RpcError::new(-32602, format!("unknown host {other}"))),
    };

    let mut child = target::command(&host, executable, &args, &cwd, &env)
        .spawn()
        .map_err(|e| RpcError::new(-32000, format!("could not start {executable}: {e}")))?;
    let adapter_pid = child.id();
    let job = adapter_pid.and_then(Job::for_process);
    let (stdin, stdout) = (child.stdin.take().unwrap(), child.stdout.take().unwrap());
    let run = Run::start(stdout, stdin);

    // IDs must not collide when a client reconnects to a restarted daemon.
    let id = format!(
        "{}-r{}",
        daemon.instance,
        daemon.next.fetch_add(1, Ordering::Relaxed) + 1
    );
    let agent = Arc::new(Agent {
        provider,
        host: host_name,
        cwd,
        adapter_pid,
        run: run.clone(),
        child: tokio::sync::Mutex::new(child),
        job,
    });
    daemon.agents.lock().unwrap().insert(id.clone(), agent);
    // Once the adapter is gone, so is the agent (and, dropped, its job with
    // whatever it left running).
    let (daemon, run_id) = (daemon.clone(), id.clone());
    tokio::spawn(async move {
        run.wait_closed().await;
        daemon.agents.lock().unwrap().remove(&run_id);
    });
    Ok(json!({"run": id, "cwd": params["cwd"], "adapterPid": adapter_pid}))
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
    notification(
        "run.traffic",
        json!({"run": run, "sequence": t.sequence, "events": t.events}),
    )
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
