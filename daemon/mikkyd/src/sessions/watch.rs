//! Native file events and incremental JSONL reads, owned by the backend.
//! A dedicated thread keeps directory walking and file I/O off Tokio.
use crate::store::{HistoryRequest, Store};
use notify::{RecursiveMode, Watcher};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    fs::File,
    io::{Read, Seek, SeekFrom},
    path::{Path, PathBuf},
    sync::{Arc, Mutex, mpsc},
    time::SystemTime,
};
use tokio::sync::broadcast;

#[derive(Default)]
struct Session {
    reader: crate::sessions::reader::Reader,
    offset: u64,
    partial: Vec<u8>,
    count: usize,
    generation: u64,
    modified: u64,
    provider: String,
}

pub struct Sessions {
    sessions: Arc<Mutex<HashMap<PathBuf, Session>>>,
    pub changes: broadcast::Sender<Value>,
    store: Arc<Store>,
    // Dropping the sender lets the worker stop; the watcher lives on it.
    _stop: Option<mpsc::Sender<Option<notify::Result<notify::Event>>>>,
}

impl Sessions {
    pub fn empty(store: Arc<Store>) -> Self {
        let (changes, _) = broadcast::channel(256);
        Self {
            sessions: Arc::new(Mutex::new(HashMap::new())),
            changes,
            store,
            _stop: None,
        }
    }

    pub fn start(home: PathBuf, store: Arc<Store>) -> Result<Self, String> {
        let mut this = Self::empty(store.clone());
        let roots = [home.join(".claude/projects"), home.join(".codex/sessions")];
        let (events, recv) = mpsc::channel();
        let stop = events.clone();
        let mut watcher = notify::recommended_watcher(move |event| {
            let _ = events.send(Some(event));
        })
        .map_err(|e| e.to_string())?;
        watcher
            .watch(&home, RecursiveMode::NonRecursive)
            .map_err(|e| e.to_string())?;
        // Watch existing tool directories, including creation of session roots.
        for root in [home.join(".claude"), home.join(".codex")] {
            if root.exists() {
                watcher
                    .watch(&root, RecursiveMode::Recursive)
                    .map_err(|e| e.to_string())?;
            }
        }
        let sessions = this.sessions.clone();
        let changes = this.changes.clone();
        this._stop = Some(stop);
        std::thread::Builder::new()
            .name("mikky-sessions".into())
            .spawn(move || {
                // Register first, scan second: modifications during the scan queue up.
                for root in &roots {
                    scan(root, &roots, &sessions, &changes, &store);
                }
                // A relay blocks on native events, not a periodic polling timer.
                while let Ok(Some(event)) = recv.recv() {
                    match event {
                        Ok(event) => {
                            if matches!(event.kind, notify::EventKind::Access(_)) {
                                continue;
                            }
                            for path in event.paths {
                                if (path == home.join(".claude") || path == home.join(".codex"))
                                    && path.is_dir()
                                {
                                    let _ = watcher.watch(&path, RecursiveMode::Recursive);
                                }
                                if path.is_dir() {
                                    scan(&path, &roots, &sessions, &changes, &store);
                                } else {
                                    read_new(&path, &roots, &sessions, &changes, &store);
                                }
                            }
                        }
                        Err(_) => {
                            for root in &roots {
                                scan(root, &roots, &sessions, &changes, &store);
                            }
                        }
                    }
                }
                drop(watcher);
            })
            .map_err(|e| e.to_string())?;
        Ok(this)
    }

    pub async fn delete(&self, path: &Path) -> Result<(), String> {
        let file = path.to_path_buf();
        let store = self.store.clone();
        let sessions = self.sessions.clone();
        tokio::task::spawn_blocking(move || {
            // Serialize removal with imports, including their database commits.
            let mut sessions = sessions.lock().unwrap();
            let key = file.to_string_lossy().into_owned();
            if store
                .history_blocking(HistoryRequest::Describe(key.clone()))?
                .is_null()
            {
                return Err("Unknown session file".into());
            }
            match std::fs::remove_file(&file) {
                Ok(()) => {}
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                Err(e) => return Err(e.to_string()),
            }
            store.history_blocking(HistoryRequest::Delete(key))?;
            sessions.remove(&file);
            Ok(())
        })
        .await
        .map_err(|e| e.to_string())??;
        let _ = self
            .changes
            .send(json!({"path":path.to_string_lossy(),"deleted":true}));
        Ok(())
    }
}

impl Drop for Sessions {
    fn drop(&mut self) {
        if let Some(stop) = &self._stop {
            let _ = stop.send(None);
        }
    }
}

fn describe(path: &Path, s: &Session) -> Value {
    json!({"path": path.to_string_lossy(), "provider": s.provider, "generation": s.generation, "modified": s.modified, "count": s.count, "firstMessage": s.reader.first_message, "parent": s.reader.parent})
}

/// A Claude session (`<project>/<session>.jsonl`), or one of its sub-agents
/// (`<project>/<session>/subagents/agent-<id>.jsonl`).
fn claude_file(path: &Path, roots: &[PathBuf; 2]) -> bool {
    if path.extension().is_none_or(|e| e != "jsonl") {
        return false;
    }
    let Ok(rest) = path.strip_prefix(&roots[0]) else {
        return false;
    };
    let parts: Vec<_> = rest
        .components()
        .map(|c| c.as_os_str().to_string_lossy())
        .collect();
    parts.len() == 2
        || (parts.len() == 4 && parts[2] == "subagents" && parts[3].starts_with("agent-"))
}

/// Who launched a Claude sub-agent, from its path and the `.meta.json`
/// beside it: the parent session, its agent id, the `Agent` tool that
/// launched it, its description.
fn claude_parent(path: &Path) -> Option<Value> {
    let folder = path.parent()?;
    if folder.file_name()? != "subagents" {
        return None;
    }
    let session = folder.parent()?.file_name()?.to_string_lossy().into_owned();
    let agent = path
        .file_stem()?
        .to_string_lossy()
        .strip_prefix("agent-")?
        .to_owned();
    let meta = std::fs::read(folder.join(format!("agent-{agent}.meta.json")))
        .ok()
        .and_then(|b| serde_json::from_slice::<Value>(&b).ok())
        .unwrap_or_default();
    Some(
        json!({"session":session, "agent":agent, "tool":meta["toolUseId"], "name":meta["description"], "type":meta["agentType"]}),
    )
}

fn provider(path: &Path, roots: &[PathBuf; 2]) -> Option<&'static str> {
    if claude_file(path, roots) {
        return Some("claude");
    }
    if path.starts_with(&roots[1])
        && path.extension().is_some_and(|e| e == "jsonl")
        && path.file_name()?.to_string_lossy().starts_with("rollout-")
    {
        return Some("codex");
    }
    None
}

fn scan(
    path: &Path,
    roots: &[PathBuf; 2],
    sessions: &Mutex<HashMap<PathBuf, Session>>,
    changes: &broadcast::Sender<Value>,
    store: &Store,
) {
    // Home events may mention unrelated directories. Only descend along
    // session roots; never crawl the user's other projects or downloads.
    if !roots
        .iter()
        .any(|root| path.starts_with(root) || root.starts_with(path))
    {
        return;
    }
    let Ok(entries) = std::fs::read_dir(path) else {
        return;
    };
    for entry in entries.flatten() {
        let Ok(kind) = entry.file_type() else {
            continue;
        };
        if kind.is_symlink() {
            continue;
        }
        if kind.is_dir() {
            scan(&entry.path(), roots, sessions, changes, store);
        } else {
            read_new(&entry.path(), roots, sessions, changes, store);
        }
    }
}

fn read_new(
    path: &Path,
    roots: &[PathBuf; 2],
    sessions: &Mutex<HashMap<PathBuf, Session>>,
    changes: &broadcast::Sender<Value>,
    store: &Store,
) {
    // Claude may write the metadata after the child's first lines.
    let transcript;
    let path = if path.to_string_lossy().ends_with(".meta.json") {
        transcript = path.with_file_name(format!(
            "{}.jsonl",
            path.file_name()
                .unwrap()
                .to_string_lossy()
                .trim_end_matches(".meta.json")
        ));
        transcript.as_path()
    } else {
        path
    };
    let Some(provider) = provider(path, roots) else {
        return;
    };
    let Ok(mut file) = File::open(path) else {
        return;
    };
    let Ok(meta) = file.metadata() else { return };
    let modified = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
        .map(|t| t.as_millis() as u64)
        .unwrap_or(0);
    let mut sessions = sessions.lock().unwrap();
    if !sessions.contains_key(path) {
        let previous = match store.history_blocking(HistoryRequest::Describe(
            path.to_string_lossy().into_owned(),
        )) {
            Ok(value) => value,
            Err(error) => {
                eprintln!("mikkyd: cannot read conversation index: {error}");
                return;
            }
        };
        sessions.insert(
            path.to_path_buf(),
            Session {
                generation: previous["generation"].as_u64().map_or(0, |g| g + 1),
                ..Default::default()
            },
        );
    }
    let s = sessions.get_mut(path).unwrap();
    s.provider = provider.into();
    if meta.len() < s.offset || (meta.len() == s.offset && modified != s.modified) {
        let generation = s.generation + 1;
        *s = Session {
            generation,
            ..Default::default()
        };
    }
    let parent = if provider == "claude" {
        claude_parent(path)
    } else {
        s.reader.parent.clone()
    };
    let parent_changed = s.reader.parent != parent;
    s.reader.parent = parent;
    if meta.len() == s.offset {
        if parent_changed {
            if !persist(path, s, s.count, Vec::new(), store) {
                return;
            }
            let _ = changes.send(describe(path, s));
        }
        return;
    }
    if file.seek(SeekFrom::Start(s.offset)).is_err() {
        return;
    }
    s.modified = modified;
    s.provider = provider.into();
    let mut bytes = [0; 64 * 1024];
    let mut changed = false;
    while let Ok(n) = file.read(&mut bytes) {
        if n == 0 {
            break;
        }
        s.offset += n as u64;
        s.partial.extend_from_slice(&bytes[..n]);
        if let Some(end) = s.partial.iter().rposition(|&c| c == b'\n') {
            let mut events = Vec::new();
            for line in s.partial[..=end].split(|&c| c == b'\n') {
                if let Ok(value) = serde_json::from_slice::<Value>(line)
                    && value.is_object()
                {
                    events.extend(s.reader.read(provider, &value));
                }
            }
            s.partial.drain(..=end);
            let from = s.count;
            s.count += events.len();
            if !persist(path, s, from, events, store) {
                return;
            }
            changed = true;
            // A single unusually large JSON line must not reserve its entire
            // allocation for the lifetime of an otherwise idle session.
            if s.partial.capacity() > 128 * 1024 && s.partial.len() < 64 * 1024 {
                s.partial.shrink_to(64 * 1024);
            }
        }
    }
    if changed {
        let _ = changes.send(describe(path, s));
    }
}

fn persist(
    path: &Path,
    session: &mut Session,
    from: usize,
    events: Vec<Value>,
    store: &Store,
) -> bool {
    if let Err(error) = store.history_blocking(HistoryRequest::Write {
        metadata: describe(path, session),
        from,
        events,
    }) {
        eprintln!("mikkyd: cannot save conversation: {error}");
        // Re-read the transcript on its next event; never advance a failed append.
        *session = Session {
            generation: session.generation + 1,
            ..Default::default()
        };
        return false;
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn old_conversations_are_indexed_and_reimports_replace_their_generation() {
        let home = std::env::temp_dir().join(format!(
            "mikky-old-{}",
            crate::system::endpoint::new_token()
        ));
        let roots = [home.join("claude"), home.join("codex")];
        let folder = roots[0].join("project");
        std::fs::create_dir_all(&folder).unwrap();
        let path = folder.join("old.jsonl");
        std::fs::write(
            &path,
            "{\"type\":\"user\",\"sessionId\":\"old\",\"message\":{\"content\":\"Encore là\"}}\n",
        )
        .unwrap();
        File::options()
            .write(true)
            .open(&path)
            .unwrap()
            .set_times(
                std::fs::FileTimes::new()
                    .set_modified(SystemTime::now() - std::time::Duration::from_secs(10 * 86400)),
            )
            .unwrap();
        let store = Store::open(None).unwrap();
        let (changes, _) = broadcast::channel(4);
        let first = Mutex::new(HashMap::new());
        scan(&roots[0], &roots, &first, &changes, &store);
        let metadata = store.history_blocking(HistoryRequest::List).unwrap();
        assert_eq!(metadata.as_array().unwrap().len(), 1);
        assert!(metadata[0]["count"].as_u64().unwrap() > 0);
        let second = Mutex::new(HashMap::new());
        read_new(&path, &roots, &second, &changes, &store);
        let updated = store
            .history_blocking(HistoryRequest::Describe(path.to_string_lossy().into()))
            .unwrap();
        assert_eq!(updated["generation"], 1);
        assert_eq!(updated["count"], metadata[0]["count"]);
        std::fs::remove_dir_all(home).unwrap();
    }
    #[test]
    fn late_claude_metadata_attaches_without_replaying_the_child() {
        let home = std::env::temp_dir().join(format!(
            "mikky-child-{}",
            crate::system::endpoint::new_token()
        ));
        let roots = [home.join("claude"), home.join("codex")];
        let folder = roots[0].join("project/parent/subagents");
        std::fs::create_dir_all(&folder).unwrap();
        let path = folder.join("agent-a85.jsonl");
        std::fs::write(&path, "{\"type\":\"user\",\"sessionId\":\"parent\",\"isSidechain\":true,\"agentId\":\"a85\",\"message\":{\"content\":\"Vérifie le lecteur\"}}\n").unwrap();
        let sessions = Mutex::new(HashMap::new());
        let (changes, _) = broadcast::channel(10);
        let store = Store::open(None).unwrap();
        read_new(&path, &roots, &sessions, &changes, &store);
        let before = sessions.lock().unwrap()[&path].count;
        let meta = folder.join("agent-a85.meta.json");
        std::fs::write(
            &meta,
            r#"{"description":"Lecteur","toolUseId":"toolu_1","agentType":"general-purpose"}"#,
        )
        .unwrap();
        read_new(&meta, &roots, &sessions, &changes, &store);
        let state = sessions.lock().unwrap();
        let s = &state[&path];
        assert_eq!(s.count, before);
        assert_eq!(s.reader.parent.as_ref().unwrap()["tool"], "toolu_1");
        assert_eq!(s.reader.parent.as_ref().unwrap()["session"], "parent");
        drop(state);
        std::fs::remove_dir_all(home).unwrap();
    }
    #[test]
    fn scanning_a_large_file_does_not_retain_its_raw_buffer() {
        let home = std::env::temp_dir().join(format!(
            "mikky-watch-{}",
            crate::system::endpoint::new_token()
        ));
        let roots = [home.join("claude"), home.join("codex")];
        let folder = roots[0].join("project");
        std::fs::create_dir_all(&folder).unwrap();
        let path = folder.join("session.jsonl");
        let line = format!(
            "{{\"type\":\"ignored\",\"padding\":\"{}\"}}\n",
            "x".repeat(8192)
        );
        std::fs::write(&path, line.repeat(512)).unwrap();
        let sessions = Mutex::new(HashMap::new());
        let (changes, _) = broadcast::channel(1);
        let store = Store::open(None).unwrap();
        read_new(&path, &roots, &sessions, &changes, &store);
        let state = sessions.lock().unwrap();
        let session = &state[&path];
        assert_eq!(session.offset, std::fs::metadata(&path).unwrap().len());
        assert!(session.partial.is_empty());
        assert!(session.partial.capacity() <= 128 * 1024);
        drop(state);
        std::fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn follows_claude_subagents_and_codex_rollouts() {
        let roots = [PathBuf::from("claude"), PathBuf::from("codex")];
        assert_eq!(
            provider(Path::new("claude/p/session.jsonl"), &roots),
            Some("claude")
        );
        assert_eq!(
            provider(Path::new("claude/p/subagents/x.jsonl"), &roots),
            None
        );
        assert_eq!(
            provider(Path::new("claude/p/s/subagents/agent-a1.jsonl"), &roots),
            Some("claude")
        );
        assert_eq!(
            provider(Path::new("claude/p/s/subagents/other.jsonl"), &roots),
            None
        );
        assert_eq!(
            provider(Path::new("codex/2026/09/30/rollout-x.jsonl"), &roots),
            Some("codex")
        );
    }
}
