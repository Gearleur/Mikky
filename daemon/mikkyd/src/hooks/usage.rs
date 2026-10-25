//! Claude's subscription usage (2026-10-25): its status line receives
//! `rate_limits` (https://code.claude.com/docs/en/statusline), the 5-hour
//! and 7-day windows with `used_percentage` and `resets_at` (Unix seconds).
//! `mikky-hook StatusLine` reports them here (`usage.report`); the screens
//! read the latest (`usage.get`, notification `usage.changed`). In memory:
//! the next status line refreshes it after a restart.

use std::sync::Mutex;

use serde_json::{Value, json};
use tokio::sync::broadcast;

pub struct Usage {
    latest: Mutex<Value>,
    pub changes: broadcast::Sender<()>,
}

impl Default for Usage {
    fn default() -> Self {
        Self {
            latest: Mutex::new(json!({})),
            changes: broadcast::channel(16).0,
        }
    }
}

impl Usage {
    /// The latest reading of each agent: `{"claude": {fiveHour, sevenDay,
    /// at, sessionId}}`, each window `{usedPercent, resetsAt}` (resetsAt in
    /// Unix seconds) or absent.
    pub fn get(&self) -> Value {
        self.latest.lock().unwrap().clone()
    }

    /// A status line's `rate_limits` for Claude. Nothing to keep (no
    /// window, not a subscription): ignored. A reading equal to the last
    /// one is not told again.
    pub fn report(&self, session: &str, limits: &Value) {
        let window = |name: &str| {
            let w = &limits[name];
            let used = w["used_percentage"].as_f64()?;
            Some(
                json!({"usedPercent": used.clamp(0.0, 100.0), "resetsAt": w["resets_at"].as_i64()}),
            )
        };
        let (five, seven) = (window("five_hour"), window("seven_day"));
        if five.is_none() && seven.is_none() {
            return;
        }
        let mut latest = self.latest.lock().unwrap();
        let same = latest["claude"]["fiveHour"] == five.clone().unwrap_or(Value::Null)
            && latest["claude"]["sevenDay"] == seven.clone().unwrap_or(Value::Null);
        latest["claude"] = json!({
            "fiveHour": five,
            "sevenDay": seven,
            "sessionId": session,
            "at": chrono::Utc::now().to_rfc3339(),
        });
        drop(latest);
        if !same {
            let _ = self.changes.send(());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_the_windows_and_tells_only_a_change() {
        let usage = Usage::default();
        let mut changes = usage.changes.subscribe();
        usage.report("s", &json!({}));
        assert_eq!(usage.get(), json!({}));
        let limits = json!({
            "five_hour": {"used_percentage": 23.5, "resets_at": 1738425600},
            "seven_day": {"used_percentage": 141.0, "resets_at": 1738857600},
        });
        usage.report("s", &limits);
        let claude = &usage.get()["claude"];
        assert_eq!(
            claude["fiveHour"],
            json!({"usedPercent": 23.5, "resetsAt": 1738425600})
        );
        assert_eq!(claude["sevenDay"]["usedPercent"], 100.0);
        assert!(changes.try_recv().is_ok());
        usage.report("s", &limits);
        assert!(changes.try_recv().is_err());
        usage.report("s", &json!({"five_hour": {"used_percentage": 30}}));
        assert!(usage.get()["claude"]["sevenDay"].is_null());
        assert!(changes.try_recv().is_ok());
    }
}
