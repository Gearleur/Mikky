//! Provider formats are decoded once, in Rust. The screen only folds events.
mod codex;

use serde_json::{Value, json};
use std::collections::{HashMap, HashSet};

#[derive(Default)]
pub struct Reader {
    started: bool,
    cwd: bool,
    app: bool,
    turn: bool,
    user_in_turn: bool,
    plan_tools: HashSet<String>,
    tasks: Vec<(String, Value)>,
    /// Codex runs its tools in `exec` scripts: its `CommandExecution` items
    /// then repeat them.
    codex_exec: bool,
    /// Codex writes its messages as items (`item_completed`): its plain
    /// message events then repeat them.
    codex_items: bool,
    /// Codex messages without an id so far.
    said: usize,
    /// Codex calls waiting for their output: the tool each one reports on
    /// (itself, or the command a poll waits for).
    calls: HashMap<String, String>,
    /// Scripts and commands that went on in the background: by cell and by
    /// shell, the tool they belong to.
    cells: HashMap<String, String>,
    shells: HashMap<i64, String>,
    /// The `apply_patch` script whose file changes Codex will report.
    patch: Option<String>,
    /// The question Codex asked, until the user answers.
    asked: Option<String>,
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
        let app = claude_app(string(&line["entrypoint"]));
        if line["sessionId"].is_string()
            && (!self.started
                || (!self.cwd && line["cwd"].is_string())
                || (!self.app && app.is_some()))
        {
            self.started = true;
            self.cwd |= line["cwd"].is_string();
            self.app |= app.is_some();
            out.push(
                json!({"type":"session", "id":line["sessionId"], "cwd":line["cwd"], "app":app}),
            );
        }
        match string(&line["type"]) {
            // The summary Claude writes after compacting is not a message
            // from the user: it would cut the task in two.
            "user" if line["isMeta"] != true && line["isCompactSummary"] != true => {
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
                                    let mut tool = json!({"type":"tool", "id":b["tool_use_id"], "status": if b["is_error"] == true { "failed" } else { "completed" }, "output": text(&b["content"])});
                                    if let Some(diff) = claude_change(&line["toolUseResult"]) {
                                        tool["diff"] = diff;
                                    }
                                    out.push(tool);
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
}

/// The software a Claude session runs in, from its `entrypoint`.
fn claude_app(entrypoint: &str) -> Option<&'static str> {
    match entrypoint {
        "cli" => Some("terminal"),
        e if e.contains("vscode") => Some("vscode"),
        e if e.contains("desktop") => Some("claude"),
        _ => None,
    }
}

/// The change a file tool of Claude made, from what its session keeps of
/// it once done (`toolUseResult`): where it is in the file. An edit: its
/// old and new strings and the line they start at in the file as it was;
/// a file written over: the whole file before and after. None when the
/// session does not say.
fn claude_change(result: &Value) -> Option<Value> {
    let path = result["filePath"].as_str()?;
    let original = result["originalFile"].as_str()?;
    if let (Some(old), Some(new)) = (result["oldString"].as_str(), result["newString"].as_str()) {
        let at = original.find(old)?;
        let line = original[..at].matches('\n').count() + 1;
        return Some(json!({"path":path, "old":old, "new":new, "line":line}));
    }
    let content = result["content"].as_str()?;
    (result["type"] == "update")
        .then(|| json!({"path":path, "old":original, "new":content, "line":1}))
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
    use super::codex::codex_app;
    use super::*;

    #[test]
    fn claude_compact_summary_does_not_cut_the_turn() {
        let mut r = Reader::default();
        let user = |text: &str| json!({"type":"user","sessionId":"s","message":{"content":text}});
        assert_eq!(
            r.read("claude", &user("Corrige le bug"))[1]["type"],
            "start"
        );
        let mut summary = user("This session is being continued from a previous conversation…");
        summary["isCompactSummary"] = json!(true);
        assert!(r.read("claude", &summary).is_empty());
        let out = r.read(
            "claude",
            &json!({"type":"assistant","message":{"id":"m","stop_reason":"end_turn","content":[{"type":"text","text":"Fait."}]}}),
        );
        assert_eq!(out.last().unwrap()["reason"], "endTurn");
    }

    #[test]
    fn a_finished_edit_says_where_it_is_in_the_file() {
        let result = |tool_result: Value| {
            let mut r = Reader::default();
            r.read(
                "claude",
                &json!({"type":"user","sessionId":"s","message":{"content":"Go"}}),
            );
            r.read(
                "claude",
                &json!({"type":"user","sessionId":"s","toolUseResult":tool_result,
                    "message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}),
            )
        };
        let out = result(
            json!({"filePath":"/a/b.dart","oldString":"x = 1;","newString":"x = 2;",
            "originalFile":"one\ntwo\n  x = 1;\nend\n"}),
        );
        assert_eq!(out[0]["diff"]["line"], 3);
        assert_eq!(out[0]["diff"]["old"], "x = 1;");
        // A file written over: the whole of it, before and after.
        let out = result(
            json!({"type":"update","filePath":"/a/b.dart","content":"new\n","originalFile":"old\n"}),
        );
        assert_eq!(out[0]["diff"]["old"], "old\n");
        assert_eq!(out[0]["diff"]["line"], 1);
        // Nothing kept: no change sent.
        assert!(result(json!({"stdout":"ok"}))[0]["diff"].is_null());
    }

    #[test]
    fn the_software_a_session_runs_in() {
        let mut r = Reader::default();
        let out = r.read("claude", &json!({"type":"user","sessionId":"s","cwd":"/a","entrypoint":"claude-vscode","message":{"content":"Go"}}));
        assert_eq!(out[0]["app"], "vscode");
        let mut r = Reader::default();
        let out = r.read("codex", &json!({"type":"session_meta","payload":{"id":"c","cwd":"/a","originator":"Codex Desktop"}}));
        assert_eq!(out[0]["app"], "codex");
        assert_eq!(codex_app("codex_exec"), Some("terminal"));
        assert_eq!(claude_app("cli"), Some("terminal"));
        assert_eq!(claude_app("sdk-ts"), None);
    }
}
