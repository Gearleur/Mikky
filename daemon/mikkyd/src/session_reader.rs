//! Provider formats are decoded once, in Rust. The screen only folds events.
use serde_json::{Value, json};
use std::collections::HashSet;

#[derive(Default)]
pub struct Reader {
    started: bool,
    cwd: bool,
    turn: bool,
    user_in_turn: bool,
    plan_tools: HashSet<String>,
    tasks: Vec<(String, Value)>,
    pub first_message: Option<String>,
}

fn text(v: &Value) -> String {
    if let Some(s) = v.as_str() {
        return s.into();
    }
    v.as_array()
        .into_iter()
        .flatten()
        .filter(|b| matches!(b["type"].as_str(), Some("text" | "Text")))
        .filter_map(|b| b["text"].as_str())
        .collect()
}
fn string(v: &Value) -> &str {
    v.as_str().unwrap_or("")
}
fn status(v: &Value) -> &str {
    match v.as_str() {
        Some("in_progress") => "inProgress",
        Some("completed") => "completed",
        _ => "pending",
    }
}
fn basename(v: &str) -> &str {
    v.rsplit(['/', '\\']).next().unwrap_or(v)
}

impl Reader {
    pub fn read(&mut self, provider: &str, line: &Value) -> Vec<Value> {
        let mut events = if provider == "claude" {
            self.claude(line)
        } else {
            self.codex(line)
        };
        for event in &mut events {
            event["at"] = line["timestamp"].clone();
        }
        events
    }

    fn user(&mut self, value: &str, out: &mut Vec<Value>) {
        if value.starts_with("[Request interrupted") {
            if self.turn {
                out.push(json!({"type":"end", "reason":"cancelled"}));
            }
            self.turn = false;
            return;
        }
        if value.is_empty() || value.starts_with('<') {
            return;
        }
        if self.turn {
            out.push(json!({"type":"end", "reason":"cancelled"}));
        }
        self.turn = true;
        out.push(json!({"type":"start"}));
        out.push(json!({"type":"user", "text":value}));
    }

    fn claude(&mut self, line: &Value) -> Vec<Value> {
        if line["isSidechain"] == true {
            return vec![];
        }
        let mut out = vec![];
        if line["sessionId"].is_string()
            && (!self.started || (!self.cwd && line["cwd"].is_string()))
        {
            self.started = true;
            self.cwd = line["cwd"].is_string();
            out.push(json!({"type":"session", "id":line["sessionId"], "cwd":line["cwd"]}));
        }
        match string(&line["type"]) {
            "user" if line["isMeta"] != true => {
                if self.first_message.is_none() {
                    self.first_message = line["uuid"].as_str().map(str::to_owned);
                }
                let content = &line["message"]["content"];
                if let Some(s) = content.as_str() {
                    self.user(s, &mut out);
                } else {
                    for b in content.as_array().into_iter().flatten() {
                        match string(&b["type"]) {
                            "tool_result" => {
                                if !self.plan_tools.remove(string(&b["tool_use_id"])) {
                                    out.push(json!({"type":"tool", "id":b["tool_use_id"], "status": if b["is_error"] == true { "failed" } else { "completed" }, "output": text(&b["content"])}));
                                }
                            }
                            "text" => self.user(string(&b["text"]), &mut out),
                            _ => {}
                        }
                    }
                }
            }
            "assistant" => {
                let message = &line["message"];
                let mut tool = false;
                for b in message["content"].as_array().into_iter().flatten() {
                    match string(&b["type"]) {
                        "text" | "thinking" => {
                            let thought = b["type"] == "thinking";
                            let value = if thought { &b["thinking"] } else { &b["text"] };
                            if !string(value).is_empty() {
                                out.push(json!({"type":"message", "text":value, "id":message["id"], "thought":thought}));
                            }
                        }
                        "tool_use" => {
                            tool = true;
                            if let Some(plan) = self.plan(b) {
                                out.push(json!({"type":"plan", "entries":plan}));
                            } else {
                                out.push(claude_tool(b));
                            }
                        }
                        _ => {}
                    }
                }
                if line["isApiErrorMessage"] == true {
                    let message = text(&message["content"]);
                    out.push(json!({"type":"end", "reason": if message.to_lowercase().contains("limit") {"rateLimited"} else {"error"}, "message":message}));
                    self.turn = false;
                } else if message["stop_reason"] == "end_turn" && !tool && self.turn {
                    self.turn = false;
                    out.push(json!({"type":"end", "reason":"endTurn"}));
                }
            }
            "attachment" if line["attachment"]["type"] == "queued_command" => {
                let value = text(&line["attachment"]["prompt"]);
                if !value.is_empty() {
                    out.push(json!({"type":"user", "text":value, "queued":self.turn}));
                }
            }
            "ai-title" | "custom-title" => {
                let title = if line["type"] == "ai-title" {
                    &line["aiTitle"]
                } else {
                    &line["customTitle"]
                };
                if !string(title).is_empty() {
                    out.push(json!({"type":"title", "title":title}));
                }
            }
            _ => {}
        }
        out
    }

    fn plan(&mut self, tool: &Value) -> Option<Value> {
        let input = &tool["input"];
        match string(&tool["name"]) {
            "TodoWrite" => {
                self.plan_tools.insert(string(&tool["id"]).into());
                return Some(input["todos"].as_array().into_iter().flatten().map(|t| json!({"content":string(&t["content"]), "status":status(&t["status"])})).collect());
            }
            "TaskCreate" => {
                self.plan_tools.insert(string(&tool["id"]).into());
                self.tasks.push((
                    (self.tasks.len() + 1).to_string(),
                    json!({"content":string(&input["subject"]), "status":"pending"}),
                ));
            }
            "TaskUpdate" => {
                self.plan_tools.insert(string(&tool["id"]).into());
                let id = input["taskId"]
                    .as_str()
                    .map(str::to_owned)
                    .unwrap_or_else(|| input["taskId"].to_string());
                let i = self.tasks.iter().position(|(key, _)| key == &id)?;
                if input["status"] == "deleted" {
                    self.tasks.remove(i);
                } else {
                    if input["subject"].is_string() {
                        self.tasks[i].1["content"] = input["subject"].clone();
                    }
                    if input.get("status").is_some() {
                        self.tasks[i].1["status"] = json!(status(&input["status"]));
                    }
                }
            }
            _ => return None,
        }
        Some(self.tasks.iter().map(|(_, t)| t.clone()).collect())
    }

    fn end(&mut self, reason: &str, message: Value) -> Vec<Value> {
        if !self.turn {
            return vec![];
        }
        self.turn = false;
        vec![json!({"type":"end", "reason":reason, "message":message})]
    }

    fn codex(&mut self, line: &Value) -> Vec<Value> {
        let p = &line["payload"];
        match string(&line["type"]) {
            "session_meta" => {
                let id = p
                    .get("id")
                    .or_else(|| p.get("session_id"))
                    .unwrap_or(&Value::Null);
                if id.is_string() {
                    return vec![json!({"type":"session", "id":id, "cwd":p["cwd"]})];
                }
            }
            "response_item" if p["type"] == "function_call" && p["name"] == "update_plan" => {
                if let Ok(args) = serde_json::from_str::<Value>(string(&p["arguments"])) {
                    return vec![codex_plan(&args["plan"])];
                }
            }
            "event_msg" => match string(&p["type"]) {
                "task_started" => {
                    self.turn = true;
                    self.user_in_turn = false;
                    return vec![json!({"type":"start"})];
                }
                // Codex now ends a refused turn here, with its error (the
                // subscription limit: `usage_limit_exceeded`).
                "task_complete" if p["error"].is_object() => {
                    let e = &p["error"];
                    return self.end(
                        failure(string(&e["message"]), string(&e["codex_error_info"])),
                        e["message"].clone(),
                    );
                }
                "task_complete" => return self.end("endTurn", Value::Null),
                "turn_aborted" => return self.end("cancelled", Value::Null),
                "error" => {
                    return self.end(
                        failure(string(&p["message"]), string(&p["codex_error_info"])),
                        p["message"].clone(),
                    );
                }
                "plan_update" => return vec![codex_plan(&p["plan"])],
                "token_count" => {
                    let mut out = vec![];
                    let info = &p["info"];
                    if info["model_context_window"].is_number()
                        && info["last_token_usage"].is_object()
                    {
                        out.push(json!({"type":"context", "used":info["last_token_usage"]["total_tokens"].as_u64().unwrap_or(0), "size":info["model_context_window"]}));
                    }
                    if p["rate_limits"].is_object() {
                        out.push(json!({"type":"limits", "limits":p["rate_limits"]}));
                    }
                    return out;
                }
                "item_completed" => return self.codex_item(&p["item"]),
                _ => {}
            },
            _ => {}
        }
        vec![]
    }

    fn codex_item(&mut self, item: &Value) -> Vec<Value> {
        let id = string(&item["id"]);
        let event = match string(&item["type"]) {
            "UserMessage" => {
                let value = text(&item["content"]);
                if value.is_empty() {
                    return vec![];
                }
                let queued = self.user_in_turn;
                self.user_in_turn = true;
                json!({"type":"user", "text":value, "queued":queued})
            }
            "AgentMessage" => {
                let value = text(&item["content"]);
                if value.is_empty() {
                    return vec![];
                }
                json!({"type":"message", "text":value, "id":id})
            }
            "CommandExecution" => {
                let first = item["parsed_cmd"].as_array().and_then(|p| p.first());
                let command = first.map(|p| p["cmd"].clone()).unwrap_or_else(|| {
                    item["command"]
                        .as_array()
                        .and_then(|a| a.last())
                        .cloned()
                        .unwrap_or_else(|| item["command"].clone())
                });
                let kind = match first.and_then(|p| p["type"].as_str()) {
                    Some("read") => "read",
                    Some("search" | "list_files") => "search",
                    _ => "execute",
                };
                json!({"type":"tool", "id":id, "name":"exec_command", "kind":kind, "title":command, "command":command,
                    "status":if item["status"] == "completed" && item["exit_code"].as_i64().unwrap_or(0) == 0 {"completed"} else {"failed"}, "output":item["aggregated_output"]})
            }
            "FileChange" => {
                let path = item["changes"].as_object().and_then(|m| m.keys().next());
                json!({"type":"tool", "id":id, "name":"apply_patch", "kind":"edit", "title":path.map(|p| format!("Edit {}", basename(p))).unwrap_or("Modifie des fichiers".into()), "path":path,
                    "status":if item["status"] == "failed" {"failed"} else {"completed"}})
            }
            "WebSearch" => {
                json!({"type":"tool", "id":id, "name":"web_search", "kind":"fetch", "title":item["query"], "status":"completed"})
            }
            _ => return vec![],
        };
        vec![event]
    }
}

/// Why a Codex turn failed: the subscription limit, or another error.
fn failure(message: &str, info: &str) -> &'static str {
    if info.contains("limit") || message.to_lowercase().contains("limit") {
        "rateLimited"
    } else {
        "error"
    }
}

fn codex_plan(plan: &Value) -> Value {
    let entries: Vec<_> = plan
        .as_array()
        .into_iter()
        .flatten()
        .map(|p| json!({"content":string(&p["step"]), "status":status(&p["status"])}))
        .collect();
    json!({"type":"plan", "entries":entries})
}

fn claude_tool(b: &Value) -> Value {
    let input = &b["input"];
    let name = string(&b["name"]);
    let path = input
        .get("file_path")
        .or_else(|| input.get("notebook_path"))
        .or_else(|| input.get("path"))
        .unwrap_or(&Value::Null);
    let kind = match name {
        "Read" | "NotebookRead" => "read",
        "Write" | "Edit" | "MultiEdit" | "NotebookEdit" => "edit",
        "Grep" | "Glob" | "ToolSearch" | "LS" => "search",
        "WebFetch" | "WebSearch" => "fetch",
        "Bash" | "PowerShell" => "execute",
        _ => "other",
    };
    let title = match name {
        "Bash" | "PowerShell" => input
            .get("description")
            .unwrap_or(&input["command"])
            .clone(),
        "Grep" => json!(format!("grep {}", string(&input["pattern"]))),
        "Glob" => input["pattern"].clone(),
        "WebFetch" => input["url"].clone(),
        "WebSearch" => input["query"].clone(),
        _ if path.is_string() => json!(format!("{name} {}", basename(string(path)))),
        _ => input.get("description").cloned().unwrap_or(json!(name)),
    };
    let diff = match name {
        "Write" if path.is_string() => {
            json!({"path":path, "old":null, "new":string(&input["content"])})
        }
        "Edit" if path.is_string() => {
            json!({"path":path, "old":input["old_string"], "new":string(&input["new_string"])})
        }
        _ => Value::Null,
    };
    json!({"type":"tool", "id":b["id"], "name":name, "kind":kind, "title":title, "status":"running", "command":input["command"], "path":path, "diff":diff})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codex_limit_in_task_complete_is_rate_limited() {
        let mut r = Reader::default();
        r.read("codex", &json!({"type":"event_msg","payload":{"type":"task_started"}}));
        let out = r.read(
            "codex",
            &json!({"type":"event_msg","payload":{"type":"task_complete","error":{
                "message":"You've hit your usage limit. Try again at 2:10 PM.",
                "codex_error_info":"usage_limit_exceeded"}}}),
        );
        assert_eq!(out[0]["type"], "end");
        assert_eq!(out[0]["reason"], "rateLimited");
        assert_eq!(out[0]["message"], "You've hit your usage limit. Try again at 2:10 PM.");
    }

    #[test]
    fn codex_task_complete_without_error_ends_the_turn() {
        let mut r = Reader::default();
        r.read("codex", &json!({"type":"event_msg","payload":{"type":"task_started"}}));
        let out = r.read("codex", &json!({"type":"event_msg","payload":{"type":"task_complete"}}));
        assert_eq!(out[0]["reason"], "endTurn");
    }
}
