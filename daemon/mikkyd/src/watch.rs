//! Native file events and incremental JSONL reads, owned by the backend.
//! A dedicated thread keeps directory walking and file I/O off Tokio.
use notify::{RecursiveMode, Watcher};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    fs::File,
    io::{Read, Seek, SeekFrom},
    path::{Path, PathBuf},
    sync::{Arc, Mutex, mpsc},
    time::{Duration, SystemTime},
};
use tokio::sync::broadcast;

#[derive(Default)]
struct Session {
    reader: crate::session_reader::Reader,
    offset: u64,
    partial: Vec<u8>,
    lines: Vec<Value>,
    generation: u64,
    modified: u64,
    provider: String,
}

pub struct Sessions {
    sessions: Arc<Mutex<HashMap<PathBuf, Session>>>,
    pub changes: broadcast::Sender<Value>,
    // Dropping the sender lets the worker stop; the watcher lives on it.
    _stop: Option<mpsc::Sender<Option<notify::Result<notify::Event>>>>,
}

impl Sessions {
    pub fn empty() -> Self {
        let (changes, _) = broadcast::channel(256);
        Self {
            sessions: Arc::new(Mutex::new(HashMap::new())),
            changes,
            _stop: None,
        }
    }

    pub fn start(home: PathBuf) -> Result<Self, String> {
        let mut this = Self::empty();
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
                    scan(root, &roots, &sessions, &changes);
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
                                    scan(&path, &roots, &sessions, &changes);
                                } else {
                                    read_new(&path, &roots, &sessions, &changes);
                                }
                            }
                        }
                        Err(_) => {
                            for root in &roots {
                                scan(root, &roots, &sessions, &changes);
                            }
                        }
                    }
                }
                drop(watcher);
            })
            .map_err(|e| e.to_string())?;
        Ok(this)
    }

    pub fn list(&self) -> Value {
        self.sessions
            .lock()
            .unwrap()
            .iter()
            .map(|(path, s)| describe(path, s))
            .collect()
    }

    pub fn delete(&self, path: &Path) -> Result<(), String> {
        let mut sessions = self.sessions.lock().unwrap();
        if !sessions.contains_key(path) {
            return Err("Unknown session file".into());
        }
        match std::fs::remove_file(path) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e.to_string()),
        }
        sessions.remove(path);
        let _ = self
            .changes
            .send(json!({"path":path.to_string_lossy(),"deleted":true}));
        Ok(())
    }

    pub fn read(&self, path: &Path, after: usize, generation: u64) -> Option<Value> {
        let sessions = self.sessions.lock().unwrap();
        let s = sessions.get(path)?;
        let start = if generation == s.generation {
            after.min(s.lines.len())
        } else {
            0
        };
        let end = (start + 256).min(s.lines.len());
        Some(
            json!({"session": describe(path, s), "from": start, "next": end, "more": end < s.lines.len(), "lines": s.lines[start..end]}),
        )
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
    json!({"path": path.to_string_lossy(), "provider": s.provider, "generation": s.generation, "modified": s.modified, "count": s.lines.len(), "firstMessage": s.reader.first_message})
}

fn kind<'a>(path: &Path, roots: &'a [PathBuf; 2]) -> Option<&'a str> {
    if path.extension()?.to_str()? != "jsonl" {
        return None;
    }
    if path.strip_prefix(&roots[0]).ok()?.components().count() == 2 {
        return Some("claude");
    }
    None
}

fn provider(path: &Path, roots: &[PathBuf; 2]) -> Option<&'static str> {
    if kind(path, roots).is_some() {
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
            scan(&entry.path(), roots, sessions, changes);
        } else if entry
            .metadata()
            .ok()
            .and_then(|m| m.modified().ok())
            .is_some_and(|m| {
                SystemTime::now().duration_since(m).unwrap_or_default()
                    < Duration::from_secs(3 * 86400)
            })
        {
            read_new(&entry.path(), roots, sessions, changes);
        }
    }
}

fn read_new(
    path: &Path,
    roots: &[PathBuf; 2],
    sessions: &Mutex<HashMap<PathBuf, Session>>,
    changes: &broadcast::Sender<Value>,
) {
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
    let s = sessions.entry(path.to_path_buf()).or_default();
    if meta.len() < s.offset || (meta.len() == s.offset && modified != s.modified) {
        let generation = s.generation + 1;
        *s = Session {
            generation,
            ..Default::default()
        };
    }
    if meta.len() == s.offset {
        return;
    }
    if file.seek(SeekFrom::Start(s.offset)).is_err() {
        return;
    }
    s.modified = modified;
    s.provider = provider.into();
    let mut bytes = [0; 64 * 1024];
    let mut changed = false;
    loop {
        let Ok(n) = file.read(&mut bytes) else { break };
        if n == 0 {
            break;
        }
        s.offset += n as u64;
        s.partial.extend_from_slice(&bytes[..n]);
        if let Some(end) = s.partial.iter().rposition(|&c| c == b'\n') {
            for line in s.partial[..=end].split(|&c| c == b'\n') {
                if let Ok(value) = serde_json::from_slice::<Value>(line) {
                    if value.is_object() {
                        s.lines.extend(s.reader.read(provider, &value));
                    }
                }
            }
            s.partial.drain(..=end);
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

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn scanning_a_large_file_does_not_retain_its_raw_buffer() {
        let home =
            std::env::temp_dir().join(format!("mikky-watch-{}", crate::endpoint::new_token()));
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
        read_new(&path, &roots, &sessions, &changes);
        let state = sessions.lock().unwrap();
        let session = &state[&path];
        assert_eq!(session.offset, std::fs::metadata(&path).unwrap().len());
        assert!(session.partial.is_empty());
        assert!(session.partial.capacity() <= 128 * 1024);
        drop(state);
        std::fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn ignores_subagents_and_accepts_codex_rollouts() {
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
            provider(Path::new("codex/2026/09/30/rollout-x.jsonl"), &roots),
            Some("codex")
        );
    }
}
