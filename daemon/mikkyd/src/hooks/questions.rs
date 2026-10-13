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

/// The session event of a question (`type: "question"`, the engine's
/// `QuestionAsked`), from questions as [`questions_of`] gives them. The
/// hooks and the Claude session reader both use it.
pub fn question_event(id: &str, questions: &Value, at: &Value) -> Value {
    let wire: Vec<_> = questions
        .as_array()
        .into_iter()
        .flatten()
        .enumerate()
        .map(|(i, q)| {
            let key = format!("q{}", i + 1);
            let choices: Vec<_> = q["options"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|o| json!({"value": o["label"], "description": o["description"].as_str().unwrap_or_default()}))
                .collect();
            json!({
                "key": key,
                "otherKey": format!("{key}_custom"),
                "text": q["question"],
                "title": q["header"].as_str().filter(|s| !s.is_empty()),
                "multiple": q["multiSelect"],
                "choices": choices,
            })
        })
        .collect();
    let message = wire.first().map_or(Value::Null, |q| q["text"].clone());
    json!({"type": "question", "id": id, "message": message, "questions": wire, "at": at})
}

/// The screens' answers, by question key as [`question_event`] names them
/// (`q1`: a label or a list of labels; `q1_custom`: free text, which wins),
/// as Claude takes them: by question text, a string, or a list of labels
/// for a multiple choice. The same keys as an ACP form (`run.answerQuestion`).
/// None when a question is left unanswered.
pub fn by_text(questions: &Value, keyed: &Value) -> Option<Value> {
    let keyed = keyed.as_object()?;
    let mut out = serde_json::Map::new();
    for (i, q) in questions.as_array()?.iter().enumerate() {
        let key = format!("q{}", i + 1);
        let multiple = q["multiSelect"] == true;
        let text = q["question"].as_str()?.to_owned();
        let other = keyed
            .get(&format!("{key}_custom"))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|t| !t.is_empty());
        let answer = match (other, keyed.get(&key)) {
            (Some(t), _) => json!(t),
            (None, Some(Value::String(s))) if !s.trim().is_empty() => {
                if multiple {
                    json!([s])
                } else {
                    json!(s)
                }
            }
            (None, Some(Value::Array(picks))) if !picks.is_empty() => {
                let mut labels: Vec<&str> = Vec::new();
                for p in picks {
                    let p = p.as_str()?;
                    if !labels.contains(&p) {
                        labels.push(p);
                    }
                }
                if multiple {
                    json!(labels)
                } else {
                    json!(labels[0])
                }
            }
            _ => return None,
        };
        out.insert(text, answer);
    }
    Some(Value::Object(out))
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
