//! Mikky's hooks in Claude Code's `settings.json` and in Codex's
//! `hooks.json` (same format; 2026-10-04), like Coucou's: never overwrite
//! them. Read, merge Mikky's entries (marked by
//! `mikky-hook` in their command) with everything else left as is, show the
//! diff, and write only what the user saw: `write` refuses a file that
//! changed since its preview. A dated backup first, then a new file beside
//! it renamed over the old one (a crash never leaves half a file).
//! Uninstalling removes Mikky's entries only.

use std::path::{Path, PathBuf};

use serde_json::{Map, Value, json};

/// Every event Mikky listens to, with the timeout written for it. The
/// permission waits for a human: the hook's own deadline (110 s) + 10 s.
/// The others only tell that the session moved on (`hooks.rs`).
const EVENTS: &[(&str, u64)] = &[
    ("PermissionRequest", 120),
    ("PostToolUse", 10),
    ("UserPromptSubmit", 10),
    ("Stop", 10),
    ("SessionEnd", 10),
];

const MARKER: &str = "mikky-hook";

/// Whose hooks.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Tool {
    Claude,
    Codex,
}

impl Tool {
    pub fn named(name: &str) -> Option<Tool> {
        match name {
            "claude" => Some(Tool::Claude),
            "codex" => Some(Tool::Codex),
            _ => None,
        }
    }

    /// `~/.claude/settings.json` (or in `CLAUDE_CONFIG_DIR`),
    /// `~/.codex/hooks.json` (or in `CODEX_HOME`).
    pub fn file(self) -> PathBuf {
        let home = || {
            std::env::var_os("USERPROFILE")
                .or_else(|| std::env::var_os("HOME"))
                .map(PathBuf::from)
                .unwrap_or_default()
        };
        match self {
            Tool::Claude => std::env::var_os("CLAUDE_CONFIG_DIR")
                .map(PathBuf::from)
                .unwrap_or_else(|| home().join(".claude"))
                .join("settings.json"),
            Tool::Codex => std::env::var_os("CODEX_HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| home().join(".codex"))
                .join("hooks.json"),
        }
    }
}

const HOOK_NAME: &str = if cfg!(windows) {
    "mikky-hook.exe"
} else {
    "mikky-hook"
};

/// The relay shipped next to `mikkyd` (a new folder at each build).
fn shipped_hook() -> PathBuf {
    std::env::current_exe()
        .unwrap_or_default()
        .with_file_name(HOOK_NAME)
}

/// Where the hooks call it: a fixed place, so that a new build of Mikky
/// does not leave Claude calling an old folder.
pub fn hook_path() -> PathBuf {
    let base = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")))
        .unwrap_or_default();
    base.join("Mikky").join("bin").join(HOOK_NAME)
}

/// Copies the shipped relay to [hook_path] (beside it, then renamed over
/// it). A relay in use (a hook running) stays: it is replaced next time.
fn place_hook() -> Result<PathBuf, String> {
    let from = shipped_hook();
    let to = hook_path();
    if !from.exists() {
        return if to.exists() {
            Ok(to)
        } else {
            Err(format!("{} manque : réinstalle Mikky.", from.display()))
        };
    }
    if let Some(dir) = to.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let temp = to.with_extension(format!("new-{}", std::process::id()));
    std::fs::copy(&from, &temp).map_err(|e| format!("copie du relais impossible : {e}"))?;
    if std::fs::rename(&temp, &to).is_err() {
        let _ = std::fs::remove_file(&temp);
        if !to.exists() {
            return Err("copie du relais impossible".into());
        }
    }
    Ok(to)
}

fn command(hook: &Path, tool: Tool, event: &str) -> String {
    // Run through a shell: forward slashes, quoted.
    let exe = hook.to_string_lossy().replace('\\', "/");
    match tool {
        Tool::Claude => format!("\"{exe}\" {event}"),
        Tool::Codex => format!("\"{exe}\" --agent codex {event}"),
    }
}

fn parse(bytes: &[u8]) -> Result<Value, String> {
    let bytes = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF][..]).unwrap_or(bytes);
    if bytes.iter().all(u8::is_ascii_whitespace) {
        return Ok(json!({}));
    }
    match serde_json::from_slice::<Value>(bytes) {
        Ok(v) if v.is_object() => Ok(v),
        Ok(_) => Err("le fichier n’est pas un objet JSON : rien n’a été touché.".into()),
        Err(e) => Err(format!("fichier illisible ({e}) : rien n’a été touché.")),
    }
}

fn read(path: &Path) -> Result<(Value, Vec<u8>), String> {
    match std::fs::read(path) {
        Ok(bytes) => Ok((parse(&bytes)?, bytes)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok((json!({}), Vec::new())),
        Err(e) => Err(format!("lecture de {} impossible : {e}", path.display())),
    }
}

fn is_ours(entry: &Value) -> bool {
    entry["hooks"].as_array().is_some_and(|h| {
        h.iter()
            .any(|h| h["command"].as_str().is_some_and(|c| c.contains(MARKER)))
    })
}

fn merged(existing: &Value, hook: &Path, tool: Tool) -> Value {
    let mut root = existing.as_object().cloned().unwrap_or_default();
    let mut hooks = root
        .get("hooks")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_else(Map::new);
    for (event, timeout) in EVENTS {
        let mut list = hooks
            .get(*event)
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        list.retain(|e| !is_ours(e));
        let mut entry =
            json!({"type": "command", "command": command(hook, tool, event), "timeout": timeout});
        if tool == Tool::Codex && *event == "PermissionRequest" {
            // Shown by Codex while it waits.
            entry["statusMessage"] = json!("En attente de ta réponse dans Mikky");
        }
        list.push(json!({"hooks": [entry]}));
        hooks.insert((*event).into(), Value::Array(list));
    }
    root.insert("hooks".into(), Value::Object(hooks));
    Value::Object(root)
}

fn without_ours(existing: &Value) -> Value {
    let mut root = existing.as_object().cloned().unwrap_or_default();
    let Some(hooks) = root.get("hooks").and_then(Value::as_object).cloned() else {
        return Value::Object(root);
    };
    let mut out = Map::new();
    for (event, value) in hooks {
        match value.as_array() {
            Some(list) => {
                let kept: Vec<_> = list.iter().filter(|e| !is_ours(e)).cloned().collect();
                if !kept.is_empty() {
                    out.insert(event, Value::Array(kept));
                }
            }
            None => {
                out.insert(event, value);
            }
        }
    }
    if out.is_empty() {
        root.remove("hooks");
    } else {
        root.insert("hooks".into(), Value::Object(out));
    }
    Value::Object(root)
}

fn installed(v: &Value) -> bool {
    v["hooks"].as_object().is_some_and(|h| {
        h.values()
            .filter_map(Value::as_array)
            .flatten()
            .any(is_ours)
    })
}

fn pretty(v: &Value) -> String {
    serde_json::to_string_pretty(v).unwrap_or_default()
}

/// Which bytes a preview was made from (FNV-1a).
fn fingerprint(bytes: &[u8]) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for b in bytes {
        hash ^= *b as u64;
        hash = hash.wrapping_mul(0x0100_0000_01b3);
    }
    format!("{hash:016x}")
}

/// Installed or not, where.
pub fn status(tool: Tool) -> Value {
    let path = tool.file();
    let hook = hook_path();
    let (current, _) = read(&path).unwrap_or((json!({}), Vec::new()));
    json!({
        "installed": installed(&current),
        "settingsPath": path.to_string_lossy(),
        "hookPath": hook.to_string_lossy(),
        "hookReady": hook.exists() || shipped_hook().exists(),
    })
}

/// What installing (or uninstalling) would change.
pub fn preview(tool: Tool, install: bool) -> Result<Value, String> {
    preview_at(&tool.file(), &hook_path(), tool, install)
}

fn preview_at(path: &Path, hook: &Path, tool: Tool, install: bool) -> Result<Value, String> {
    let (current, bytes) = read(path)?;
    let next = if install {
        merged(&current, hook, tool)
    } else {
        without_ours(&current)
    };
    Ok(json!({
        "diff": unified_diff(&pretty(&current), &pretty(&next)),
        "changes": current != next,
        "settingsPath": path.to_string_lossy(),
        "fingerprint": fingerprint(&bytes),
    }))
}

/// Writes it, if the file is still the one previewed. Returns the backup.
pub fn write(tool: Tool, install: bool, seen: &str) -> Result<Value, String> {
    let hook = if install { place_hook()? } else { hook_path() };
    write_at(&tool.file(), &hook, tool, install, seen)
}

fn write_at(path: &Path, hook: &Path, tool: Tool, install: bool, seen: &str) -> Result<Value, String> {
    if install && !hook.exists() {
        return Err(format!("{} manque : réinstalle Mikky.", hook.display()));
    }
    let (current, bytes) = read(path)?;
    if fingerprint(&bytes) != seen {
        return Err(
            "le fichier a changé depuis l’aperçu : rien n’a été écrit, regarde le nouveau diff."
                .into(),
        );
    }
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let mut backup = Value::Null;
    if !bytes.is_empty() {
        let stamp = chrono::Local::now().format("%Y%m%d-%H%M%S");
        let name = path.file_name().unwrap_or_default().to_string_lossy();
        let to = path.with_file_name(format!("{name}.bak-{stamp}"));
        std::fs::write(&to, &bytes).map_err(|e| format!("sauvegarde impossible : {e}"))?;
        backup = json!(to.to_string_lossy());
    }
    let next = if install {
        merged(&current, hook, tool)
    } else {
        without_ours(&current)
    };
    let mut text = pretty(&next);
    text.push('\n');
    let temp = path.with_extension(format!("json.mikky-{}", std::process::id()));
    std::fs::write(&temp, text).map_err(|e| format!("écriture impossible : {e}"))?;
    if let Err(e) = std::fs::rename(&temp, path) {
        let _ = std::fs::remove_file(&temp);
        return Err(format!("écriture impossible : {e}"));
    }
    Ok(json!({"backup": backup}))
}

/// A unified diff with 3 lines of context, enough to read what changes.
fn unified_diff(before: &str, after: &str) -> String {
    let a: Vec<&str> = before.lines().collect();
    let b: Vec<&str> = after.lines().collect();
    // Longest common subsequence table, bottom-up (settings files are small).
    let (n, m) = (a.len(), b.len());
    let mut lcs = vec![vec![0u32; m + 1]; n + 1];
    for i in (0..n).rev() {
        for j in (0..m).rev() {
            lcs[i][j] = if a[i] == b[j] {
                lcs[i + 1][j + 1] + 1
            } else {
                lcs[i + 1][j].max(lcs[i][j + 1])
            };
        }
    }
    // (kind, text): ' ' kept, '-' removed, '+' added.
    let mut ops = Vec::new();
    let (mut i, mut j) = (0, 0);
    while i < n || j < m {
        if i < n && j < m && a[i] == b[j] {
            ops.push((' ', a[i]));
            i += 1;
            j += 1;
        } else if i < n && (j == m || lcs[i + 1][j] >= lcs[i][j + 1]) {
            // What goes, before what comes.
            ops.push(('-', a[i]));
            i += 1;
        } else {
            ops.push(('+', b[j]));
            j += 1;
        }
    }
    // Each change with 3 lines around it; « … » where lines are skipped.
    let mut shown = vec![false; ops.len()];
    for (k, op) in ops.iter().enumerate() {
        if op.0 != ' ' {
            for s in shown
                .iter_mut()
                .take((k + 4).min(ops.len()))
                .skip(k.saturating_sub(3))
            {
                *s = true;
            }
        }
    }
    let mut out = String::new();
    let mut gap = false;
    for (k, (kind, text)) in ops.iter().enumerate() {
        if !shown[k] {
            gap = true;
            continue;
        }
        if gap && !out.is_empty() {
            out.push_str("…\n");
        }
        gap = false;
        out.push(*kind);
        out.push(' ');
        out.push_str(text);
        out.push('\n');
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("mikky-settings-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn merge_keeps_everything_else_and_uninstall_removes_only_ours() {
        let hook = Path::new("C:\\Mikky\\mikky-hook.exe");
        let mine = json!({
            "env": {"A": "1"},
            "hooks": {"PostToolUse": [{"hooks": [{"type": "command", "command": "other"}]}]},
        });
        let with = merged(&mine, hook, Tool::Claude);
        assert_eq!(with["env"], json!({"A": "1"}));
        let post = with["hooks"]["PostToolUse"].as_array().unwrap();
        assert_eq!(post.len(), 2);
        assert_eq!(post[0]["hooks"][0]["command"], "other");
        assert_eq!(
            post[1]["hooks"][0]["command"],
            "\"C:/Mikky/mikky-hook.exe\" PostToolUse"
        );
        assert_eq!(
            with["hooks"]["PermissionRequest"][0]["hooks"][0]["timeout"],
            120
        );
        assert!(installed(&with));
        // Installing twice: still one entry of ours.
        assert_eq!(
            merged(&with, hook, Tool::Claude)["hooks"]["PostToolUse"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
        assert_eq!(without_ours(&with), mine);
        assert_eq!(without_ours(&merged(&json!({}), hook, Tool::Claude)), json!({}));
    }

    #[test]
    fn codex_hooks_say_which_agent_and_wait_with_a_message() {
        let hook = Path::new("C:\\Mikky\\mikky-hook.exe");
        let with = merged(&json!({}), hook, Tool::Codex);
        let ask = &with["hooks"]["PermissionRequest"][0]["hooks"][0];
        assert_eq!(
            ask["command"],
            "\"C:/Mikky/mikky-hook.exe\" --agent codex PermissionRequest"
        );
        assert!(ask["statusMessage"].as_str().unwrap().contains("Mikky"));
        assert_eq!(without_ours(&with), json!({}));
        assert!(Tool::Codex.file().ends_with("hooks.json"));
        assert_eq!(Tool::named("codex"), Some(Tool::Codex));
        assert_eq!(Tool::named("x"), None);
    }

    #[test]
    fn unreadable_settings_are_never_replaced() {
        assert!(parse(b"{ broken").is_err());
        assert!(parse(b"[1]").is_err());
        assert_eq!(parse(b"\xEF\xBB\xBF{}").unwrap(), json!({}));
        assert_eq!(parse(b"  \n").unwrap(), json!({}));
    }

    #[test]
    fn write_backs_up_and_refuses_a_file_changed_since_the_preview() {
        let dir = temp_dir("write");
        let path = dir.join("settings.json");
        let hook = dir.join("mikky-hook.exe");
        std::fs::write(&hook, b"").unwrap();
        std::fs::write(&path, b"{\"model\": \"opus\"}").unwrap();

        let p = preview_at(&path, &hook, Tool::Claude, true).unwrap();
        assert!(p["diff"].as_str().unwrap().contains("+ "));
        assert_eq!(p["changes"], true);
        std::fs::write(&path, b"{\"model\": \"sonnet\"}").unwrap();
        assert!(write_at(&path, &hook, Tool::Claude, true, p["fingerprint"].as_str().unwrap()).is_err());
        assert_eq!(
            std::fs::read_to_string(&path).unwrap(),
            "{\"model\": \"sonnet\"}"
        );

        let p = preview_at(&path, &hook, Tool::Claude, true).unwrap();
        let done = write_at(&path, &hook, Tool::Claude, true, p["fingerprint"].as_str().unwrap()).unwrap();
        let backup = done["backup"].as_str().unwrap();
        assert_eq!(
            std::fs::read_to_string(backup).unwrap(),
            "{\"model\": \"sonnet\"}"
        );
        let now: Value = serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(now["model"], "sonnet");
        assert!(installed(&now));

        let p = preview_at(&path, &hook, Tool::Claude, false).unwrap();
        write_at(&path, &hook, Tool::Claude, false, p["fingerprint"].as_str().unwrap()).unwrap();
        let now: Value = serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(now, json!({"model": "sonnet"}));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn diff_shows_changes_with_context() {
        let d = unified_diff("a\nb\nc\nd\ne\nf\ng\nh\ni", "a\nb\nc\nd\nX\nf\ng\nh\ni");
        assert!(d.contains("- e\n+ X\n"));
        assert!(d.starts_with("  b\n"));
        assert_eq!(unified_diff("same", "same"), "");
    }
}
