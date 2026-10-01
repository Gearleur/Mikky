//! Where an agent runs (MVP spec §3.4): Windows itself, or a WSL
//! distribution through `wsl.exe` (until WSL has its own `mikkyd`, R2).

use std::process::Stdio;

use tokio::process::Command;

pub enum Host {
    Windows,
    Wsl { distro: String },
}

/// The command that starts `executable args` on `host`, in `cwd` (a path of
/// that host), with `env` added. Pipes for ACP; stderr dropped (adapters log
/// there); no console window; the process dies with its `Child`.
pub fn command(
    host: &Host,
    executable: &str,
    args: &[String],
    cwd: &str,
    env: &[(String, String)],
) -> Command {
    let mut c = match host {
        Host::Windows if executable.ends_with(".cmd") => {
            let mut c = Command::new("cmd");
            c.arg("/c").arg(executable).args(args);
            c
        }
        Host::Windows => {
            let mut c = Command::new(executable);
            c.args(args);
            c
        }
        Host::Wsl { distro } => {
            // A login shell: without it, `claude` and `codex` may resolve to
            // the Windows ones (WSL appends the Windows PATH).
            let exports: String = env
                .iter()
                .map(|(k, v)| format!("export {k}={}; ", shell_quote(v)))
                .collect();
            let line = std::iter::once(executable)
                .chain(args.iter().map(String::as_str))
                .map(shell_quote)
                .collect::<Vec<_>>()
                .join(" ");
            let mut c = Command::new("wsl.exe");
            c.args(["-d", distro, "--cd", cwd, "--", "bash", "-lc"])
                .arg(format!("{exports}exec {line}"));
            c
        }
    };
    if let Host::Windows = host {
        c.current_dir(cwd).envs(env.iter().map(|(k, v)| (k, v)));
    }
    c.stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    #[cfg(windows)]
    c.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    #[cfg(unix)]
    c.process_group(0);
    c
}

/// Single-quotes `s` for bash.
pub fn shell_quote(s: &str) -> String {
    let plain = !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || "_./:=@%+-".contains(c));
    if plain {
        s.to_owned()
    } else {
        format!("'{}'", s.replace('\'', r"'\''"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quotes_only_what_needs_it() {
        assert_eq!(
            shell_quote("/home/me/.local/bin/node"),
            "/home/me/.local/bin/node"
        );
        assert_eq!(shell_quote("a b"), "'a b'");
        assert_eq!(shell_quote("it's"), r"'it'\''s'");
        assert_eq!(shell_quote(""), "''");
    }

    #[test]
    fn wsl_runs_a_login_shell_in_the_folder() {
        let c = command(
            &Host::Wsl {
                distro: "Ubuntu".into(),
            },
            "/opt/node",
            &["index.js".into()],
            "/tmp/x",
            &[("CLAUDE_CODE_EXECUTABLE".into(), "/usr/bin/claude".into())],
        );
        let c = c.as_std();
        assert_eq!(c.get_program(), "wsl.exe");
        let args: Vec<_> = c
            .get_args()
            .map(|a| a.to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            args,
            [
                "-d",
                "Ubuntu",
                "--cd",
                "/tmp/x",
                "--",
                "bash",
                "-lc",
                "export CLAUDE_CODE_EXECUTABLE=/usr/bin/claude; exec /opt/node index.js"
            ]
        );
    }
}
