//! One SQLite owner on a dedicated thread: no disk I/O on Tokio's workers.
//! The old JSON file is imported once, in a transaction, and left untouched.
use rusqlite::{Connection, OptionalExtension};
use serde_json::{Value, json};
use std::{path::Path, sync::mpsc};
use tokio::sync::oneshot;

type Reply = oneshot::Sender<Result<Value, String>>;
enum Work {
    Read(Reply),
    Patch(Value, Reply),
}

pub struct Store {
    send: mpsc::Sender<Work>,
    pub changes: tokio::sync::broadcast::Sender<()>,
}

impl Store {
    pub fn open(path: Option<&Path>) -> Result<Self, String> {
        let mut db = match path {
            Some(path) => {
                if let Some(parent) = path.parent() {
                    std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
                }
                Connection::open(path)
            }
            None => Connection::open_in_memory(),
        }
        .map_err(|e| e.to_string())?;
        db.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;
            CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY CHECK(id=1), value TEXT NOT NULL);").map_err(|e| e.to_string())?;
        let exists: bool = db
            .query_row("SELECT EXISTS(SELECT 1 FROM state WHERE id=1)", [], |r| {
                r.get(0)
            })
            .map_err(|e| e.to_string())?;
        if !exists {
            let mut state = empty();
            if let Some(legacy) = path
                .and_then(Path::parent)
                .map(|p| p.join("agents.json"))
                .filter(|p| p.exists())
            {
                // A malformed file must not be silently replaced by an empty store.
                let text = std::fs::read_to_string(legacy).map_err(|e| e.to_string())?;
                let old: Value =
                    serde_json::from_str(&text).map_err(|e| format!("agents.json: {e}"))?;
                let agents = old
                    .get("agents")
                    .and_then(Value::as_array)
                    .ok_or("agents.json: missing agents")?;
                for agent in agents {
                    let id = agent
                        .get("id")
                        .and_then(Value::as_str)
                        .ok_or("agents.json: missing agent id")?;
                    state["agents"][id] = agent.clone();
                }
                for key in ["marks", "choices"] {
                    if let Some(value) = old.get(key) {
                        if !value.is_object() {
                            return Err(format!("agents.json: invalid {key}"));
                        }
                        state[key] = value.clone();
                    }
                }
                if let Some(value) = old.get("recentFolders") {
                    if !value.is_array() {
                        return Err("agents.json: invalid folders".into());
                    }
                    state["recentFolders"] = value.clone();
                }
            }
            let tx = db.transaction().map_err(|e| e.to_string())?;
            tx.execute("INSERT INTO state VALUES(1, ?1)", [state.to_string()])
                .map_err(|e| e.to_string())?;
            tx.commit().map_err(|e| e.to_string())?;
        }
        let (send, recv) = mpsc::channel();
        std::thread::Builder::new()
            .name("mikky-store".into())
            .spawn(move || {
                for work in recv {
                    match work {
                        Work::Read(reply) => {
                            let _ = reply.send(read(&db));
                        }
                        Work::Patch(patch, reply) => {
                            let _ = reply.send(patch_state(&mut db, patch));
                        }
                    }
                }
            })
            .map_err(|e| e.to_string())?;
        let (changes, _) = tokio::sync::broadcast::channel(16);
        Ok(Self { send, changes })
    }

    pub async fn read(&self) -> Result<Value, String> {
        let (send, recv) = oneshot::channel();
        self.send
            .send(Work::Read(send))
            .map_err(|e| e.to_string())?;
        recv.await.map_err(|e| e.to_string())?
    }

    pub async fn patch(&self, patch: Value) -> Result<Value, String> {
        let (send, recv) = oneshot::channel();
        self.send
            .send(Work::Patch(patch, send))
            .map_err(|e| e.to_string())?;
        let state = recv.await.map_err(|e| e.to_string())??;
        let _ = self.changes.send(());
        Ok(state)
    }
}

fn empty() -> Value {
    json!({"agents": {}, "marks": {}, "choices": {}, "recentFolders": []})
}

fn read(db: &Connection) -> Result<Value, String> {
    let value: Option<String> = db
        .query_row("SELECT value FROM state WHERE id=1", [], |r| r.get(0))
        .optional()
        .map_err(|e| e.to_string())?;
    serde_json::from_str(value.as_deref().unwrap_or("{}")).map_err(|e| e.to_string())
}

fn patch_state(db: &mut Connection, patch: Value) -> Result<Value, String> {
    let changes = patch.as_object().ok_or("invalid patch")?;
    let tx = db.transaction().map_err(|e| e.to_string())?;
    let mut state = read(&tx)?;
    for (key, value) in changes {
        match key.as_str() {
            "agents" | "marks" | "choices" => {
                let entries = value.as_object().ok_or("invalid entries")?;
                for (id, entry) in entries {
                    if entry.is_null() {
                        state[key].as_object_mut().unwrap().remove(id);
                    } else if entry.is_object() {
                        state[key][id] = entry.clone();
                    } else {
                        return Err("invalid entry".into());
                    }
                }
            }
            "recentFolders"
                if value
                    .as_array()
                    .is_some_and(|a| a.len() <= 8 && a.iter().all(Value::is_string)) =>
            {
                state[key] = value.clone()
            }
            _ => return Err(format!("unknown or invalid state field {key}")),
        }
    }
    tx.execute("UPDATE state SET value=?1 WHERE id=1", [state.to_string()])
        .map_err(|e| e.to_string())?;
    tx.commit().map_err(|e| e.to_string())?;
    Ok(state)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn patches_merge_and_invalid_patch_is_atomic() {
        let store = Store::open(None).unwrap();
        store
            .patch(json!({"marks": {"a": {"pinned": true}}}))
            .await
            .unwrap();
        store
            .patch(json!({"marks": {"b": {"archived": true}}}))
            .await
            .unwrap();
        assert!(
            store
                .patch(json!({"marks": {"a": null}, "unknown": 1}))
                .await
                .is_err()
        );
        let state = store.read().await.unwrap();
        assert_eq!(state["marks"]["a"]["pinned"], true);
        assert_eq!(state["marks"]["b"]["archived"], true);
    }

    #[tokio::test]
    async fn legacy_import_is_once_and_committed_state_survives_reopen() {
        let dir =
            std::env::temp_dir().join(format!("mikky-store-{}", crate::endpoint::new_token()));
        std::fs::create_dir_all(&dir).unwrap();
        let legacy = dir.join("agents.json");
        let original = r#"{"agents":[{"id":"old","sessionId":"session"}],"marks":{"session":{"pinned":true}}}"#;
        std::fs::write(&legacy, original).unwrap();
        let path = dir.join("mikky.db");
        let first = Store::open(Some(&path)).unwrap();
        assert_eq!(
            first.read().await.unwrap()["agents"]["old"]["sessionId"],
            "session"
        );
        first
            .patch(json!({"marks":{"session":{"archived":true}}}))
            .await
            .unwrap();
        assert_eq!(std::fs::read_to_string(&legacy).unwrap(), original);
        let second = Store::open(Some(&path)).unwrap();
        assert_eq!(
            second.read().await.unwrap()["marks"]["session"]["archived"],
            true
        );
        // Drop workers before removing the test's own directory.
        drop(first);
        drop(second);
        for _ in 0..50 {
            if std::fs::remove_dir_all(&dir).is_ok() {
                return;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
        panic!("store worker did not close");
    }
}
