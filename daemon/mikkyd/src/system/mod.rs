//! What touches the machine: where agents run (Windows or WSL), the job
//! object holding them, the endpoint in the credential store, the startup
//! task, and the bridge to the Linux engine in WSL.

pub mod autostart;
pub mod endpoint;
pub mod job;
#[cfg(unix)]
pub mod linux;
pub mod target;
pub mod wsl;
