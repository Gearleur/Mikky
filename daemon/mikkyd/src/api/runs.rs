//! `run.*` and `runs.*`: the agents `mikkyd` runs, each an ACP adapter in
//! its own job.

use std::sync::atomic::Ordering;
use std::time::Duration;

use mikky_acp::{Run, RunEvent, Traffic};
use tokio::process::Child;

use super::notification;
use super::prelude::*;
use crate::system::job::Job;
use crate::system::target::{self, Host};

/// One agent `mikkyd` runs.
pub(super) struct Agent {
    provider: String,
    host: String,
    cwd: String,
    /// PID of the ACP adapter started on this daemon's host, not of its children.
    adapter_pid: Option<u32>,
    run: Run,
    child: tokio::sync::Mutex<Child>,
    job: Option<Job>,
}

impl Daemon {
    /// [session] is one of the agents `mikkyd` runs.
    pub(super) fn owns_session(&self, session: &str) -> bool {
        self.agents
            .lock()
            .unwrap()
            .values()
            .any(|a| a.run.session_id().as_deref() == Some(session))
    }
}

pub(super) async fn dispatch(
    daemon: &Arc<Daemon>,
    method: &str,
    params: &Value,
    out: &Out,
) -> RpcResult {
    match method {
        "runs.stopAll" => {
            daemon.stop_all().await;
            if daemon.allow_wsl {
                daemon.wsl(out).await?.request(method, json!({})).await?;
            }
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
                    crate::system::wsl::prefix(item);
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
        _ => Err(not_found(method)),
    }
}

/// Starts an adapter (the app says which: `executable args` in `cwd` on
/// `host`, with `env`) and puts it in its own job.
pub(super) fn start(daemon: &Arc<Daemon>, params: &Value) -> Result<Value, RpcError> {
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
pub(super) async fn stop(a: &Agent) {
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
