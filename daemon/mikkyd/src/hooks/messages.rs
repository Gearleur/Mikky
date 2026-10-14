//! Bounded, in-memory user messages for external Claude and Codex sessions.
//! A hook leases a batch; only its acknowledgement after stdout is flushed
//! removes it from the waiting queue. A failed relay leaves it available.
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use mikky_acp::RpcError;
use serde_json::{Value, json};
use tokio::sync::broadcast;

const MAX_MESSAGES: usize = 256;
const MAX_SESSION_MESSAGES: usize = 16;
const MAX_TEXT: usize = 4000;
const MAX_SESSION_BYTES: usize = 6000;
const LEASE: Duration = Duration::from_secs(2);

#[derive(Default)]
struct State {
    messages: Vec<Value>,
    leases: HashMap<String, (String, Vec<String>, Instant)>,
}

pub struct Messages {
    state: Mutex<State>,
    pub changes: broadcast::Sender<()>,
}

impl Default for Messages {
    fn default() -> Self {
        Self {
            state: Mutex::new(State::default()),
            changes: broadcast::channel(16).0,
        }
    }
}

impl Messages {
    pub fn list(&self) -> Value {
        json!(self.state.lock().unwrap().messages)
    }

    #[cfg(test)]
    pub fn enqueue(&self, session: &str, id: &str, text: &str) -> Result<Value, RpcError> {
        self.enqueue_for("claude", session, id, text)
    }

    pub fn enqueue_for(
        &self,
        agent: &str,
        session: &str,
        id: &str,
        text: &str,
    ) -> Result<Value, RpcError> {
        let invalid = |message| RpcError::new(-32602, message);
        if !matches!(agent, "claude" | "codex")
            || session.is_empty()
            || session.len() > 128
            || id.is_empty()
            || id.len() > 96
            || !id.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-')
        {
            return Err(invalid("Identifiant de message ou de session invalide"));
        }
        if text.trim().is_empty()
            || text.len() > MAX_TEXT
            || json!({"id":id,"text":text}).to_string().len() + 20 > 9000
        {
            return Err(invalid("Message vide ou trop long (4000 octets maximum)"));
        }
        let mut state = self.state.lock().unwrap();
        if let Some(m) = state.messages.iter().find(|m| m["id"] == id) {
            return if m["text"] == text && m["sessionId"] == session && m["agent"] == agent {
                Ok(m.clone())
            } else {
                Err(invalid("Cet identifiant désigne déjà un autre message"))
            };
        }
        let waiting: Vec<_> = state
            .messages
            .iter()
            .filter(|m| m["sessionId"] == session && m["state"] == "waitingForTool")
            .collect();
        let bytes: usize = waiting
            .iter()
            .map(|m| m["text"].as_str().unwrap_or_default().len())
            .sum();
        if waiting.len() >= MAX_SESSION_MESSAGES || bytes + text.len() > MAX_SESSION_BYTES {
            return Err(invalid(
                "La file de cette session est pleine. Attends la transmission des messages.",
            ));
        }
        if state.messages.len() >= MAX_MESSAGES {
            let Some(i) = state
                .messages
                .iter()
                .position(|m| m["state"] == "delivered")
            else {
                return Err(invalid("La file de messages est pleine"));
            };
            state.messages.remove(i);
        }
        let message = json!({"id":id,"agent":agent,"sessionId":session,"text":text,"state":"waitingForTool","at":chrono::Utc::now().to_rfc3339()});
        state.messages.push(message.clone());
        drop(state);
        let _ = self.changes.send(());
        Ok(message)
    }

    #[cfg(test)]
    pub fn offer(&self, session: &str) -> Value {
        self.offer_for("claude", session)
    }

    pub fn offer_for(&self, agent: &str, session: &str) -> Value {
        let mut state = self.state.lock().unwrap();
        let now = Instant::now();
        state.leases.retain(|_, (_, _, until)| *until > now);
        if state.leases.contains_key(session) {
            return Value::Null;
        }
        let mut messages = vec![];
        let mut bytes = 0;
        for m in state.messages.iter().filter(|m| {
            m["agent"] == agent && m["sessionId"] == session && m["state"] == "waitingForTool"
        }) {
            bytes += json!({"id":m["id"],"text":m["text"]}).to_string().len() + 20;
            if bytes > 9000 {
                break;
            }
            messages.push(m.clone());
        }
        if messages.is_empty() {
            return Value::Null;
        }
        let delivery = crate::system::endpoint::new_token();
        let ids = messages
            .iter()
            .filter_map(|m| m["id"].as_str().map(str::to_owned))
            .collect();
        state
            .leases
            .insert(session.into(), (delivery.clone(), ids, now + LEASE));
        json!({"delivery":delivery,"messages":messages})
    }

    pub fn acknowledge(&self, session: &str, delivery: &str) -> bool {
        let mut state = self.state.lock().unwrap();
        let Some((token, ids, _)) = state.leases.get(session) else {
            return false;
        };
        if token != delivery {
            return false;
        }
        let ids = ids.clone();
        state.leases.remove(session);
        for message in &mut state.messages {
            if message["sessionId"] == session && ids.iter().any(|id| message["id"] == *id) {
                message["state"] = json!("delivered");
                message["deliveredAt"] = json!(chrono::Utc::now().to_rfc3339());
            }
        }
        drop(state);
        let _ = self.changes.send(());
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn providers_cannot_drain_each_others_messages_or_reuse_ids() {
        let q = Messages::default();
        q.enqueue_for("codex", "s", "mikky-cx", "Codex seulement")
            .unwrap();
        assert!(q.offer_for("claude", "s").is_null());
        assert!(q.enqueue("s", "mikky-cx", "Codex seulement").is_err());
        let batch = q.offer_for("codex", "s");
        assert_eq!(batch["messages"][0]["agent"], "codex");
        assert!(q.acknowledge("s", batch["delivery"].as_str().unwrap()));
        assert!(q.offer_for("codex", "s").is_null());
    }

    #[test]
    fn batches_are_per_session_and_only_printed_messages_are_acknowledged() {
        let q = Messages::default();
        q.enqueue("a", "m1", "un").unwrap();
        q.enqueue("b", "m2", "deux").unwrap();
        let offer = q.offer("a");
        assert_eq!(offer["messages"].as_array().unwrap().len(), 1);
        assert!(q.offer("a").is_null());
        assert!(!q.acknowledge("a", "wrong"));
        q.enqueue("a", "m3", "pendant le hook").unwrap();
        assert!(q.acknowledge("a", offer["delivery"].as_str().unwrap()));
        assert_eq!(q.list()[0]["state"], "delivered");
        assert_eq!(q.offer("a")["messages"][0]["id"], "m3");
        assert_eq!(q.offer("b")["messages"][0]["id"], "m2");
    }

    #[test]
    fn retries_are_idempotent_and_a_failed_relay_does_not_consume_messages() {
        let q = Messages::default();
        let m = q.enqueue("a", "m1", "un").unwrap();
        assert_eq!(q.enqueue("a", "m1", "un").unwrap(), m);
        assert!(q.enqueue("a", "m1", "autre").is_err());
        q.offer("a");
        q.state.lock().unwrap().leases.get_mut("a").unwrap().2 = Instant::now();
        assert_eq!(q.offer("a")["messages"][0]["text"], "un");
    }

    #[test]
    fn the_queue_is_bounded_and_never_discards_waiting_messages() {
        let q = Messages::default();
        assert!(q.enqueue("a", "bad]id", "un").is_err());
        assert!(q.enqueue("a", "empty", " ").is_err());
        assert!(q.enqueue("a", "big", &"x".repeat(MAX_TEXT + 1)).is_err());
        assert!(q.enqueue("a", "escaped", &"\u{0001}".repeat(2000)).is_err());
        for i in 0..MAX_MESSAGES {
            q.enqueue(&format!("s{i}"), &format!("m{i}"), "x").unwrap();
        }
        assert!(q.enqueue("other", "overflow", "x").is_err());
        assert_eq!(q.list().as_array().unwrap().len(), MAX_MESSAGES);
    }

    #[test]
    fn per_session_limits_and_escaped_batches_leave_the_remainder_waiting() {
        let q = Messages::default();
        for i in 0..MAX_SESSION_MESSAGES {
            q.enqueue("a", &format!("m{i}"), "x").unwrap();
        }
        assert!(q.enqueue("a", "overflow", "x").is_err());
        q.enqueue("b", "b1", &"\u{0001}".repeat(1000)).unwrap();
        q.enqueue("b", "b2", &"\u{0001}".repeat(1000)).unwrap();
        let first = q.offer("b");
        assert_eq!(first["messages"].as_array().unwrap().len(), 1);
        q.acknowledge("b", first["delivery"].as_str().unwrap());
        assert_eq!(q.offer("b")["messages"][0]["id"], "b2");
        q.enqueue("c", "c1", &"x".repeat(4000)).unwrap();
        assert!(q.enqueue("c", "c2", &"x".repeat(2001)).is_err());
    }
}
