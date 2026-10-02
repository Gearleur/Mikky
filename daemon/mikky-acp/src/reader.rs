//! ACP is normalized once by its owning backend, independently of screens.
use serde_json::{Value, json};
use std::collections::{HashMap, HashSet};

#[derive(Default)]
pub struct Reader {
    methods: HashMap<String, String>,
    modes: HashMap<String, Value>,
    models: HashMap<String, Value>,
    permissions: HashMap<String, Value>,
    questions: HashSet<String>,
    prompts: Vec<String>,
    loading: Option<String>,
    mode_reported: bool,
    replay_turn: bool,
    replay_user: Value,
}

fn items(v: &Value) -> impl Iterator<Item = &Value> {
    v.as_array().into_iter().flatten()
}
fn string(v: &Value) -> &str {
    v.as_str().unwrap_or("")
}
fn text(v: &Value) -> String {
    items(v)
        .filter(|b| b["type"] == "text")
        .map(|b| string(&b["text"]))
        .collect()
}
fn command(raw: &Value) -> Value {
    match &raw["command"] {
        Value::String(s) => json!(s),
        Value::Array(a) => json!(a.iter().map(string).collect::<Vec<_>>().join(" ")),
        _ => Value::Null,
    }
}
/// A prompt that failed: its end, a limit or an error. codex-acp answers a
/// subscription limit with « Internal error » and puts the agent's text and
/// `codexErrorInfo: usageLimitExceeded` in `data` (seen 2026-10-02).
fn prompt_error(error: &Value) -> Value {
    let data = &error["data"];
    let message = data
        .get("message")
        .filter(|m| m.as_str().is_some_and(|s| !s.is_empty()))
        .or(error.get("message"))
        .cloned()
        .unwrap_or(json!("Erreur"));
    let lower = string(&message).to_lowercase();
    let info = data["codexErrorInfo"].to_string().to_lowercase();
    let limited = info.contains("usagelimit")
        || info.contains("usage_limit")
        || ["rate limit", "usage limit", "limit reached"]
            .iter()
            .any(|s| lower.contains(s));
    json!({"type":"end","reason":if limited {"rateLimited"} else {"error"},"message":message})
}
fn stop_reason(v: &Value) -> &str {
    match string(v) {
        "cancelled" => "cancelled",
        "refusal" => "refused",
        "max_tokens" | "max_turn_requests" => "maxTokens",
        _ => "endTurn",
    }
}

impl Reader {
    pub fn read(&mut self, message: &Value, outgoing: bool, at: &str) -> Vec<Value> {
        let mut events = self.message(message, outgoing);
        for e in &mut events {
            e["at"] = json!(at);
        }
        events
    }

    fn message(&mut self, m: &Value, outgoing: bool) -> Vec<Value> {
        let id = &m["id"];
        let key = id.to_string();
        let method = string(&m["method"]);
        let p = &m["params"];
        if outgoing {
            if !method.is_empty() {
                if !id.is_null() {
                    self.methods.insert(key.clone(), method.into());
                }
                match method {
                    "session/prompt" => {
                        let queued = !self.prompts.is_empty();
                        self.prompts.push(key);
                        let mut out = vec![];
                        if !queued {
                            out.push(json!({"type":"start"}));
                        }
                        out.push(json!({"type":"user","text":text(&p["prompt"]),"queued":queued}));
                        return out;
                    }
                    "session/set_mode" => {
                        self.modes.insert(key, p["modeId"].clone());
                        self.mode_reported = false;
                    }
                    "session/set_model" => {
                        self.models.insert(key, p["modelId"].clone());
                    }
                    "session/set_config_option" if p["configId"] == "model" => {
                        self.models.insert(key, p["value"].clone());
                    }
                    "session/load" => self.loading = Some(key),
                    _ => {}
                }
            } else if let Some(options) = self.permissions.remove(&key) {
                let outcome = &m["result"]["outcome"];
                let allowed = outcome["outcome"] == "selected"
                    && items(&options).any(|o| {
                        o["optionId"] == outcome["optionId"]
                            && matches!(string(&o["kind"]), "allow_once" | "allow_always")
                    });
                return vec![json!({"type":"permissionAnswered","id":id,"allowed":allowed})];
            } else if self.questions.remove(&key) {
                return vec![json!({"type":"questionAnswered","id":id})];
            }
            return vec![];
        }
        match method {
            "session/update" => return self.update(&p["update"]),
            "session/request_permission" => {
                self.permissions.insert(key, p["options"].clone());
                let t = &p["toolCall"];
                return vec![
                    json!({"type":"permission","id":id,"toolCallId":t["toolCallId"],"title":t.get("title").or(t.get("name")).cloned().unwrap_or(json!("")),"command":command(&t["rawInput"]),"options":p.get("options").cloned().unwrap_or(json!([]))}),
                ];
            }
            "elicitation/create" if p["mode"] == "form" => {
                self.questions.insert(key);
                let props = p["requestedSchema"]["properties"].as_object();
                let fields: Vec<Value> = props.into_iter().flat_map(|p| p.iter()).filter(|(k,_)| !k.ends_with("_custom")).map(|(k,v)| {
                    let multiple = v["type"] == "array";
                    let choices = if multiple { &v["items"]["anyOf"] } else { &v["oneOf"] };
                    let other = format!("{k}_custom");
                    json!({"key":k,"text":v.get("description").cloned().unwrap_or_else(|| if props.is_some_and(|p| p.len() <= 2) {p["message"].clone()} else {json!("")}),"title":v["title"],"multiple":multiple,"otherKey":if props.is_some_and(|p| p.contains_key(&other)) {json!(other)} else {Value::Null},"choices":items(choices).map(|c| json!({"value":c.get("const").or(c.get("title")).cloned().unwrap_or(json!("null")),"description":c.get("description").cloned().unwrap_or(json!(""))})).collect::<Vec<_>>()})
                }).collect();
                return vec![
                    json!({"type":"question","id":id,"message":p.get("message").cloned().unwrap_or(json!("")),"questions":fields}),
                ];
            }
            "" if !id.is_null() => {}
            _ => return vec![],
        }
        let method = self.methods.remove(&key).unwrap_or_default();
        let r = &m["result"];
        let error = &m["error"];
        match method.as_str() {
            "session/new" | "session/load" | "session/resume" => {
                let mut out = vec![];
                if self.replay_turn {
                    self.replay_turn = false;
                    out.push(json!({"type":"end","reason":"endTurn"}));
                }
                if self.loading.as_ref() == Some(&key) {
                    self.loading = None;
                }
                if r.is_object() {
                    let config = items(&r["configOptions"])
                        .find(|o| o["category"] == "model" && o["type"] == "select")
                        .unwrap_or(&Value::Null);
                    let modes: Vec<_> = items(&r["modes"]["availableModes"]).map(|m| json!({"id":m["id"],"name":m.get("name").unwrap_or(&m["id"]),"description":m.get("description").cloned().unwrap_or(json!(""))})).collect();
                    let options = if r["models"].is_null() {
                        &config["options"]
                    } else {
                        &r["models"]["availableModels"]
                    };
                    let models: Vec<_> = items(options).map(|m| {let id = m.get("modelId").unwrap_or(&m["value"]); json!({"id":id,"name":m.get("name").unwrap_or(id),"description":m.get("description").cloned().unwrap_or(json!(""))})}).collect();
                    out.push(json!({"type":"session","id":r.get("sessionId").cloned().unwrap_or(json!("")),"modes":modes,"modeId":r["modes"]["currentModeId"],"models":models,"modelId":r["models"].get("currentModelId").unwrap_or(&config["currentValue"]),"modelOption":if r["models"].is_null() {config["id"].clone()} else {Value::Null}}));
                }
                out
            }
            "session/set_model" | "session/set_config_option" => self
                .models
                .remove(&key)
                .filter(|_| error.is_null())
                .map(|id| vec![json!({"type":"model","id":id})])
                .unwrap_or_default(),
            "session/set_mode" => self
                .modes
                .remove(&key)
                .filter(|_| error.is_null() && !self.mode_reported)
                .map(|id| vec![json!({"type":"mode","id":id})])
                .unwrap_or_default(),
            "session/prompt" => {
                let Some(i) = self.prompts.iter().position(|p| p == &key) else {
                    return vec![];
                };
                self.prompts.drain(..=i);
                if !self.prompts.is_empty() {
                    return vec![];
                }
                if !error.is_null() {
                    return vec![prompt_error(error)];
                }
                let mut out = vec![];
                let usage = &r["usage"];
                if usage.is_object() {
                    out.push(json!({"type":"tokens","input":usage["inputTokens"].as_u64().unwrap_or(0),"output":usage["outputTokens"].as_u64().unwrap_or(0),"cached":usage["cachedReadTokens"].as_u64().unwrap_or(0)+usage["cachedWriteTokens"].as_u64().unwrap_or(0)}));
                }
                out.push(json!({"type":"end","reason":stop_reason(&r["stopReason"])}));
                out
            }
            _ => vec![],
        }
    }

    fn update(&mut self, u: &Value) -> Vec<Value> {
        match string(&u["sessionUpdate"]) {
            "user_message_chunk" => {
                let event =
                    json!({"type":"user","text":text(&json!([u["content"]])),"id":u["messageId"]});
                if self.loading.is_none() {
                    return vec![event];
                }
                let same = !u["messageId"].is_null() && u["messageId"] == self.replay_user;
                self.replay_user = u["messageId"].clone();
                if same {
                    return vec![event];
                }
                let mut out = vec![];
                if self.replay_turn {
                    out.push(json!({"type":"end","reason":"endTurn"}));
                }
                self.replay_turn = true;
                out.extend([json!({"type":"start"}), event]);
                out
            }
            "agent_message_chunk" | "agent_thought_chunk" => {
                let t = text(&json!([u["content"]]));
                if t.is_empty() {
                    vec![]
                } else {
                    vec![
                        json!({"type":"message","text":t,"id":u["messageId"],"thought":u["sessionUpdate"] == "agent_thought_chunk"}),
                    ]
                }
            }
            "tool_call" | "tool_call_update" => vec![tool(u)],
            "plan" => vec![
                json!({"type":"plan","entries":items(&u["entries"]).map(|e| json!({"content":e.get("content").cloned().unwrap_or(json!("")),"status":match string(&e["status"]) {"in_progress"=>"inProgress","completed"=>"completed",_=>"pending"}})).collect::<Vec<_>>()}),
            ],
            "usage_update" if u["size"].as_i64().unwrap_or(0) > 0 && u["used"].is_number() => {
                vec![json!({"type":"context","used":u["used"],"size":u["size"]})]
            }
            "current_mode_update" => {
                self.mode_reported = true;
                vec![json!({"type":"mode","id":u["currentModeId"]})]
            }
            "available_commands_update" => vec![
                json!({"type":"commands","commands":items(&u["availableCommands"]).filter(|c| c["name"].is_string()).map(|c| json!({"name":c["name"],"description":c.get("description").cloned().unwrap_or(json!("")),"hint":c["input"]["hint"]})).collect::<Vec<_>>()}),
            ],
            "session_info_update" if !string(&u["title"]).is_empty() => {
                vec![json!({"type":"title","title":u["title"]})]
            }
            _ => vec![],
        }
    }
}

fn tool(u: &Value) -> Value {
    let raw = &u["rawInput"];
    let mut diff = Value::Null;
    let mut output = vec![];
    for c in items(&u["content"]) {
        if c["type"] == "diff" {
            diff = json!({"path":c["path"],"old":c["oldText"],"new":c.get("newText").cloned().unwrap_or(json!(""))});
        }
        if c["type"] == "content" {
            let t = text(&json!([c["content"]]));
            if !t.is_empty() {
                output.push(t);
            }
        }
    }
    let title = if !string(&raw["description"]).is_empty() {
        raw["description"].clone()
    } else if u["title"].is_null() || string(&u["title"]).ends_with('…') || u["title"] == "Terminal"
    {
        Value::Null
    } else {
        u["title"].clone()
    };
    let kind = if u["kind"].is_string() {
        json!(match string(&u["kind"]) {
            "read" => "read",
            "edit" => "edit",
            "delete" => "delete",
            "move" => "move",
            "search" => "search",
            "execute" => "execute",
            "think" => "think",
            "fetch" => "fetch",
            _ => "other",
        })
    } else {
        Value::Null
    };
    json!({"type":"tool","id":u["toolCallId"],"name":u.get("name").unwrap_or(&u["_meta"]["claudeCode"]["toolName"]),"kind":kind,"title":title,"status":match string(&u["status"]) {"pending"=>json!("pending"),"in_progress"=>json!("running"),"completed"=>json!("completed"),"failed"=>json!("failed"),_=>Value::Null},"command":command(raw),"path":raw.get("file_path").unwrap_or(&u["locations"][0]["path"]),"diff":diff,"output":if output.is_empty() {Value::Null} else {json!(output.join("\n"))}})
}

#[cfg(test)]
mod tests {
    use super::*;

    fn failed_prompt(error: Value) -> Vec<Value> {
        let mut r = Reader::default();
        r.read(&json!({"jsonrpc":"2.0","id":7,"method":"session/prompt","params":{"prompt":[{"type":"text","text":"ok ?"}]}}), true, "t0");
        r.read(&json!({"jsonrpc":"2.0","id":7,"error":error}), false, "t1")
    }

    #[test]
    fn codex_usage_limit_in_data_is_a_limit() {
        let out = failed_prompt(json!({"code":-32603,"message":"Internal error","data":{
            "message":"You've hit your usage limit. Try again at 12:51 AM.",
            "codexErrorInfo":"usageLimitExceeded"}}));
        assert_eq!(out[0]["reason"], "rateLimited");
        assert_eq!(out[0]["message"], "You've hit your usage limit. Try again at 12:51 AM.");
    }

    #[test]
    fn limit_words_in_the_message_are_a_limit() {
        let out = failed_prompt(json!({"code":-32603,"message":"Claude AI usage limit reached|1759248000"}));
        assert_eq!(out[0]["reason"], "rateLimited");
    }

    #[test]
    fn another_failure_stays_an_error() {
        let out = failed_prompt(json!({"code":-32603,"message":"Internal error","data":{"details":"boom"}}));
        assert_eq!(out[0]["reason"], "error");
        assert_eq!(out[0]["message"], "Internal error");
    }
}
