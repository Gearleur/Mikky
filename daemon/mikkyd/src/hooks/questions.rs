//! Claude's questions (`AskUserQuestion`): the form the screens show, and
//! whether the answers fit it.

use serde_json::{Value, json};

/// The questions of an `AskUserQuestion` input, as the screens get them:
/// `question`, `header`, `options` (`label`, `description`),
/// `multiSelect`. None if it is not a form of 1 to 4 questions, each with
/// a text and labelled options (Claude asks in its terminal then).
pub fn questions_of(input: &Value) -> Option<Value> {
    let items = input["questions"].as_array()?;
    if items.is_empty() || items.len() > 4 {
        return None;
    }
    let mut out = Vec::new();
    for q in items {
        let text = q["question"].as_str().filter(|t| !t.trim().is_empty())?;
        let mut options = Vec::new();
        for o in q["options"].as_array()? {
            let label = o["label"].as_str().filter(|l| !l.is_empty())?;
            options.push(json!({
                "label": label,
                "description": o["description"].as_str().unwrap_or_default(),
            }));
        }
        if options.is_empty() {
            return None;
        }
        out.push(json!({
            "question": text,
            "header": q["header"].as_str().unwrap_or_default(),
            "options": options,
            "multiSelect": q["multiSelect"].as_bool().unwrap_or(false),
        }));
    }
    // Claude keys its answers by question text: two alike cannot be told
    // apart.
    let mut texts: Vec<_> = out.iter().map(|q| &q["question"]).collect();
    texts.sort_by_key(|t| t.as_str());
    texts.dedup();
    (texts.len() == out.len()).then_some(Value::Array(out))
}

/// True when `answers` answers each question once, by its text: free text
/// or a label (a non-empty string), or for a multiple choice a non-empty
/// list of distinct labels. Nothing else.
pub fn fits(questions: &Value, answers: &Value) -> bool {
    let (Some(questions), Some(answers)) = (questions.as_array(), answers.as_object()) else {
        return false;
    };
    if questions.is_empty() || questions.len() != answers.len() {
        return false;
    }
    questions.iter().all(|q| {
        let Some(text) = q["question"].as_str() else {
            return false;
        };
        let labels: Vec<&str> = q["options"]
            .as_array()
            .map(|o| o.iter().filter_map(|o| o["label"].as_str()).collect())
            .unwrap_or_default();
        match answers.get(text) {
            Some(Value::String(s)) => !s.trim().is_empty(),
            Some(Value::Array(picks)) if q["multiSelect"] == true => {
                let picks: Vec<&str> = picks.iter().filter_map(Value::as_str).collect();
                let mut seen = picks.clone();
                seen.sort_unstable();
                seen.dedup();
                !picks.is_empty()
                    && seen.len() == picks.len()
                    && picks.len() == answers[text].as_array().map(Vec::len).unwrap_or_default()
                    && picks.iter().all(|p| labels.contains(p))
            }
            _ => false,
        }
    })
}
