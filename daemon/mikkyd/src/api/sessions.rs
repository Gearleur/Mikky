//! `sessions.*` (Claude's and Codex's session files) and `state.*` (the
//! app's metadata in SQLite).

use super::prelude::*;

pub(super) async fn dispatch(
    daemon: &Arc<Daemon>,
    method: &str,
    params: &Value,
    out: &Out,
) -> RpcResult {
    match method {
        "sessions.list" => {
            let mut list = daemon.sessions.list();
            if daemon.allow_wsl
                && let Ok(proxy) = daemon.wsl(out).await
                && let Ok(Value::Array(mut remote)) = proxy.request(method, json!({})).await
            {
                for item in &mut remote {
                    crate::system::wsl::prefix(item);
                }
                list.as_array_mut().unwrap().extend(remote);
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
        _ => Err(not_found(method)),
    }
}
