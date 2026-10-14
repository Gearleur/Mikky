//! Codex's session files (`rollout-*.jsonl`): turns, messages, plans,
//! limits, and the tools it runs through `exec` scripts.
use super::{Reader, basename, status, string, text};
use crate::sessions::codex_script;
use serde_json::{Value, json};

impl Reader {
    pub(super) fn codex(&mut self, line: &Value) -> Vec<Value> {
        let p = &line["payload"];
        match string(&line["type"]) {
            "session_meta" => {
                let id = p
                    .get("id")
                    .or_else(|| p.get("session_id"))
                    .unwrap_or(&Value::Null);
                if id.is_string() {
                    if p["parent_thread_id"].is_string() {
                        self.parent = Some(codex_parent(p));
                    }
                    let app = codex_app(string(&p["originator"]));
                    return vec![json!({"type":"session", "id":id, "cwd":p["cwd"], "app":app})];
                }
            }
            "response_item" if p["type"] == "function_call" && p["name"] == "update_plan" => {
                if let Ok(args) = serde_json::from_str::<Value>(string(&p["arguments"])) {
                    return vec![codex_plan(&args["plan"])];
                }
            }
            "response_item" => return self.codex_call(p),
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
                // Codex Desktop (2026-10) writes no items: its messages and
                // file changes are plain events.
                "user_message" if !self.codex_items => {
                    return self.codex_user(p["message"].as_str().unwrap_or("").trim());
                }
                "context_compacted" if !self.codex_items => return self.compacted(),
                "agent_message" if !self.codex_items => {
                    let value = string(&p["message"]).trim();
                    if !value.is_empty() {
                        self.said += 1;
                        return vec![
                            json!({"type":"message", "text":value, "id":format!("said-{}", self.said)}),
                        ];
                    }
                }
                "sub_agent_activity" => return self.sub_agent(p),
                "patch_apply_end" => {
                    return self.codex_item(
                        &json!({"type":"FileChange", "id":p["call_id"], "changes":p["changes"],
                        "status": if p["success"] == false {"failed"} else {"completed"}}),
                    );
                }
                _ => {}
            },
            _ => {}
        }
        vec![]
    }

    fn codex_item(&mut self, item: &Value) -> Vec<Value> {
        let id = string(&item["id"]);
        let event = match string(&item["type"]) {
            "HookPrompt" => {
                return item["fragments"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .flat_map(|fragment| self.hook_messages.read_text(string(&fragment["text"])))
                    .collect();
            }
            "UserMessage" => {
                self.codex_items = true;
                return self.codex_user(&text(&item["content"]));
            }
            "AgentMessage" => {
                self.codex_items = true;
                let value = text(&item["content"]);
                if value.is_empty() {
                    return vec![];
                }
                json!({"type":"message", "text":value, "id":id})
            }
            "Reasoning" => {
                self.codex_items = true;
                return thought(id, &item["summary_text"]);
            }
            "ContextCompaction" => return self.compacted(),
            "SubAgentActivity" => return self.sub_agent(item),
            // Inside `exec` scripts, already shown as their tools.
            "CommandExecution" | "McpToolCall" | "ImageView" if self.codex_exec => return vec![],
            "McpToolCall" => {
                let failed = item["status"] == "failed" || item["result"]["isError"] == true;
                json!({"type":"tool", "id":id, "name":item["tool"], "kind":"other",
                    "title":format!("{} · {}", string(&item["server"]), string(&item["tool"])),
                    "status":if failed {"failed"} else {"completed"}, "output":text(&item["result"]["content"])})
            }
            "ImageView" => {
                let path = string(&item["path"]).trim_start_matches("file:///");
                json!({"type":"tool", "id":id, "name":"view_image", "kind":"read",
                    "title":format!("Regarde {}", basename(path)), "path":path, "status":"completed"})
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
            "FileChange" => return self.codex_files(id, item),
            "WebSearch" => {
                json!({"type":"tool", "id":id, "name":"web_search", "kind":"fetch", "title":item["query"], "status":"completed"})
            }
            _ => return vec![],
        };
        vec![event]
    }

    /// A change of files: one tool per file, with each part of its diff.
    /// Made by an `apply_patch` script: the first file is that script's tool.
    fn codex_files(&mut self, id: &str, item: &Value) -> Vec<Value> {
        let status = if item["status"] == "failed" {
            "failed"
        } else {
            "completed"
        };
        let base = self
            .patch
            .take()
            .filter(|call| self.calls.contains_key(call))
            .unwrap_or_else(|| id.to_string());
        codex_script::file_changes(&item["changes"])
            .into_iter()
            .enumerate()
            .map(|(i, (path, kind, diffs))| {
                let id = if i == 0 { base.clone() } else { format!("{base}:{i}") };
                let verb = if kind == "delete" { "Delete" } else { "Edit" };
                json!({"type":"tool", "id":id, "name":"apply_patch", "kind":kind, "title":format!("{verb} {}", basename(&path)),
                    "path":path, "status":status, "diff":diffs.first(), "diffs":diffs})
            })
            .collect()
    }

    fn codex_user(&mut self, value: &str) -> Vec<Value> {
        if value.starts_with("<hook_prompt")
            || value.starts_with("Messages de l'utilisateur via Mikky :\n")
        {
            return self.codex_hook_context(value);
        }
        if let Some(reply) = value.strip_prefix("<send_user_message_question_reply>") {
            return self.codex_reply(reply);
        }
        if value.is_empty() {
            return vec![];
        }
        let queued = self.user_in_turn;
        self.user_in_turn = true;
        let mut out = self.answered();
        out.push(json!({"type":"user", "text":value, "queued":queued}));
        out
    }

    /// The question Codex asked is over: the user wrote.
    fn answered(&mut self) -> Vec<Value> {
        self.asked
            .take()
            .map(|id| json!({"type":"questionAnswered", "id":id}))
            .into_iter()
            .collect()
    }

    /// The user's answers to Codex's question, as Codex Desktop writes them:
    /// `[{"questionItemId":…, "question":…, "answer":…}]`.
    fn codex_reply(&mut self, reply: &str) -> Vec<Value> {
        let body = reply
            .trim()
            .trim_end_matches("</send_user_message_question_reply>");
        let answers = serde_json::from_str::<Value>(body.trim()).unwrap_or_default();
        let text = answers
            .as_array()
            .into_iter()
            .flatten()
            .map(|a| match &a["answer"] {
                Value::Array(all) => all
                    .iter()
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join(", "),
                v => string(v).to_string(),
            })
            .filter(|a| !a.is_empty())
            .collect::<Vec<_>>()
            .join("\n");
        if text.starts_with('<') {
            return vec![];
        }
        self.codex_user(&text)
    }

    /// Where a sub-agent stands (`sub_agent_activity`: started, interacted;
    /// the `SubAgentActivity` item: completed), on the tool that launched it.
    fn sub_agent(&mut self, p: &Value) -> Vec<Value> {
        let thread = string(&p["agent_thread_id"]).to_string();
        if p["kind"] == "started" && p["event_id"].is_string() {
            let call = string(&p["event_id"]).to_string();
            self.agents.insert(thread.clone(), call.clone());
            return vec![json!({"type":"tool", "id":call, "agent":thread})];
        }
        let Some(call) = self.agents.get(&thread) else {
            return vec![];
        };
        let status = if p["kind"] == "completed" {
            "completed"
        } else {
            "running"
        };
        vec![json!({"type":"tool", "id":call, "status":status})]
    }

    fn compacted(&mut self) -> Vec<Value> {
        self.said += 1;
        vec![
            json!({"type":"tool", "id":format!("compact-{}", self.said), "name":"compact", "kind":"think",
            "title":"Contexte résumé", "status":"completed"}),
        ]
    }

    /// Codex's tool calls (`response_item`): an `exec` script, another
    /// function, their outputs.
    fn codex_call(&mut self, p: &Value) -> Vec<Value> {
        let call = string(&p["call_id"]).to_string();
        match string(&p["type"]) {
            "message" if p["role"] == "developer" || p["role"] == "user" => {
                let value: String = p["content"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter(|b| b["type"] == "input_text")
                    .filter_map(|b| b["text"].as_str())
                    .collect();
                if value.starts_with("<hook_prompt")
                    || value.starts_with("Messages de l'utilisateur via Mikky :\n")
                {
                    return self.codex_hook_context(&value);
                }
                vec![]
            }
            "custom_tool_call" if p["name"] == "exec" => {
                self.codex_exec = true;
                let script = string(&p["input"]);
                if let Some(shell) = codex_script::poll_of(script)
                    && let Some(tool) = self.shells.get(&shell)
                {
                    self.calls.insert(call, tool.clone());
                    return vec![];
                }
                self.calls.insert(call.clone(), call.clone());
                let tool = codex_script::script_tool(&call, script);
                if tool["name"] == "apply_patch" {
                    self.patch = Some(call);
                }
                vec![tool]
            }
            // Codex Desktop asks and goes on; the answer comes as a message.
            "function_call" if p["name"] == "request_user_input_async" => {
                let args =
                    serde_json::from_str::<Value>(string(&p["arguments"])).unwrap_or_default();
                let questions: Vec<Value> = args["questions"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .enumerate()
                    .map(|(i, q)| {
                        let choices: Vec<Value> = q["options"]
                            .as_array()
                            .into_iter()
                            .flatten()
                            .map(|o| json!({"value":o.as_str().unwrap_or(string(&o["label"])), "description":""}))
                            .collect();
                        json!({"key":format!("q{}", i + 1), "text":string(&q["title"]), "title":null,
                            "multiple":false, "otherKey":null, "choices":choices})
                    })
                    .collect();
                if questions.is_empty() {
                    return vec![];
                }
                let message = questions[0]["text"].clone();
                self.asked = Some(call.clone());
                vec![
                    json!({"type":"question", "id":call, "message":message, "questions":questions}),
                ]
            }
            "reasoning" if !self.codex_items => {
                let summary: Vec<Value> = p["summary"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .map(|b| b["text"].clone())
                    .collect();
                thought(string(&p["id"]), &json!(summary))
            }
            // A sub-agent: its tool runs until Codex says it is done.
            "function_call" if p["name"] == "spawn_agent" => {
                let args =
                    serde_json::from_str::<Value>(string(&p["arguments"])).unwrap_or_default();
                vec![
                    json!({"type":"tool", "id":call, "name":"agent", "kind":"other",
                    "title":args["task_name"].as_str().unwrap_or("Sous-agent"), "status":"running"}),
                ]
            }
            "function_call" if p["namespace"] == "collaboration" => {
                let args =
                    serde_json::from_str::<Value>(string(&p["arguments"])).unwrap_or_default();
                let target = args["target"].as_str().unwrap_or("");
                let title = match string(&p["name"]) {
                    "send_message" | "followup_task" => format!("Écrit à {target}"),
                    "wait_agent" => "Attend ses sous-agents".to_string(),
                    "list_agents" => "Liste ses sous-agents".to_string(),
                    name => name.to_string(),
                };
                self.calls.insert(call.clone(), call.clone());
                vec![
                    json!({"type":"tool", "id":call, "name":p["name"], "kind":"other", "title":title, "status":"running"}),
                ]
            }
            "function_call" if p["name"] == "wait" => {
                let args =
                    serde_json::from_str::<Value>(string(&p["arguments"])).unwrap_or_default();
                let cell = args["cell_id"]
                    .as_str()
                    .map(str::to_owned)
                    .unwrap_or_else(|| args["cell_id"].to_string());
                if let Some(tool) = self.cells.remove(&cell) {
                    self.calls.insert(call, tool);
                }
                vec![]
            }
            "custom_tool_call" | "function_call" => {
                let args =
                    serde_json::from_str::<Value>(string(&p["arguments"])).unwrap_or_default();
                let name = string(&p["name"]);
                let title = args["title"]
                    .as_str()
                    .map(str::to_owned)
                    .unwrap_or_else(|| match string(&p["namespace"]).strip_prefix("mcp__") {
                        Some(server) => format!("{server} · {name}"),
                        None => name.to_string(),
                    });
                self.calls.insert(call.clone(), call.clone());
                vec![
                    json!({"type":"tool", "id":call, "name":name, "kind":"other", "title":title, "status":"running"}),
                ]
            }
            "custom_tool_call_output" | "function_call_output" => {
                let Some(tool) = self.calls.remove(&call) else {
                    return vec![];
                };
                let o = codex_script::outcome(&p["output"]);
                let mut event = json!({"type":"tool", "id":tool, "output":o.output});
                if let Some(cell) = o.cell {
                    self.cells.insert(cell, tool);
                } else if let Some(shell) = o.shell {
                    self.shells.insert(shell, tool);
                } else {
                    self.shells.retain(|_, t| *t != tool);
                    event["status"] = json!(if o.failed { "failed" } else { "completed" });
                }
                if string(&event["output"]).is_empty() {
                    event["output"] = Value::Null;
                }
                vec![event]
            }
            _ => vec![],
        }
    }

    /// HookPrompt's XML rendering in response items; decode XML text only,
    /// then reuse the stable message IDs to ignore the item/event echoes.
    fn codex_hook_context(&mut self, value: &str) -> Vec<Value> {
        if !value.starts_with("<hook_prompt") {
            return self.hook_messages.read_text(value);
        }
        let Some((_, content)) = value.split_once('>') else {
            return vec![];
        };
        let Some((body, _)) = content.rsplit_once("</hook_prompt>") else {
            return vec![];
        };
        let decoded = body
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&apos;", "'")
            .replace("&amp;", "&");
        self.hook_messages.read_text(&decoded)
    }
}

/// The software a Codex session runs in, from its `originator`.
pub(super) fn codex_app(originator: &str) -> Option<&'static str> {
    let o = originator.to_lowercase();
    match o.as_str() {
        "codex_cli_rs" | "codex_exec" => Some("terminal"),
        o if o.contains("vscode") => Some("vscode"),
        o if o.contains("desktop") => Some("codex"),
        _ => None,
    }
}

/// Who launched a Codex sub-agent, from its `session_meta`: a task of
/// another session (`agent_path: /root/review`, a nickname), or the
/// reviewer Codex runs before a risky action (`guardian_review`).
fn codex_parent(p: &Value) -> Value {
    let path = string(&p["agent_path"]);
    let name = p["agent_nickname"]
        .as_str()
        .map(str::to_owned)
        .or_else(|| {
            path.rsplit('/')
                .next()
                .filter(|n| !n.is_empty())
                .map(str::to_owned)
        })
        .unwrap_or_else(|| match string(&p["thread_source"]) {
            "guardian_review" => "Relecteur".into(),
            _ => "Sous-agent".into(),
        });
    let kind = if path.is_empty() {
        string(&p["thread_source"])
    } else {
        path
    };
    json!({"session":p["parent_thread_id"], "agent":p["id"], "tool":null, "name":name, "type":kind})
}

/// Codex's reasoning, as the thread's greyed thought: its summary titles
/// (often none).
fn thought(id: &str, summary: &Value) -> Vec<Value> {
    let text = summary
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(|t| t.trim().trim_matches('*').trim())
        .filter(|t| !t.is_empty())
        .collect::<Vec<_>>()
        .join("\n");
    if text.is_empty() {
        return vec![];
    }
    vec![json!({"type":"message", "text":text, "id":id, "thought":true})]
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

#[cfg(test)]
mod tests;
