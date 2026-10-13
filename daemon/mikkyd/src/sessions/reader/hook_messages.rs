//! Claude persists PostToolUse context in hook_additional_context attachments
//! (content: string[]). Stop feedback appears as a blockingError or summary.
//! Decode only our JSON records, once by message id.
use serde_json::{Value, json};
use std::collections::HashSet;

#[derive(Default)]
pub struct Messages {
    seen: HashSet<String>,
}

impl Messages {
    pub fn read(&mut self, line: &Value) -> Vec<Value> {
        let attachment = &line["attachment"];
        let payload = match line["type"].as_str() {
            Some("attachment") if attachment["type"] == "hook_additional_context" => {
                &attachment["content"]
            }
            Some("attachment") if attachment["type"] == "hook_blocking_error" => {
                &attachment["blockingError"]["blockingError"]
            }
            Some("system") if line["subtype"] == "stop_hook_summary" => &line["hook_errors"],
            Some("user") if line["isMeta"] == true => &line["message"]["content"],
            _ => return vec![],
        };
        let mut strings = vec![];
        contents(payload, &mut strings);
        let mut out = vec![];
        for s in strings {
            for row in s.lines() {
                let Some(record) = row.strip_prefix("MIKKY_USER_MESSAGE ") else {
                    continue;
                };
                let Ok(message) = serde_json::from_str::<Value>(record) else {
                    continue;
                };
                let (Some(id), Some(text)) = (message["id"].as_str(), message["text"].as_str())
                else {
                    continue;
                };
                if !id.starts_with("mikky-") || text.is_empty() || !self.seen.insert(id.to_owned())
                {
                    continue;
                }
                out.push(json!({"type":"user","id":id,"text":text,"queued":true}));
            }
        }
        out
    }
}

fn contents<'a>(v: &'a Value, out: &mut Vec<&'a str>) {
    match v {
        Value::String(s) => out.push(s),
        Value::Array(a) => {
            for v in a {
                contents(v, out);
            }
        }
        Value::Object(_) if v["type"] == "text" => contents(&v["text"], out),
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn attachment_and_stop_summary_do_not_duplicate_or_expose_raw_hook_context() {
        let text = "Messages de l'utilisateur via Mikky :\nMIKKY_USER_MESSAGE {\"id\":\"mikky-m1\",\"text\":\"Écris autrement\"}\n";
        let mut messages = Messages::default();
        let event = json!({"type":"attachment","attachment":{"type":"hook_additional_context","content":[text]}});
        assert_eq!(
            messages.read(&event),
            vec![json!({"type":"user","id":"mikky-m1","text":"Écris autrement","queued":true})]
        );
        assert!(
            messages
                .read(&json!({"type":"system","subtype":"stop_hook_summary","hook_errors":[text]}))
                .is_empty()
        );
        assert!(
            messages
                .read(&json!({"type":"user","message":{"content":text}}))
                .is_empty()
        );
    }

    #[test]
    fn stop_feedback_starts_a_continuation_and_its_meta_echo_is_ignored() {
        let context = "MIKKY_USER_MESSAGE {\"id\":\"mikky-stop\",\"text\":\"Ajoute un test\"}";
        let mut reader = super::super::Reader::default();
        let line = json!({"type":"attachment","sessionId":"s","timestamp":"2026-10-13T12:00:00Z", "attachment":{"type":"hook_blocking_error","blockingError":{"blockingError":context}}});
        let events = reader.read("claude", &line);
        assert!(events.iter().any(|e| e["type"] == "start"));
        let user = events.iter().find(|e| e["type"] == "user").unwrap();
        assert_eq!(user["text"], "Ajoute un test");
        assert_eq!(user["at"], line["timestamp"]);
        assert!(reader.read("claude", &json!({"type":"user","isMeta":true,"message":{"content":[{"type":"text","text":context}]}})).is_empty());
    }
}
