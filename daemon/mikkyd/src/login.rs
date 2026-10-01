//! Ephemeral login output goes to its requesting screen only, never to disk.
use crate::{job::Job, tools};
use mikky_acp::RpcError;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};
use tokio::{
    io::{AsyncRead, AsyncReadExt},
    sync::{mpsc, oneshot},
};

#[derive(Default, Clone)]
pub struct Logins(Arc<Mutex<HashMap<String, oneshot::Sender<()>>>>);
impl Logins {
    pub async fn start(
        &self,
        provider: &str,
        id: String,
        out: mpsc::UnboundedSender<String>,
    ) -> Result<Value, RpcError> {
        if !matches!(provider, "claude" | "codex") {
            return Err(RpcError::new(-32602, "Unknown provider"));
        }
        let exe = if provider == "claude" {
            tools::claude().await
        } else if cfg!(windows) {
            "codex.cmd".into()
        } else {
            "codex".into()
        };
        let args: Vec<String> = if provider == "claude" {
            vec!["auth".into(), "login".into()]
        } else {
            vec!["login".into(), "--device-auth".into()]
        };
        let mut cmd = if cfg!(unix) {
            let line = format!("{} {}", crate::target::shell_quote(&exe), args.join(" "));
            tools::command(
                "script",
                &[
                    "-q".into(),
                    "-f".into(),
                    "-c".into(),
                    line,
                    "/dev/null".into(),
                ],
            )
        } else {
            tools::command(&exe, &args)
        };
        let mut child = cmd
            .spawn()
            .map_err(|e| RpcError::new(-32000, e.to_string()))?;
        let job = child.id().and_then(Job::for_process);
        let (cancel, cancelled) = oneshot::channel();
        if let Some(previous) = self.0.lock().unwrap().insert(id.clone(), cancel) {
            let _ = previous.send(());
        }
        let stdout = tokio::spawn(pump(child.stdout.take().unwrap(), id.clone(), out.clone()));
        let stderr = tokio::spawn(pump(child.stderr.take().unwrap(), id.clone(), out.clone()));
        let logins = self.clone();
        tokio::spawn(async move {
            let ok = tokio::select! {
                result = child.wait() => result.is_ok_and(|s| s.success()),
                _ = cancelled => { let _ = child.start_kill(); false },
                _ = out.closed() => { let _ = child.start_kill(); false },
            };
            stdout.abort();
            stderr.abort();
            drop(job);
            logins.0.lock().unwrap().remove(&id);
            let _ = out.send(
                json!({"jsonrpc":"2.0","method":"login.done","params":{"login":id,"ok":ok}})
                    .to_string(),
            );
        });
        Ok(Value::Null)
    }
    pub fn cancel(&self, id: &str) {
        if let Some(cancel) = self.0.lock().unwrap().remove(id) {
            let _ = cancel.send(());
        }
    }
}
async fn pump(mut input: impl AsyncRead + Unpin, id: String, out: mpsc::UnboundedSender<String>) {
    let mut buffer = [0; 4096];
    while let Ok(n) = input.read(&mut buffer).await {
        if n == 0 {
            break;
        }
        if out.send(json!({"jsonrpc":"2.0","method":"login.output","params":{"login":id,"text":String::from_utf8_lossy(&buffer[..n])}}).to_string()).is_err() { break; }
    }
}
