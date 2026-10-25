use super::*;

fn append(
    db: &mut Connection,
    path: &str,
    generation: u64,
    from: usize,
    count: usize,
) -> Result<Value, String> {
    handle(
        db,
        HistoryRequest::Write {
            metadata: json!({"path":path,"provider":"claude","generation":generation,"modified":42,"count":from+count}),
            from,
            events: (from..from + count)
                .map(|i| json!({"type":"text","index":i}))
                .collect(),
        },
    )
}

fn page(db: &mut Connection, after: usize, generation: u64) -> Value {
    handle(
        db,
        HistoryRequest::Read {
            path: "session".into(),
            after,
            generation,
        },
    )
    .unwrap()
}

#[test]
fn pages_appends_and_generation_resets_are_atomic() {
    let mut db = Connection::open_in_memory().unwrap();
    migrate(&db).unwrap();
    append(&mut db, "session", 0, 0, 300).unwrap();
    let first = page(&mut db, 0, 0);
    assert_eq!(first["next"], 256);
    assert_eq!(first["more"], true);
    assert_eq!(page(&mut db, 256, 0)["lines"].as_array().unwrap().len(), 44);
    append(&mut db, "session", 0, 300, 2).unwrap();
    assert_eq!(page(&mut db, 300, 0)["lines"][1]["index"], 301);
    assert!(append(&mut db, "session", 0, 280, 2).is_err());
    assert_eq!(describe(&db, "session").unwrap().unwrap()["count"], 302);
    append(&mut db, "session", 1, 0, 1).unwrap();
    let reset = page(&mut db, 256, 0);
    assert_eq!(reset["from"], 0);
    assert_eq!(reset["lines"].as_array().unwrap().len(), 1);
    handle(&mut db, HistoryRequest::Delete("session".into())).unwrap();
    assert!(page(&mut db, 0, 0).is_null());
    assert_eq!(
        db.query_row("SELECT count(*) FROM conversation_events", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        0
    );
}

#[test]
fn migration_and_reopen_keep_conversations_and_existing_metadata() {
    let dir = std::env::temp_dir().join(format!(
        "mikky-history-db-{}",
        crate::system::endpoint::new_token()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("mikky.db");
    {
        let mut db = Connection::open(&path).unwrap();
        db.execute_batch("CREATE TABLE state(id INTEGER PRIMARY KEY,value TEXT); INSERT INTO state VALUES(1,'original');").unwrap();
        migrate(&db).unwrap();
        append(&mut db, "session", 3, 0, 2).unwrap();
    }
    let mut reopened = Connection::open(&path).unwrap();
    migrate(&reopened).unwrap();
    assert_eq!(
        reopened
            .query_row("SELECT value FROM state", [], |r| r.get::<_, String>(0))
            .unwrap(),
        "original"
    );
    assert_eq!(
        page(&mut reopened, 0, 3)["lines"].as_array().unwrap().len(),
        2
    );
    assert_eq!(
        handle(&mut reopened, HistoryRequest::List).unwrap()[0]["generation"],
        3
    );
    drop(reopened);
    std::fs::remove_dir_all(dir).unwrap();
}
