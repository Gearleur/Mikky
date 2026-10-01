//! The Windows hub talks to a persistent Linux backend through a private pipe.
//! No listening TCP port, token file, or Node watch probe in WSL.
use mikky_acp::RpcError;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    process::Command,
    sync::{mpsc, oneshot},
};

type Pending = oneshot::Sender<Result<Value, RpcError>>;
pub struct Proxy {
    input: mpsc::UnboundedSender<String>,
    pending: Mutex<HashMap<u64, Pending>>,
    sinks: Mutex<Vec<mpsc::UnboundedSender<String>>>,
    login_sinks: Mutex<HashMap<String, mpsc::UnboundedSender<String>>>,
    next: AtomicU64,
    closed: AtomicBool,
}

impl Proxy {
    pub async fn start() -> Result<Arc<Self>, RpcError> {
        for _ in 0..2 {
            let proxy = Self::start_once().await?;
            let hello = proxy.request("hello", json!({})).await?;
            if hello["protocol"] == 3 {
                return Ok(proxy);
            }
            let runs = proxy.request("runs.list", json!({})).await?;
            if !runs.as_array().is_some_and(|r| r.is_empty()) {
                return Err(RpcError::new(
                    -32000,
                    "Le moteur WSL doit être mis à jour. Termine ses agents avant de le relancer.",
                ));
            }
            let _ = proxy.request("daemon.shutdown", json!({})).await;
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        }
        Err(RpcError::new(
            -32000,
            "Le moteur WSL installé est incompatible",
        ))
    }

    async fn start_once() -> Result<Arc<Self>, RpcError> {
        // The bundled Linux binary is executed from the installation directory.
        // It opens a private socket to its daemon; closing this bridge leaves
        // that daemon and its agents alone.
        let exe = std::env::current_exe().map_err(error)?;
        let bundled = exe.parent().unwrap().join("mikkyd-linux");
        let path = if bundled.exists() {
            let path = bundled.to_string_lossy().replace('\\', "/");
            if path.as_bytes().get(1) == Some(&b':') {
                format!("/mnt/{}/{}", &path[..1].to_lowercase(), &path[3..])
            } else {
                path
            }
        } else {
            return Err(RpcError::new(
                -32000,
                "Le moteur Linux manque dans l’installation de Mikky.",
            ));
        };
        let mut command = Command::new("wsl.exe");
        command
            .args(["-d", "Ubuntu", "--", &path, "--bridge"])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null())
            .kill_on_drop(true);
        #[cfg(windows)]
        command.creation_flags(0x0800_0000);
        let mut child = command.spawn().map_err(error)?;
        let mut input = child.stdin.take().unwrap();
        let mut lines = BufReader::new(child.stdout.take().unwrap()).lines();
        let (send, mut receive) = mpsc::unbounded_channel::<String>();
        let proxy = Arc::new(Self {
            input: send,
            pending: Mutex::new(HashMap::new()),
            sinks: Mutex::new(vec![]),
            login_sinks: Mutex::new(HashMap::new()),
            next: AtomicU64::new(1),
            closed: AtomicBool::new(false),
        });
        let writer = tokio::spawn(async move {
            while let Some(line) = receive.recv().await {
                if input
                    .write_all(format!("{line}\n").as_bytes())
                    .await
                    .is_err()
                {
                    break;
                }
            }
        });
        let reading = proxy.clone();
        tokio::spawn(async move {
            while let Ok(Some(line)) = lines.next_line().await {
                let Ok(mut message) = serde_json::from_str::<Value>(&line) else {
                    continue;
                };
                if message["method"].is_string() {
                    let params = &mut message["params"];
                    prefix(params);
                    let text = message.to_string();
                    if let Some(id) = message["params"]["login"].as_str() {
                        let mut sinks = reading.login_sinks.lock().unwrap();
                        if let Some(sink) = sinks.get(id) {
                            let _ = sink.send(text);
                        }
                        if message["method"] == "login.done" {
                            sinks.remove(id);
                        }
                    } else {
                        reading
                            .sinks
                            .lock()
                            .unwrap()
                            .retain(|sink| sink.send(text.clone()).is_ok());
                    }
                } else if let Some(id) = message["id"].as_u64() {
                    if let Some(reply) = reading.pending.lock().unwrap().remove(&id) {
                        let result = if message["error"].is_object() {
                            Err(RpcError::new(
                                message["error"]["code"].as_i64().unwrap_or(-32000),
                                message["error"]["message"].as_str().unwrap_or("WSL error"),
                            ))
                        } else {
                            Ok(message["result"].take())
                        };
                        let _ = reply.send(result);
                    }
                }
            }
            reading.closed.store(true, Ordering::SeqCst);
            let disconnected =
                json!({"jsonrpc":"2.0","method":"machine.disconnected","params":{"host":"wsl"}})
                    .to_string();
            reading
                .sinks
                .lock()
                .unwrap()
                .retain(|sink| sink.send(disconnected.clone()).is_ok());
            for (_, reply) in reading.pending.lock().unwrap().drain() {
                let _ = reply.send(Err(RpcError::new(-32000, "Connexion WSL interrompue")));
            }
            writer.abort();
            let _ = child.wait().await;
        });
        tokio::time::timeout(
            std::time::Duration::from_secs(10),
            proxy.request("hello", json!({})),
        )
        .await
        .map_err(|_| RpcError::new(-32000, "Le moteur WSL ne répond pas"))??;
        Ok(proxy)
    }

    pub fn alive(&self) -> bool {
        !self.closed.load(Ordering::SeqCst)
    }
    pub fn login_sink(&self, id: &str, sink: &mpsc::UnboundedSender<String>) {
        self.login_sinks
            .lock()
            .unwrap()
            .insert(id.into(), sink.clone());
    }
    pub fn subscribe(&self, sink: &mpsc::UnboundedSender<String>) {
        let mut sinks = self.sinks.lock().unwrap();
        sinks.retain(|s| !s.is_closed());
        if !sinks.iter().any(|s| s.same_channel(sink)) {
            sinks.push(sink.clone());
        }
    }
    pub async fn request(&self, method: &str, params: Value) -> Result<Value, RpcError> {
        if !self.alive() {
            return Err(RpcError::new(-32000, "WSL déconnecté"));
        }
        let id = self.next.fetch_add(1, Ordering::Relaxed);
        let (send, receive) = oneshot::channel();
        self.pending.lock().unwrap().insert(id, send);
        if self
            .input
            .send(json!({"jsonrpc":"2.0", "id":id, "method":method, "params":params}).to_string())
            .is_err()
        {
            self.pending.lock().unwrap().remove(&id);
            return Err(RpcError::new(-32000, "WSL déconnecté"));
        }
        receive
            .await
            .map_err(|_| RpcError::new(-32000, "WSL déconnecté"))?
    }
}

pub fn prefix(value: &mut Value) {
    if let Some(run) = value["run"].as_str() {
        value["run"] = json!(format!("wsl:{run}"));
    }
    if let Some(path) = value["path"].as_str() {
        value["path"] = json!(format!(
            "\\\\wsl.localhost\\Ubuntu{}",
            path.replace('/', "\\")
        ));
    }
    if value.is_object() {
        value["host"] = json!("wsl");
    }
}
fn error(e: impl std::fmt::Display) -> RpcError {
    RpcError::new(-32000, e.to_string())
}
