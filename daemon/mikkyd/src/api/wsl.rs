//! The requests for WSL (a `wsl` host, a `wsl:` run, a path in WSL's
//! share) go to the Linux engine there, their ids and paths translated.

use std::sync::Arc;

use mikky_acp::RpcError;
use serde_json::{Value, json};
use tokio::sync::mpsc;

use super::{Daemon, str_param};

/// [params] are for the Linux engine in WSL.
pub(super) fn targets_wsl(daemon: &Daemon, params: &Value) -> bool {
    daemon.allow_wsl
        && (params["host"] == "wsl"
            || params["run"]
                .as_str()
                .is_some_and(|s| s.starts_with("wsl:"))
            || params["path"]
                .as_str()
                .is_some_and(|s| s.starts_with("\\\\wsl.localhost\\Ubuntu\\")))
}

/// Sends the request to the Linux engine, as it would come to it directly.
pub(super) async fn forward(
    daemon: &Arc<Daemon>,
    method: &str,
    params: &Value,
    out: &mpsc::UnboundedSender<String>,
) -> Result<Value, RpcError> {
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
        crate::system::wsl::prefix(&mut result);
    }
    if method == "sessions.read" {
        crate::system::wsl::prefix(&mut result["session"]);
    }
    Ok(result)
}
