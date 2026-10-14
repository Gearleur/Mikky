//! Only explicit user messages may keep a Claude or Codex turn going.
use serde_json::{Value, json};

pub fn output(event: &str, agent: &str, offer: &Value) -> Option<String> {
    if !matches!(agent, "claude" | "codex") || !matches!(event, "PostToolUse" | "Stop") {
        return None;
    }
    let delivery = offer["delivery"].as_str()?;
    if delivery.is_empty() {
        return None;
    }
    let messages = offer["messages"].as_array()?;
    if messages.is_empty() || messages.len() > 16 {
        return None;
    }
    let mut context = String::from("Messages de l'utilisateur via Mikky :\n");
    for message in messages {
        let (id, text) = (message["id"].as_str()?, message["text"].as_str()?);
        if id.is_empty()
            || id.len() > 96
            || text.trim().is_empty()
            || text.len() > 4000
            || !id.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-')
        {
            return None;
        }
        // A whole JSON record per line: newlines and markers in the user's
        // text cannot split a record or forge another message's identity.
        context.push_str(&format!(
            "MIKKY_USER_MESSAGE {}\n",
            json!({"id":id,"text":text})
        ));
    }
    if context.len() > 9500 {
        return None;
    }
    Some(if event == "PostToolUse" {
        json!({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":context}})
    } else { json!({"decision":"block","reason":context}) }.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn post_tool_context_and_stop_reason_carry_the_same_user_messages() {
        let batch = json!({"delivery":"d1","messages":[{"id":"m1","text":"Continue\navec é"}]});
        for (agent, event) in [
            ("claude", "PostToolUse"),
            ("claude", "Stop"),
            ("codex", "PostToolUse"),
            ("codex", "Stop"),
        ] {
            let out: Value = serde_json::from_str(&output(event, agent, &batch).unwrap()).unwrap();
            let context = if event == "Stop" {
                assert_eq!(out["decision"], "block");
                out["reason"].as_str().unwrap()
            } else {
                assert_eq!(out["hookSpecificOutput"]["hookEventName"], "PostToolUse");
                out["hookSpecificOutput"]["additionalContext"]
                    .as_str()
                    .unwrap()
            };
            assert!(context.contains("MIKKY_USER_MESSAGE"));
            assert_eq!(context.lines().count(), 2);
        }
    }

    #[test]
    fn doubt_wrong_agent_or_event_and_empty_batches_are_silent() {
        let batch = json!({"delivery":"d","messages":[{"id":"m","text":"x"}]});
        assert!(output("Stop", "unknown", &batch).is_none());
        assert!(output("PermissionRequest", "claude", &batch).is_none());
        for bad in [
            Value::Null,
            json!({}),
            json!({"delivery":"d","messages":[]}),
            json!({"delivery":"d","messages":[{"id":"m","text":""}]}),
        ] {
            assert!(output("Stop", "claude", &bad).is_none());
        }
    }
}
