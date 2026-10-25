//! Durable conversation inventory and normalized, paged events. All work
//! runs on the existing SQLite owner; transcripts are never deleted on import.
use rusqlite::{Connection, OptionalExtension, params};
use serde_json::{Value, json};

#[cfg(test)]
mod tests;

pub enum HistoryRequest {
    List,
    Describe(String),
    Read {
        path: String,
        after: usize,
        generation: u64,
    },
    Write {
        metadata: Value,
        from: usize,
        events: Vec<Value>,
    },
    Delete(String),
}

pub(super) fn migrate(db: &Connection) -> Result<(), String> {
    db.execute_batch(
        "PRAGMA foreign_keys=ON;
         CREATE TABLE IF NOT EXISTS conversations (
           path TEXT PRIMARY KEY, modified INTEGER NOT NULL, metadata TEXT NOT NULL
         );
         CREATE INDEX IF NOT EXISTS conversations_recent ON conversations(modified DESC, path);
         CREATE TABLE IF NOT EXISTS conversation_events (
           path TEXT NOT NULL REFERENCES conversations(path) ON DELETE CASCADE,
           sequence INTEGER NOT NULL, event TEXT NOT NULL,
           PRIMARY KEY(path, sequence)
         );",
    )
    .map_err(|e| e.to_string())
}

pub(super) fn handle(db: &mut Connection, request: HistoryRequest) -> Result<Value, String> {
    match request {
        HistoryRequest::List => {
            let mut query = db
                .prepare("SELECT metadata FROM conversations ORDER BY modified DESC, path")
                .map_err(|e| e.to_string())?;
            let rows = query
                .query_map([], |r| r.get::<_, String>(0))
                .map_err(|e| e.to_string())?;
            let mut list = Vec::new();
            for row in rows {
                list.push(decode(row.map_err(|e| e.to_string())?)?);
            }
            Ok(Value::Array(list))
        }
        HistoryRequest::Describe(path) => Ok(describe(db, &path)?.unwrap_or(Value::Null)),
        HistoryRequest::Read {
            path,
            after,
            generation,
        } => {
            let Some(meta) = describe(db, &path)? else {
                return Ok(Value::Null);
            };
            let count = meta["count"].as_u64().ok_or("invalid conversation count")? as usize;
            let start = if meta["generation"].as_u64() == Some(generation) {
                after.min(count)
            } else {
                0
            };
            let end = start.saturating_add(256).min(count);
            let mut query = db.prepare(
                "SELECT event FROM conversation_events WHERE path=?1 AND sequence>=?2 AND sequence<?3 ORDER BY sequence",
            ).map_err(|e| e.to_string())?;
            let rows = query
                .query_map(params![path, start as i64, end as i64], |r| {
                    r.get::<_, String>(0)
                })
                .map_err(|e| e.to_string())?;
            let mut lines = Vec::new();
            for row in rows {
                lines.push(decode(row.map_err(|e| e.to_string())?)?);
            }
            Ok(json!({"session":meta,"from":start,"next":end,"more":end<count,"lines":lines}))
        }
        HistoryRequest::Write {
            metadata,
            from,
            events,
        } => write(db, metadata, from, events),
        HistoryRequest::Delete(path) => {
            db.execute("DELETE FROM conversations WHERE path=?1", [path])
                .map_err(|e| e.to_string())?;
            Ok(Value::Null)
        }
    }
}

fn decode(text: String) -> Result<Value, String> {
    serde_json::from_str(&text).map_err(|e| e.to_string())
}

fn describe(db: &Connection, path: &str) -> Result<Option<Value>, String> {
    let text: Option<String> = db
        .query_row(
            "SELECT metadata FROM conversations WHERE path=?1",
            [path],
            |r| r.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?;
    text.map(decode).transpose()
}

fn write(
    db: &mut Connection,
    metadata: Value,
    from: usize,
    events: Vec<Value>,
) -> Result<Value, String> {
    let path = metadata["path"]
        .as_str()
        .ok_or("missing conversation path")?;
    let modified = metadata["modified"]
        .as_u64()
        .ok_or("missing conversation date")?;
    let generation = metadata["generation"]
        .as_u64()
        .ok_or("missing conversation generation")?;
    if metadata["count"].as_u64() != Some((from + events.len()) as u64) {
        return Err("inconsistent conversation count".into());
    }
    let tx = db.transaction().map_err(|e| e.to_string())?;
    if from > 0 {
        let previous = describe(&tx, path)?.ok_or("missing conversation")?;
        if previous["count"].as_u64() != Some(from as u64)
            || previous["generation"].as_u64() != Some(generation)
        {
            return Err("conversation changed before append".into());
        }
    }
    tx.execute(
        "INSERT INTO conversations(path,modified,metadata) VALUES(?1,?2,?3)
         ON CONFLICT(path) DO UPDATE SET modified=excluded.modified,metadata=excluded.metadata",
        params![path, modified as i64, metadata.to_string()],
    )
    .map_err(|e| e.to_string())?;
    if from == 0 {
        tx.execute("DELETE FROM conversation_events WHERE path=?1", [path])
            .map_err(|e| e.to_string())?;
    }
    {
        let mut insert = tx
            .prepare("INSERT INTO conversation_events VALUES(?1,?2,?3)")
            .map_err(|e| e.to_string())?;
        for (index, event) in events.iter().enumerate() {
            insert
                .execute(params![path, (from + index) as i64, event.to_string()])
                .map_err(|e| e.to_string())?;
        }
    }
    tx.commit().map_err(|e| e.to_string())?;
    Ok(Value::Null)
}
