//! `tools.*`: the adapters on this machine — installed, signed in, launched.

use std::sync::Arc;

use mikky_acp::RpcError;
use serde_json::Value;
use tokio::sync::mpsc;

use super::runs::start;
use super::{Daemon, not_found, str_param};

pub(super) async fn dispatch(
    daemon: &Arc<Daemon>,
    method: &str,
    params: &Value,
    out: &mpsc::UnboundedSender<String>,
) -> Result<Value, RpcError> {
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
        "tools.auth" => crate::tools::auth(str_param(params, "provider")?).await,
        "tools.launch" => {
            let _prepare = daemon.preparing.lock().await;
            crate::tools::prepare().await?;
            let command =
                crate::tools::launch(str_param(params, "provider")?, str_param(params, "cwd")?)
                    .await?;
            start(daemon, &command)
        }
        _ => Err(not_found(method)),
    }
}
