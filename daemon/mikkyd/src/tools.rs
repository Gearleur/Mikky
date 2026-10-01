//! Installation and tool discovery belong to the machine running the agent.
use crate::target::{self, Host};
use mikky_acp::RpcError;
use serde_json::{Value, json};
use std::{path::PathBuf, process::Stdio};
use tokio::process::Command;

pub const CLAUDE: &str = "@agentclientprotocol/claude-agent-acp@0.84.0";
pub const CODEX: &str = "@agentclientprotocol/codex-acp@2.0.0";

pub fn home() -> PathBuf {
    std::env::var_os(if cfg!(windows) { "USERPROFILE" } else { "HOME" })
        .map(PathBuf::from)
        .unwrap_or_default()
}
fn directory() -> PathBuf {
    if cfg!(windows) {
        std::env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(home)
            .join("Mikky")
    } else {
        home().join(".local/share/mikky")
    }
}
fn node() -> String {
    if cfg!(windows) {
        "node".into()
    } else {
        directory()
            .join("node/bin/node")
            .to_string_lossy()
            .into_owned()
    }
}
fn adapter(provider: &str) -> Result<PathBuf, RpcError> {
    if !matches!(provider, "claude" | "codex") {
        return Err(RpcError::new(-32602, "Unknown provider"));
    }
    Ok(directory()
        .join("acp/node_modules/@agentclientprotocol")
        .join(format!(
            "{provider}-{}",
            if provider == "claude" {
                "agent-acp"
            } else {
                "acp"
            }
        ))
        .join("dist/index.js"))
}

pub fn command(exe: &str, args: &[String]) -> Command {
    let mut cmd = target::command(&Host::Windows, exe, args, &home().to_string_lossy(), &[]);
    cmd.stdin(Stdio::null()).stderr(Stdio::piped());
    cmd
}
async fn output(exe: &str, args: &[&str]) -> Result<std::process::Output, RpcError> {
    tokio::time::timeout(
        std::time::Duration::from_secs(20),
        command(exe, &args.iter().map(|s| s.to_string()).collect::<Vec<_>>()).output(),
    )
    .await
    .map_err(|_| RpcError::new(-32000, "L’outil ne répond pas"))?
    .map_err(|e| RpcError::new(-32000, e.to_string()))
}

pub async fn status() -> Value {
    let version = output(&node(), &["--version"])
        .await
        .ok()
        .filter(|r| r.status.success())
        .map(|r| String::from_utf8_lossy(&r.stdout).trim().to_owned());
    let major = version
        .as_deref()
        .unwrap_or("")
        .trim_start_matches('v')
        .split('.')
        .next()
        .and_then(|s| s.parse::<u32>().ok())
        .unwrap_or(0);
    let adapters = adapter("claude").unwrap().exists() && adapter("codex").unwrap().exists();
    json!({"node":major >= 22, "adapters":adapters, "nodeVersion":version, "ready":major >= 22 && adapters})
}

pub async fn prepare() -> Result<(), RpcError> {
    let status = status().await;
    if status["ready"] == true {
        return Ok(());
    }
    let dir = directory();
    tokio::fs::create_dir_all(dir.join("acp"))
        .await
        .map_err(|e| RpcError::new(-32000, e.to_string()))?;
    let mut cmd = if cfg!(windows) {
        if status["node"] != true {
            return Err(RpcError::new(
                -32000,
                "Node.js 22 ou plus est nécessaire sous Windows",
            ));
        }
        command(
            "npm.cmd",
            &[
                "install".into(),
                "--prefix".into(),
                dir.join("acp").to_string_lossy().into_owned(),
                "--no-fund".into(),
                "--no-audit".into(),
                CLAUDE.into(),
                CODEX.into(),
            ],
        )
    } else {
        let script = format!(
            "set -e\nD={}\nV=v24.19.0\nmkdir -p \"$D\"\ncd \"$D\"\nif [ ! -x node/bin/node ]; then\n curl -fsSL \"https://nodejs.org/dist/$V/node-$V-linux-x64.tar.xz\" -o node.tar.xz\n curl -fsSL \"https://nodejs.org/dist/$V/SHASUMS256.txt\" | grep \" node-$V-linux-x64.tar.xz$\" | sed \"s/node-$V-linux-x64.tar.xz/node.tar.xz/\" | sha256sum -c -\n mkdir -p node\n tar -xJf node.tar.xz -C node --strip-components=1\n rm node.tar.xz\nfi\nPATH=\"$D/node/bin:$PATH\" npm install --prefix acp --no-fund --no-audit {CLAUDE} {CODEX}\n",
            target::shell_quote(&dir.to_string_lossy())
        );
        command("bash", &["-lc".into(), script])
    };
    let result = tokio::time::timeout(std::time::Duration::from_secs(300), cmd.output())
        .await
        .map_err(|_| RpcError::new(-32000, "Installation trop longue, réessaie"))?
        .map_err(|e| RpcError::new(-32000, e.to_string()))?;
    if !result.status.success() {
        return Err(RpcError::new(
            -32000,
            format!(
                "Installation des adaptateurs impossible : {}",
                String::from_utf8_lossy(&result.stderr)
            ),
        ));
    }
    if self::status().await["ready"] != true {
        return Err(RpcError::new(
            -32000,
            "Les adaptateurs ne sont pas prêts après l’installation",
        ));
    }
    Ok(())
}

pub async fn claude() -> String {
    let native = home().join(if cfg!(windows) {
        ".local/bin/claude.exe"
    } else {
        ".local/bin/claude"
    });
    if native.exists() {
        return native.to_string_lossy().into_owned();
    }
    if cfg!(windows) {
        "claude".into()
    } else {
        output("bash", &["-lc", "command -v claude"])
            .await
            .ok()
            .map(|r| String::from_utf8_lossy(&r.stdout).trim().to_owned())
            .filter(|s| s.starts_with('/'))
            .unwrap_or("claude".into())
    }
}

pub async fn launch(provider: &str, cwd: &str) -> Result<Value, RpcError> {
    let script = adapter(provider)?;
    let cwd = if cfg!(unix) && cwd.as_bytes().get(1) == Some(&b':') {
        format!(
            "/mnt/{}/{}",
            cwd[..1].to_lowercase(),
            cwd[3..].replace('\\', "/")
        )
    } else if cfg!(unix) && cwd.starts_with("\\\\wsl.localhost\\Ubuntu\\") {
        cwd.trim_start_matches("\\\\wsl.localhost\\Ubuntu")
            .replace('\\', "/")
    } else {
        cwd.to_owned()
    };
    let mut env = json!({});
    if provider == "claude" {
        env["CLAUDE_CODE_EXECUTABLE"] = json!(claude().await);
    }
    Ok(
        json!({"provider":provider, "host":"windows", "executable":node(), "args":[script], "cwd":cwd, "env":env}),
    )
}

pub async fn auth(provider: &str) -> Result<Value, RpcError> {
    adapter(provider)?;
    let exe = if provider == "claude" {
        claude().await
    } else if cfg!(windows) {
        "codex.cmd".into()
    } else {
        "codex".into()
    };
    let args: &[&str] = if provider == "claude" {
        &["auth", "status"]
    } else {
        &["login", "status"]
    };
    let result = if cfg!(unix) {
        output(
            "bash",
            &[
                "-lc",
                &format!("{} {}", target::shell_quote(&exe), args.join(" ")),
            ],
        )
        .await
    } else {
        output(&exe, args).await
    };
    let Ok(r) = result else {
        return Ok(json!({"installed":false,"loggedIn":false}));
    };
    let stdout = String::from_utf8_lossy(&r.stdout);
    if provider == "claude" {
        let status = stdout
            .find('{')
            .and_then(|i| serde_json::from_str::<Value>(&stdout[i..]).ok());
        return Ok(match status {
            Some(s) => {
                json!({"installed":true,"loggedIn":s["loggedIn"] == true,"plan":s["subscriptionType"]})
            }
            None => {
                json!({"installed":r.status.code() != Some(127) && !stdout.trim().is_empty(),"loggedIn":false})
            }
        });
    }
    let text = format!("{stdout}\n{}", String::from_utf8_lossy(&r.stderr));
    let plan = text
        .split("Logged in using ")
        .nth(1)
        .and_then(|s| s.split_whitespace().next());
    Ok(
        json!({"installed":r.status.code() != Some(127) && !text.contains("command not found"),"loggedIn":plan.is_some(),"plan":plan}),
    )
}
