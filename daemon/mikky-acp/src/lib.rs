//! The ACP side of `mikkyd`: JSON-RPC with an agent adapter ([Connection])
//! and one agent session on top of it ([Run]).
//!
//! Raw JSON on purpose: every message is handed on as is to the app, whose
//! `AcpReader` (Dart, tested with real recordings) builds the session.

mod connection;
mod run;

pub use connection::{Connection, Event, RpcError, TrafficHook};
pub use run::{Run, RunEvent, Sink, Traffic};
