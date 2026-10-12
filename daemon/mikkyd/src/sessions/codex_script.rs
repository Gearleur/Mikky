//! Codex runs its tools through small JavaScript scripts (`exec`):
//! `text(await tools.exec_command({cmd:"rg --files", workdir:"…"}))`.
//! What a script does, and what came out of it, read from their text.
use serde_json::{Value, json};

/// One tool a script calls: its name and its argument text.
struct Call<'a> {
    name: &'a str,
    args: &'a str,
}

fn calls(script: &str) -> Vec<Call<'_>> {
    let mut out = vec![];
    let mut rest = script;
    while let Some(at) = rest.find("tools.") {
        let after = &rest[at + 6..];
        let end = after
            .find(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .unwrap_or(after.len());
        let name = &after[..end];
        let tail = &after[end..];
        if !name.is_empty() && tail.starts_with('(') {
            let args = &tail[1..];
            // The arguments run to the next call (a script rarely has more).
            let stop = args.find("tools.").unwrap_or(args.len());
            out.push(Call {
                name,
                args: &args[..stop],
            });
        }
        rest = tail;
    }
    out
}

/// The JavaScript string literal at the start of [s] (after blanks).
fn literal(s: &str) -> Option<String> {
    let s = s.trim_start();
    let quote = s.chars().next().filter(|c| matches!(c, '"' | '\'' | '`'))?;
    let mut out = String::new();
    let mut chars = s[1..].chars();
    while let Some(c) = chars.next() {
        match c {
            '\\' => match chars.next()? {
                'n' => out.push('\n'),
                't' => out.push('\t'),
                'r' => out.push('\r'),
                'u' => {
                    let hex: String = chars.by_ref().take(4).collect();
                    out.push(char::from_u32(u32::from_str_radix(&hex, 16).ok()?)?);
                }
                c => out.push(c),
            },
            c if c == quote => return Some(out),
            c => out.push(c),
        }
    }
    None
}

/// The string given for [key] in an argument object: `key:"…"` or `"key":"…"`.
fn field(args: &str, key: &str) -> Option<String> {
    for pattern in [format!("\"{key}\":"), format!("{key}:")] {
        let mut rest = args;
        while let Some(at) = rest.find(&pattern) {
            let before = rest[..at].chars().last();
            let after = &rest[at + pattern.len()..];
            if !before.is_some_and(|c| c.is_ascii_alphanumeric() || c == '_')
                && let Some(value) = literal(after)
            {
                return Some(value);
            }
            rest = after;
        }
    }
    None
}

fn basename(v: &str) -> &str {
    v.rsplit(['/', '\\']).next().unwrap_or(v)
}

/// What a shell command does, from its first word, like Codex's own
/// `parsed_cmd`: it reads a file, looks for something, or runs.
pub fn command_kind(command: &str) -> &'static str {
    let first = command
        .trim_start()
        .split(|c: char| c.is_whitespace() || c == ';')
        .next()
        .unwrap_or("")
        .to_lowercase();
    match first.as_str() {
        "get-content" | "gc" | "cat" | "type" | "head" | "tail" | "sed" | "nl" | "less" => "read",
        "rg" | "grep" | "select-string" | "get-childitem" | "gci" | "ls" | "dir" | "find"
        | "fd" | "tree" => "search",
        _ => "execute",
    }
}

/// The paths an `apply_patch` touches, in order.
fn patch_files(patch: &str) -> Vec<&str> {
    patch
        .lines()
        .filter_map(|l| {
            ["*** Update File: ", "*** Add File: ", "*** Delete File: "]
                .iter()
                .find_map(|p| l.strip_prefix(p))
        })
        .map(str::trim)
        .collect()
}

/// The tool event for a script's start: what it does first, its kind,
/// how many other calls it makes.
pub fn script_tool(id: &str, script: &str) -> Value {
    let calls = calls(script);
    let more = calls.len().saturating_sub(1);
    let Some(first) = calls.first() else {
        return json!({"type":"tool", "id":id, "name":"exec", "kind":"other", "title":"Script", "status":"running"});
    };
    let (kind, title, command, path) = match first.name {
        "exec_command" => {
            let cmd = field(first.args, "cmd").unwrap_or_default();
            (command_kind(&cmd), cmd.clone(), Some(cmd), None)
        }
        "apply_patch" => {
            let patch = literal(first.args).unwrap_or_default();
            let files = patch_files(&patch);
            let path = files.first().map(|p| p.to_string());
            let title = match files.as_slice() {
                [] => "Modifie des fichiers".to_string(),
                [one] => format!("Edit {}", basename(one)),
                [one, rest @ ..] => format!("Edit {} +{}", basename(one), rest.len()),
            };
            ("edit", title, None, path)
        }
        "view_image" => {
            let path = field(first.args, "path");
            let title = format!(
                "Regarde {}",
                path.as_deref().map(basename).unwrap_or("une image")
            );
            ("read", title, None, path)
        }
        "web__run" => {
            let query = field(first.args, "q").or_else(|| field(first.args, "url"));
            (
                "fetch",
                query.unwrap_or_else(|| "Cherche sur le web".into()),
                None,
                None,
            )
        }
        "write_stdin" => ("execute", "Suit une commande".into(), None, None),
        name => match name.strip_prefix("mcp__").and_then(|n| n.split_once("__")) {
            Some((server, tool)) => ("other", format!("{server} · {tool}"), None, None),
            None => ("other", name.to_string(), None, None),
        },
    };
    let title = if more > 0 && first.name != "apply_patch" {
        format!("{title} (+{more})")
    } else {
        title
    };
    json!({"type":"tool", "id":id, "name":first.name, "kind":kind, "title":title, "status":"running",
        "command":command, "path":path})
}

/// A script that only waits on a command started earlier
/// (`write_stdin` to its shell): the shell it waits on.
pub fn poll_of(script: &str) -> Option<i64> {
    let calls = calls(script);
    let shell = calls.first().filter(|c| c.name == "write_stdin")?;
    if calls.iter().any(|c| c.name != "write_stdin") {
        return None;
    }
    let args = shell.args;
    let at = args.find("session_id")? + "session_id".len();
    let digits: String = args[at..]
        .trim_start_matches(['"', ':', ' '])
        .chars()
        .take_while(char::is_ascii_digit)
        .collect();
    digits.parse().ok()
}

/// What came out of a script.
#[derive(Default, Debug, PartialEq)]
pub struct Outcome {
    /// Still running in the background: the cell to `wait` on.
    pub cell: Option<String>,
    /// A command still running in its shell (`write_stdin` to follow).
    pub shell: Option<i64>,
    pub failed: bool,
    pub output: String,
}

const MAX_OUTPUT: usize = 4000;

fn collect(v: &Value, o: &mut Outcome) {
    match v {
        Value::Object(m) => {
            if let Some(text) = m.get("output").and_then(Value::as_str) {
                o.output.push_str(text);
            }
            match m.get("exit_code").and_then(Value::as_i64) {
                Some(0) => {}
                Some(_) => o.failed = true,
                None => {
                    if let Some(shell) = m.get("session_id").and_then(Value::as_i64) {
                        o.shell = Some(shell);
                    }
                }
            }
            if m.get("isError") == Some(&json!(true)) {
                o.failed = true;
            }
            for (k, v) in m {
                if k != "output" {
                    collect(v, o);
                }
            }
        }
        Value::Array(a) => a.iter().for_each(|v| collect(v, o)),
        _ => {}
    }
}

/// Reads a script's output: `Script completed` / `Script failed` /
/// `Script running with cell ID 9`, then what its tools gave back (often
/// a JSON `{"exit_code":0,"output":"…"}`).
pub fn outcome(output: &Value) -> Outcome {
    let mut o = Outcome::default();
    let texts: Vec<&str> = match output {
        Value::String(s) => vec![s.as_str()],
        Value::Array(a) => a.iter().filter_map(|b| b["text"].as_str()).collect(),
        _ => vec![],
    };
    for (i, text) in texts.iter().enumerate() {
        if i == 0 && text.starts_with("Script ") {
            let head = text.lines().next().unwrap_or("");
            if let Some(cell) = head.strip_prefix("Script running with cell ID ") {
                o.cell = Some(cell.trim().to_string());
            }
            if head.starts_with("Script failed") {
                o.failed = true;
                if let Some((_, rest)) = text.split_once("Output:\n") {
                    o.output.push_str(rest);
                }
            }
            continue;
        }
        match serde_json::from_str::<Value>(text) {
            Ok(v) if v.is_object() || v.is_array() => collect(&v, &mut o),
            _ => o.output.push_str(text),
        }
    }
    if o.output.len() > MAX_OUTPUT {
        let mut end = MAX_OUTPUT;
        while !o.output.is_char_boundary(end) {
            end -= 1;
        }
        o.output.truncate(end);
        o.output.push('…');
    }
    o
}

/// The parts of a unified diff: for each `@@ -a,b +c,d @@`, the text
/// before and after (context lines in both) and the line of the file it
/// starts at (before; after for a pure insertion).
fn hunks(path: &str, diff: &str) -> Vec<Value> {
    let mut out = vec![];
    let mut part: Option<(usize, Vec<&str>, Vec<&str>)> = None;
    let mut push = |part: Option<(usize, Vec<&str>, Vec<&str>)>| {
        if let Some((line, old, new)) = part {
            let text =
                |lines: Vec<&str>| lines.iter().map(|l| format!("{l}\n")).collect::<String>();
            out.push(json!({"path":path, "old":text(old), "new":text(new), "line":line}));
        }
    };
    for l in diff.lines() {
        if let Some(head) = l.strip_prefix("@@ -") {
            push(part.take());
            let number = |s: &str| -> (usize, usize) {
                let mut it = s.split(',');
                let start = it.next().and_then(|n| n.parse().ok()).unwrap_or(1);
                (start, it.next().and_then(|n| n.parse().ok()).unwrap_or(1))
            };
            let mut sides = head.split(' ');
            let (old_start, old_len) = number(sides.next().unwrap_or(""));
            let (new_start, _) = number(sides.next().unwrap_or("").trim_start_matches('+'));
            let line = if old_len == 0 { new_start } else { old_start };
            part = Some((line.max(1), vec![], vec![]));
        } else if let Some((_, old, new)) = part.as_mut() {
            match l.chars().next() {
                Some('-') => old.push(&l[1..]),
                Some('+') => new.push(&l[1..]),
                Some(' ') => {
                    old.push(&l[1..]);
                    new.push(&l[1..]);
                }
                // `\ No newline at end of file`.
                Some('\\') => {}
                _ => {
                    old.push(l);
                    new.push(l);
                }
            }
        }
    }
    push(part);
    out
}

/// What a Codex file change did to each file (`changes`: path →
/// `{type: add | delete | update, content | unified_diff}`): its tool
/// kind and its diffs, in the `diff` format of the wire.
pub fn file_changes(changes: &Value) -> Vec<(String, &'static str, Vec<Value>)> {
    let Some(files) = changes.as_object() else {
        return vec![];
    };
    files
        .iter()
        .map(|(path, c)| {
            let content = c["content"].as_str().unwrap_or("");
            match c["type"].as_str() {
                Some("add") => (
                    path.clone(),
                    "edit",
                    vec![json!({"path":path, "old":null, "new":content, "line":1})],
                ),
                Some("delete") => (
                    path.clone(),
                    "delete",
                    vec![json!({"path":path, "old":content, "new":"", "line":1})],
                ),
                _ => (
                    path.clone(),
                    "edit",
                    hunks(path, c["unified_diff"].as_str().unwrap_or("")),
                ),
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_unified_diff_gives_each_part_with_its_line() {
        let changes = json!({
            "C:\\p\\a.dart": {"type":"update","move_path":null,"unified_diff":
                "@@ -10,2 +10,5 @@\n \n+/// Flat.\n+enum Look { raised, flat }\n+\n /// An app.\n@@ -16,3 +19,3 @@\n class A {\n-  const A();\n+  const A({this.look});\n }\n\\ No newline at end of file\n"},
            "C:\\p\\b.txt": {"type":"add","content":"un\n"},
            "C:\\p\\c.txt": {"type":"delete","content":"vieux\n"},
            "C:\\p\\d.md": {"type":"update","unified_diff":"@@ -8,0 +9,2 @@\n+dist/\n+build/\n"}
        });
        let files = file_changes(&changes);
        let (path, kind, a) = &files[0];
        assert_eq!((path.as_str(), *kind), ("C:\\p\\a.dart", "edit"));
        assert_eq!(a.len(), 2);
        assert_eq!(a[0]["line"], 10);
        assert_eq!(a[0]["old"], "\n/// An app.\n");
        assert_eq!(
            a[0]["new"],
            "\n/// Flat.\nenum Look { raised, flat }\n\n/// An app.\n"
        );
        assert_eq!(a[1]["line"], 16);
        assert_eq!(a[1]["old"], "class A {\n  const A();\n}\n");
        assert!(files[1].2[0]["old"].is_null());
        assert_eq!(files[2].1, "delete");
        assert_eq!(files[2].2[0]["new"], "");
        // A pure insertion is numbered where it lands.
        assert_eq!(files[3].2[0]["line"], 9);
        assert_eq!(files[3].2[0]["old"], "");
    }

    #[test]
    fn a_command_script_says_its_command_and_kind() {
        let t = script_tool(
            "c1",
            "text(await tools.exec_command({cmd:\"rg --files -g '*home*'\",\"workdir\":\"C:\\\\p\",\"max_output_tokens\":4000}));\n",
        );
        assert_eq!(t["title"], "rg --files -g '*home*'");
        assert_eq!(t["kind"], "search");
        assert_eq!(t["status"], "running");
        let t = script_tool(
            "c2",
            "text(await tools.exec_command({cmd:\"Get-Content a.dart; Get-Content b.dart\",\"workdir\":\"C:\\\\p\"}));\ntext(await tools.exec_command({cmd:\"git status\"}));\n",
        );
        assert_eq!(t["title"], "Get-Content a.dart; Get-Content b.dart (+1)");
        assert_eq!(t["kind"], "read");
        assert_eq!(command_kind("cargo test"), "execute");
    }

    #[test]
    fn other_script_tools() {
        let patch = script_tool(
            "p",
            "text(await tools.apply_patch(\"*** Begin Patch\\n*** Update File: C:/p/app/lib/a.dart\\n@@\\n-x\\n+y\\n*** Add File: C:/p/b.dart\\n+z\\n*** End Patch\"));\n",
        );
        assert_eq!(patch["title"], "Edit a.dart +1");
        assert_eq!(patch["kind"], "edit");
        assert_eq!(patch["path"], "C:/p/app/lib/a.dart");
        let image = script_tool(
            "i",
            "const r=await tools.view_image({path:\"C:\\\\p\\\\shot.png\"});image(r.image_url);\n",
        );
        assert_eq!(image["title"], "Regarde shot.png");
        let web = script_tool(
            "w",
            "const r = await tools.web__run({search_query:[\n {q:\"sqlite fts5\"}]});",
        );
        assert_eq!(web["title"], "sqlite fts5");
        assert_eq!(web["kind"], "fetch");
        let mcp = script_tool(
            "m",
            "text(await tools.mcp__codex_app__read_thread({id:\"x\"}));",
        );
        assert_eq!(mcp["title"], "codex_app · read_thread");
        assert_eq!(script_tool("s", "console.log(1)")["title"], "Script");
    }

    #[test]
    fn a_poll_names_its_shell() {
        assert_eq!(
            poll_of(
                "const r=await tools.write_stdin({session_id:52395,chars:\"\",yield_time_ms:30000});text(r);\n"
            ),
            Some(52395)
        );
        assert_eq!(
            poll_of("text(await tools.exec_command({cmd:\"ls\"}));"),
            None
        );
    }

    #[test]
    fn script_outcomes() {
        let done = outcome(&json!([
            {"type":"input_text","text":"Script completed\nWall time 0.5 seconds\nOutput:\n"},
            {"type":"input_text","text":"{\"chunk_id\":\"81598f\",\"wall_time_seconds\":0.02,\"exit_code\":0,\"original_token_count\":63,\"output\":\"app\\\\lib\\\\a.dart\\n\"}"}
        ]));
        assert_eq!(done.output, "app\\lib\\a.dart\n");
        assert!(!done.failed);
        let failed = outcome(&json!([
            {"type":"input_text","text":"Script completed\nWall time 0.5 seconds\nOutput:\n"},
            {"type":"input_text","text":"{\"exit_code\":1,\"output\":\"error\"}"}
        ]));
        assert!(failed.failed);
        let running = outcome(&json!(
            "Script running with cell ID 308\nWall time 31.0 seconds\nOutput:\n"
        ));
        assert_eq!(running.cell.as_deref(), Some("308"));
        let shell = outcome(&json!([
            {"type":"input_text","text":"Script completed\nWall time 0.0 seconds\nOutput:\n"},
            {"type":"input_text","text":"{\"chunk_id\":\"228a30\",\"wall_time_seconds\":30.0,\"session_id\":52395,\"original_token_count\":133,\"output\":\"building\"}"}
        ]));
        assert_eq!(shell.shell, Some(52395));
        assert!(!shell.failed);
        let script_failed = outcome(&json!([
            {"type":"input_text","text":"Script failed\nWall time 0.1 seconds\nOutput:\nTypeError: x is undefined"}
        ]));
        assert!(script_failed.failed);
        assert_eq!(script_failed.output, "TypeError: x is undefined");
    }
}
