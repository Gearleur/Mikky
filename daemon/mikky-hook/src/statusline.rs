//! `mikky-hook StatusLine`: Claude Code's status line command
//! (https://code.claude.com/docs/en/statusline), installed only when the
//! user asks for it. It prints a short line for Claude's footer at once,
//! then hands the subscription's `rate_limits` to `mikkyd`
//! (`usage.report`) so that Mikky knows the 5-hour and weekly usage. No
//! `mikkyd`: the line is still printed, nothing else happens.

use std::io::{Read, Write};
use std::sync::mpsc;
use std::time::Duration;

use serde_json::{Value, json};

/// Claude cancels a status line still running at its next update: stay
/// short.
const REPORT: Duration = Duration::from_millis(300);

pub fn run() {
    let mut raw = Vec::new();
    if std::io::stdin()
        .take(super::MAX_INPUT)
        .read_to_end(&mut raw)
        .is_err()
    {
        return;
    }
    let raw = raw.strip_prefix(&[0xEF, 0xBB, 0xBF][..]).unwrap_or(&raw);
    let Ok(payload) = serde_json::from_slice::<Value>(raw) else {
        return;
    };
    let mut stdout = std::io::stdout();
    let _ = writeln!(stdout, "{}", line(&payload));
    let _ = stdout.flush();
    let limits = &payload["rate_limits"];
    if !limits.is_object() {
        return;
    }
    let params = json!({
        "sessionId": payload["session_id"],
        "rateLimits": {"five_hour": limits["five_hour"], "seven_day": limits["seven_day"]},
    });
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let _ = tx.send(super::talk_call("usage.report", params, false, REPORT));
    });
    let _ = rx.recv_timeout(REPORT);
}

/// The model, then each window's use: `Opus · 5 h 24 % · 7 j 41 %`.
fn line(payload: &Value) -> String {
    let mut parts = Vec::new();
    if let Some(model) = payload["model"]["display_name"].as_str() {
        parts.push(model.to_owned());
    }
    for (key, name) in [("five_hour", "5 h"), ("seven_day", "7 j")] {
        if let Some(used) = payload["rate_limits"][key]["used_percentage"].as_f64() {
            parts.push(format!("{name} {} %", used.round()));
        }
    }
    if parts.is_empty() {
        parts.push("Mikky".into());
    }
    parts.join(" · ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_line_says_the_model_and_the_windows_it_has() {
        let full = json!({
            "model": {"display_name": "Opus"},
            "rate_limits": {
                "five_hour": {"used_percentage": 23.5, "resets_at": 1738425600},
                "seven_day": {"used_percentage": 41.2, "resets_at": 1738857600},
            },
        });
        assert_eq!(line(&full), "Opus · 5 h 24 % · 7 j 41 %");
        assert_eq!(
            line(&json!({"model": {"display_name": "Sonnet"}})),
            "Sonnet"
        );
        assert_eq!(line(&json!({})), "Mikky");
    }
}
