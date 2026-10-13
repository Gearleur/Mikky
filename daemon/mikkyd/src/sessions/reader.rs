//! Provider formats are decoded once, in Rust. The screen only folds events.
mod codex;
mod hook_messages;

use serde_json::{Value, json};
use std::collections::{HashMap, HashSet};

#[derive(Default)]
pub struct Reader {
    hook_messages: hook_messages::Messages,
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
    /// Codex's sub-agents: by thread, the call that launched each.
    agents: HashMap<String, String>,
    pub first_message: Option<String>,
    /// A sub-agent's link to who launched it: `{session, agent, tool, name,
    /// type}`; null for a main session.
    pub parent: Option<Value>,
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
        if provider == "claude" {
            let messages = self.hook_messages.read(line);
            if !messages.is_empty() && !self.turn {
                self.turn = true;
                events.push(json!({"type":"start"}));
            }
            events.extend(messages);
        }
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
        // A main file may hold its sub-agents' lines (older Claude Code):
        // they are read from their own files.
        if line["isSidechain"] == true && self.parent.is_none() {
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
                    match s.strip_prefix("<task-notification>") {
                        Some(note) => self.notification(note, &mut out),
                        None => self.user(s, &mut out),
                    }
                } else {
                    for b in content.as_array().into_iter().flatten() {
                        match string(&b["type"]) {
                            "tool_result" => {
                                if !self.plan_tools.remove(string(&b["tool_use_id"])) {
                                    let mut tool = json!({"type":"tool", "id":b["tool_use_id"], "status": if b["is_error"] == true { "failed" } else { "completed" }, "output": text(&b["content"])});
                                    let result = &line["toolUseResult"];
                                    if let Some(diff) = claude_change(result) {
                                        tool["diff"] = diff;
                                    }
                                    // A sub-agent: which one; launched in the
                                    // background, it goes on after this.
                                    if result["agentId"].is_string() {
                                        tool["agent"] = result["agentId"].clone();
                                        if result["status"] == "async_launched" {
                                            tool["status"] = json!("running");
                                            tool["output"] = Value::Null;
                                        }
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
                if line["isApiErrorMessage"] == true
                    || line["error"] == "rate_limit"
                    || line["apiErrorStatus"] == 429
                {
                    let message = text(&message["content"]);
                    let limited = line["error"] == "rate_limit"
                        || line["apiErrorStatus"] == 429
                        || message.to_lowercase().contains("limit");
                    out.push(json!({"type":"end", "reason": if limited {"rateLimited"} else {"error"}, "message":message, "resetsAt":line["quotaLimits"]["resetsAt"]}));
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

    /// Claude Code tells the session that something it ran in the
    /// background stopped (a sub-agent, a command): that tool is done, and
    /// Claude takes a turn to read it.
    fn notification(&mut self, note: &str, out: &mut Vec<Value>) {
        let tag = |name: &str| {
            let open = format!("<{name}>");
            let start = note.find(&open)? + open.len();
            let end = note[start..].find(&format!("</{name}>"))?;
            Some(note[start..start + end].trim().to_string())
        };
        if let Some(id) = tag("tool-use-id") {
            let status = match tag("status").as_deref() {
                Some("completed") => "completed",
                _ => "failed",
            };
            out.push(json!({"type":"tool", "id":id, "status":status, "output":tag("summary")}));
        }
        if !self.turn {
            self.turn = true;
            out.push(json!({"type":"start"}));
        }
        if tag("status").as_deref() == Some("failed")
            && let Some(summary) = tag("summary")
            && (summary.contains("session limit") || summary.contains("weekly limit"))
        {
            self.turn = false;
            out.push(json!({"type":"end", "reason":"rateLimited", "message":summary}));
        }
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

    #[test]
    fn claude_session_and_weekly_limits_keep_the_exact_reset() {
        for (message, reset) in [
            (
                "You've hit your session limit · resets 2:50pm (Europe/Paris)",
                1791463800_i64,
            ),
            (
                "You've hit your weekly limit · resets Oct 2, 9pm (Europe/Paris)",
                1790967600,
            ),
        ] {
            let mut r = Reader {
                parent: Some(json!({"session":"p","agent":"a85"})),
                ..Default::default()
            };
            r.read("claude", &json!({"type":"user","sessionId":"p","agentId":"a85","isSidechain":true,"message":{"content":"Vérifie le lecteur"}}));
            let out = r.read("claude", &json!({"type":"assistant","isSidechain":true,"agentId":"a85",
                "error":"rate_limit","isApiErrorMessage":true,"apiErrorStatus":429,
                "quotaLimits":{"status":"rejected","resetsAt":reset},
                "message":{"role":"assistant","stop_reason":"stop_sequence","content":[{"type":"text","text":message}]}}));
            let end = out.last().unwrap();
            assert_eq!(end["reason"], "rateLimited");
            assert_eq!(end["resetsAt"], reset);
            assert_eq!(end["message"], message);
        }
    }

    #[test]
    fn a_claude_sub_agent_runs_until_its_notification() {
        let mut r = Reader::default();
        let user =
            |content: Value| json!({"type":"user","sessionId":"s","message":{"content":content}});
        r.read("claude", &user(json!("Lance trois sous-agents")));
        r.read(
            "claude",
            &json!({"type":"assistant","message":{"id":"m","content":[{"type":"tool_use","id":"toolu_1","name":"Agent",
                "input":{"description":"Front: island interactions","subagent_type":"general-purpose","run_in_background":true}}]}}),
        );
        let mut launched = user(
            json!([{"type":"tool_result","tool_use_id":"toolu_1","content":[{"type":"text","text":"Async agent launched successfully."}]}]),
        );
        launched["toolUseResult"] = json!({"isAsync":true,"status":"async_launched","agentId":"a85","description":"Front: island interactions"});
        let out = r.read("claude", &launched);
        assert_eq!(out[0]["agent"], "a85");
        assert_eq!(out[0]["status"], "running");
        r.read(
            "claude",
            &json!({"type":"assistant","message":{"id":"m2","stop_reason":"end_turn","content":[{"type":"text","text":"Ils travaillent."}]}}),
        );
        // Later, Claude Code tells the session; Claude reads it in a turn.
        let note = user(json!("<task-notification>
<task-id>a85</task-id>
<tool-use-id>toolu_1</tool-use-id>
<status>failed</status>
<summary>Agent \"Front\" failed: You've hit your session limit · resets 2:50pm (Europe/Paris)</summary>
</task-notification>"));
        let out = r.read("claude", &note);
        assert_eq!(out[0]["id"], "toolu_1");
        assert_eq!(out[0]["status"], "failed");
        assert!(out[0]["output"].as_str().unwrap().contains("session limit"));
        assert_eq!(out[1]["type"], "start");
        assert_eq!(out[2]["reason"], "rateLimited");
    }

    #[test]
    fn a_sub_agent_file_reads_its_sidechain_lines() {
        let line = json!({"type":"user","sessionId":"s","isSidechain":true,"agentId":"a85","message":{"content":"Tu es le sous-agent FRONT"}});
        assert!(Reader::default().read("claude", &line).is_empty());
        let mut r = Reader {
            parent: Some(json!({"session":"s","agent":"a85"})),
            ..Default::default()
        };
        assert_eq!(
            r.read("claude", &line)[2]["text"],
            "Tu es le sous-agent FRONT"
        );
    }
}
