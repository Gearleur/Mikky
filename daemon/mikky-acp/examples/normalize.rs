//! Offline fixture reader; no processes, network or credentials.
use std::io::{self, BufRead};
fn main() {
    let mut reader = mikky_acp::reader::Reader::default();
    for line in io::stdin().lock().lines() {
        let line = line.unwrap();
        if line.trim().is_empty() {
            continue;
        }
        let record: serde_json::Value = serde_json::from_str(&line).unwrap();
        let events = reader.read(
            &record["msg"],
            record["dir"] == "out",
            "2026-09-30T00:00:00Z",
        );
        println!("{}", serde_json::to_string(&events).unwrap());
    }
}
