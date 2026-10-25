//! `hook.event` (from `mikky-hook`) and `hooks.*`: Claude Code's and
//! Codex's hooks, and installing them.

use super::prelude::*;

pub(super) async fn dispatch(
    daemon: &Arc<Daemon>,
    method: &str,
    params: &Value,
    out: &Out,
) -> RpcResult {
    match method {
        "hooks.messages.list" => Ok(daemon.hooks.messages.list()),
        "hooks.messages.send" => {
            let agent = str_param(params, "agent")?;
            if !matches!(agent, "claude" | "codex")
                || params["host"].as_str().is_some_and(|h| h != "windows")
            {
                return Err(RpcError::new(
                    -32602,
                    "Seules les sessions Claude et Codex sous Windows sont prises en charge",
                ));
            }
            let session = str_param(params, "sessionId")?;
            if daemon.owns_session(session) {
                return Err(RpcError::new(
                    -32602,
                    "Cette session est pilotée par Mikky : utilise le steering",
                ));
            }
            daemon.hooks.messages.enqueue_for(
                agent,
                session,
                str_param(params, "id")?,
                str_param(params, "text")?,
            )
        }
        "hooks.messages.ack" => Ok(json!(daemon.hooks.messages.acknowledge(
            str_param(params, "sessionId")?,
            str_param(params, "delivery")?
        ))),
        "hook.event" => {
            let payload = params.get("payload").cloned().unwrap_or(Value::Null);
            // An agent Mikky runs in WSL calls the same hooks there.
            let in_wsl = crate::hooks::from_wsl(&payload)
                && daemon
                    .wsl_owns_session(payload["session_id"].as_str().unwrap_or_default())
                    .await;
            let own = |session: &str| in_wsl || daemon.owns_session(session);
            let out = out.clone();
            Ok(daemon
                .hooks
                .event(&payload, own, async move { out.closed().await })
                .await)
        }
        "hooks.list" => Ok(daemon.hooks.list()),
        "usage.get" => Ok(daemon.hooks.usage.get()),
        "usage.report" => {
            let limits = params.get("rateLimits").cloned().unwrap_or(Value::Null);
            daemon
                .hooks
                .usage
                .report(params["sessionId"].as_str().unwrap_or_default(), &limits);
            Ok(Value::Null)
        }
        "hooks.answer" => {
            let id = params
                .get("id")
                .and_then(Value::as_u64)
                .ok_or_else(|| RpcError::new(-32602, "missing id"))?;
            Ok(json!(daemon.hooks.answer(
                id,
                params.get("decision").and_then(Value::as_str),
                params.get("answers").filter(|a| !a.is_null()),
            )))
        }
        "hooks.origin" => Ok(daemon.hooks.origin(str_param(params, "sessionId")?)),
        "hooks.status" => Ok(crate::hooks::settings::status(
            hook_tool(params)?,
            given_hook(params),
        )),
        "hooks.preview" if params["part"] == "statusLine" => crate::hooks::settings::preview_line(
            params["install"].as_bool().unwrap_or(true),
            given_hook(params),
        )
        .map_err(|e| RpcError::new(-32000, e)),
        "hooks.write" if params["part"] == "statusLine" => crate::hooks::settings::write_line(
            params["install"].as_bool().unwrap_or(true),
            str_param(params, "fingerprint")?,
            given_hook(params),
        )
        .map_err(|e| RpcError::new(-32000, e)),
        "hooks.preview" => crate::hooks::settings::preview(
            hook_tool(params)?,
            params["install"].as_bool().unwrap_or(true),
            given_hook(params),
        )
        .map_err(|e| RpcError::new(-32000, e)),
        "hooks.write" => crate::hooks::settings::write(
            hook_tool(params)?,
            params["install"].as_bool().unwrap_or(true),
            str_param(params, "fingerprint")?,
            given_hook(params),
        )
        .map_err(|e| RpcError::new(-32000, e)),
        _ => Err(not_found(method)),
    }
}

/// The relay the hooks call when it is not this engine's: `hook` (the
/// Windows one, for Claude or Codex in WSL).
fn given_hook(params: &Value) -> Option<std::path::PathBuf> {
    params["hook"].as_str().map(std::path::PathBuf::from)
}

/// Whose hooks: `tool` is `claude` (the default) or `codex`.
fn hook_tool(params: &Value) -> Result<crate::hooks::settings::Tool, RpcError> {
    let name = params["tool"].as_str().unwrap_or("claude");
    crate::hooks::settings::Tool::named(name)
        .ok_or_else(|| RpcError::new(-32602, format!("unknown tool {name}")))
}
