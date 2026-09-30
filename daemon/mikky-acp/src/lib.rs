//! The ACP side of `mikkyd`: we start the adapter ourselves (to keep it in a
//! job object, or to run it in WSL) and hand its pipes to the official SDK
//! (`agent-client-protocol`), which does the JSON-RPC.

use std::path::Path;
use std::process::Stdio;

pub use agent_client_protocol as acp;
use tokio::process::{Child, ChildStdin, ChildStdout, Command};
use tokio_util::compat::{Compat, TokioAsyncReadCompatExt, TokioAsyncWriteCompatExt};

/// The adapter's stdin / stdout, ready for `connect_with`.
pub type Transport = acp::ByteStreams<Compat<ChildStdin>, Compat<ChildStdout>>;

/// Starts `program args` in `cwd` with piped stdin / stdout. Adapters log on
/// stderr: dropped, so the pipe never fills. The process dies with [Child].
pub fn spawn(program: &str, args: &[&str], cwd: &Path) -> std::io::Result<(Child, Transport)> {
    let mut child = Command::new(program)
        .args(args)
        .current_dir(cwd)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()?;
    let stdin = child.stdin.take().expect("stdin is piped");
    let stdout = child.stdout.take().expect("stdout is piped");
    Ok((child, acp::ByteStreams::new(stdin.compat_write(), stdout.compat())))
}
