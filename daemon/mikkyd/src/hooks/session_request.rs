//! Hooks use the same permission/question events as ACP. Raw fields stay
//! available to old clients and to the reply transport.
use serde_json::{Value, json};

pub(super) fn event(request: &Value) -> Value {
    let id = format!("hook:{}", request["id"]);
    if request["kind"] == "question" {
        return super::questions::question_event(&id, &request["questions"], &request["at"]);
    }
    let command = request["command"]
        .as_str()
        .filter(|s| !s.trim().is_empty())
        .map(str::to_owned)
        .or_else(|| {
            request["path"]
                .as_str()
                .map(|p| format!("{} {p}", request["tool"].as_str().unwrap_or_default()))
        })
        .unwrap_or_else(|| request["title"].as_str().unwrap_or_default().to_owned());
    json!({"type":"permission","id":id,"toolCallId":request["toolCallId"],"title":request["title"],"description":request["description"],"command":command,"at":request["at"],
        "options":[{"optionId":"allow","name":"Oui","kind":"allow_once"},{"optionId":"deny","name":"Non","kind":"reject_once"}]})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hook_permission_and_question_are_session_events() {
        let permission = event(
            &json!({"id":7,"kind":"permission","tool":"Bash","title":"Bash cargo test","description":"Vérifie le moteur","command":"cargo test","toolCallId":"toolu_1"}),
        );
        assert_eq!(permission["type"], "permission");
        assert_eq!(permission["id"], "hook:7");
        assert_eq!(permission["command"], "cargo test");
        assert_eq!(permission["toolCallId"], "toolu_1");
        assert_eq!(permission["options"].as_array().unwrap().len(), 2);
        let question = event(
            &json!({"id":8,"kind":"question","title":"Quelle base ?","questions":[{"question":"Quelle base ?","header":"Base","multiSelect":true,"options":[{"label":"SQLite","description":"Locale"}]}]}),
        );
        assert_eq!(question["type"], "question");
        assert_eq!(question["questions"][0]["key"], "q1");
        assert_eq!(question["questions"][0]["otherKey"], "q1_custom");
        assert_eq!(question["questions"][0]["choices"][0]["value"], "SQLite");
    }
}
