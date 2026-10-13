use super::*;
use std::sync::Arc;

/// Hooks with a screen there, and what they say when their list changes.
fn with_screen() -> (Arc<Hooks>, broadcast::Receiver<()>) {
    let hooks = Arc::new(Hooks::default());
    hooks.screen_joined();
    let changes = hooks.changes.subscribe();
    (hooks, changes)
}

/// [event] sent to [hooks]: the call ends with what the hook prints.
fn waiting(hooks: &Arc<Hooks>, event: Value) -> tokio::task::JoinHandle<Value> {
    let h = hooks.clone();
    tokio::spawn(async move { h.event(&event, |_| false, std::future::pending()).await })
}

fn ask(session: &str, command: &str) -> Value {
    json!({
        "hook_event_name": "PermissionRequest",
        "session_id": session,
        "cwd": "C:/p",
        "tool_name": "Bash",
        "tool_input": {"command": command},
    })
}

/// Claude's AskUserQuestion, as its PermissionRequest hook sends it.
fn question(session: &str) -> Value {
    json!({
        "hook_event_name": "PermissionRequest",
        "session_id": session,
        "cwd": "C:/p",
        "tool_name": "AskUserQuestion",
        "tool_input": {"questions": [
            {"question": "Quelle base ?", "header": "Base", "multiSelect": false, "options": [
                {"label": "SQLite", "description": "Un fichier"},
                {"label": "Postgres", "description": "Un serveur"},
            ]},
            {"question": "Quels tests ?", "header": "Tests", "multiSelect": true, "options": [
                {"label": "Unitaires", "description": ""},
                {"label": "Bout en bout", "description": ""},
            ]},
        ]},
    })
}

#[test]
fn codex_commands_come_as_words() {
    let words = json!({"command": ["bash", "-lc", "cargo  test"]});
    assert_eq!(command_of(&words).as_deref(), Some("bash -lc cargo  test"));
    assert_eq!(
        summary("shell", command_of(&words).as_deref()),
        "shell bash -lc cargo test"
    );
    assert_eq!(command_of(&json!({"file_path": "a"})), None);
    assert_eq!(summary("Edit", None), "Edit");
}

#[tokio::test]
async fn pending_hooks_publish_the_same_request_events_as_acp() {
    let (hooks, mut changes) = with_screen();
    let task = waiting(&hooks, ask("s", "cargo test"));
    changes.recv().await.unwrap();
    let request = hooks.list()[0].clone();
    assert_eq!(request["event"]["type"], "permission");
    assert_eq!(request["event"]["id"], format!("hook:{}", request["id"]));
    assert_eq!(request["event"]["command"], "cargo test");
    hooks.answer(request["id"].as_u64().unwrap(), Some("allow"), None);
    assert_eq!(task.await.unwrap()["decision"], "allow");
}

#[tokio::test]
async fn nobody_watching_never_waits() {
    let hooks = Hooks::default();
    let r = hooks
        .event(&ask("s", "ls"), |_| false, std::future::pending())
        .await;
    assert_eq!(r, json!({"decision": null}));
    let r = hooks
        .event(&question("s"), |_| false, std::future::pending())
        .await;
    assert_eq!(r, json!({"decision": null}));
}

#[tokio::test]
async fn own_sessions_and_question_permissions_go_their_way() {
    let hooks = Hooks::default();
    hooks.screen_joined();
    let r = hooks
        .event(&ask("mine", "ls"), |s| s == "mine", std::future::pending())
        .await;
    assert_eq!(r["decision"], Value::Null);
    let r = hooks
        .event(&question("mine"), |s| s == "mine", std::future::pending())
        .await;
    assert_eq!(r["decision"], Value::Null);
    // A form Mikky cannot show: the terminal.
    let mut odd = question("s");
    odd["tool_input"] = json!({"questions": []});
    let r = hooks.event(&odd, |_| false, std::future::pending()).await;
    assert_eq!(r["decision"], Value::Null);
    assert_eq!(hooks.list(), json!([]));
}

#[tokio::test]
async fn a_screen_answers() {
    let (hooks, mut changes) = with_screen();
    let call = waiting(&hooks, ask("s", "cargo   test"));
    changes.recv().await.unwrap();
    let list = hooks.list();
    assert_eq!(list[0]["kind"], "permission");
    assert_eq!(list[0]["title"], "Bash cargo test");
    assert_eq!(list[0]["command"], "cargo   test");
    let id = list[0]["id"].as_u64().unwrap();
    // Answers are for questions only: a permission ignores them.
    assert!(hooks.answer(id, Some("allow"), Some(&json!({"x": "y"}))));
    assert_eq!(call.await.unwrap(), json!({"decision": "allow"}));
    assert_eq!(hooks.list(), json!([]));
    assert!(!hooks.answer(id, Some("deny"), None));
}

#[tokio::test]
async fn a_screen_answers_a_question() {
    let (hooks, mut changes) = with_screen();
    let call = waiting(&hooks, question("s"));
    changes.recv().await.unwrap();
    let list = hooks.list();
    assert_eq!(list[0]["kind"], "question");
    assert_eq!(list[0]["title"], "Quelle base ?");
    assert_eq!(list[0]["questions"][0]["header"], "Base");
    assert_eq!(list[0]["questions"][1]["multiSelect"], true);
    assert_eq!(
        list[0]["questions"][0]["options"][1],
        json!({"label": "Postgres", "description": "Un serveur"})
    );
    let id = list[0]["id"].as_u64().unwrap();
    // Answers by key, as for an ACP form; those that do not fit: refused,
    // the question stays.
    for wrong in [
        json!({"q1": "SQLite"}),
        json!({"q1": "SQLite", "q2": ["Autre"]}),
        json!({"q1": " ", "q2": ["Unitaires"]}),
        json!({"q1": "SQLite", "q2": []}),
        json!({"Quelle base ?": "SQLite", "Quels tests ?": ["Unitaires"]}),
    ] {
        assert!(!hooks.answer(id, None, Some(&wrong)), "{wrong}");
    }
    assert_eq!(hooks.list().as_array().unwrap().len(), 1);
    // Free text (it wins over a label), several labels once each.
    let keyed = json!({"q1": "SQLite", "q1_custom": " DuckDB, en fait ", "q2": ["Unitaires", "Bout en bout", "Unitaires"]});
    assert!(hooks.answer(id, Some("allow"), Some(&keyed)));
    assert_eq!(
        call.await.unwrap(),
        json!({"answers": {"Quelle base ?": "DuckDB, en fait", "Quels tests ?": ["Unitaires", "Bout en bout"]}})
    );
    assert_eq!(hooks.list(), json!([]));
}

#[tokio::test]
async fn a_question_left_to_the_terminal() {
    let (hooks, mut changes) = with_screen();
    let call = waiting(&hooks, question("s"));
    changes.recv().await.unwrap();
    let id = hooks.list()[0]["id"].as_u64().unwrap();
    // « Répondre dans le terminal », or an answer meant for a permission.
    assert!(hooks.answer(id, Some("allow"), None));
    assert_eq!(call.await.unwrap(), json!({"decision": null}));
}

#[tokio::test]
async fn answered_in_the_terminal_or_gone() {
    let (hooks, mut changes) = with_screen();
    let call = waiting(&hooks, ask("s", "ls"));
    changes.recv().await.unwrap();
    // The session goes on: answered in its terminal.
    let next = json!({"hook_event_name": "PostToolUse", "session_id": "s"});
    hooks.event(&next, |_| false, std::future::pending()).await;
    assert_eq!(call.await.unwrap()["decision"], Value::Null);
    assert_eq!(hooks.list(), json!([]));

    // The same for a question.
    let call = waiting(&hooks, question("q"));
    while hooks.list() == json!([]) {
        changes.recv().await.unwrap();
    }
    let next = json!({"hook_event_name": "UserPromptSubmit", "session_id": "q"});
    hooks.event(&next, |_| false, std::future::pending()).await;
    assert_eq!(call.await.unwrap(), json!({"decision": null}));

    // The hook's connection closed.
    let (tx, rx) = oneshot::channel::<()>();
    let h = hooks.clone();
    let call = tokio::spawn(async move {
        h.event(&ask("t", "ls"), |_| false, async {
            let _ = rx.await;
        })
        .await
    });
    changes.recv().await.unwrap();
    drop(tx);
    assert_eq!(call.await.unwrap()["decision"], Value::Null);
    assert_eq!(hooks.list(), json!([]));
}

#[tokio::test]
async fn every_event_tells_where_the_session_runs() {
    let hooks = Hooks::default();
    assert_eq!(hooks.origin("s"), Value::Null);
    let first = json!({
        "hook_event_name": "UserPromptSubmit",
        "session_id": "s",
        "cwd": "C:/p",
        "mikky_agent": "claude",
        "term_program": "vscode",
        "vscode_pid": "4242",
        "window_pid": 4242,
        "window_handle": 132_456,
        "window_exe": "Code.exe",
    });
    hooks.event(&first, |_| false, std::future::pending()).await;
    // A later event without the window keeps it.
    let next = json!({"hook_event_name": "Stop", "session_id": "s", "cwd": "C:/q"});
    hooks.event(&next, |_| false, std::future::pending()).await;
    assert_eq!(
        hooks.origin("s"),
        json!({
            "cwd": "C:/q",
            "agent": "claude",
            "termProgram": "vscode",
            "vscodePid": "4242",
            "windowPid": 4242,
            "windowHandle": 132_456,
            "windowExe": "Code.exe",
        })
    );
    // Bounded: the oldest sessions go.
    for i in 0..ORIGINS {
        let e = json!({"hook_event_name": "Stop", "session_id": format!("x{i}"), "cwd": "C:/"});
        hooks.event(&e, |_| false, std::future::pending()).await;
    }
    assert_eq!(hooks.origin("s"), Value::Null);
    assert_eq!(hooks.origin("x1")["cwd"], "C:/");
}

#[test]
fn questions_are_kept_only_when_mikky_can_show_them() {
    let q = questions_of(&question("s")["tool_input"]).unwrap();
    assert_eq!(q.as_array().unwrap().len(), 2);
    assert!(questions_of(&json!({})).is_none());
    assert!(questions_of(&json!({"questions": [{"question": "A ?", "options": []}]})).is_none());
    assert!(
        questions_of(&json!({"questions": [{"question": "", "options": [{"label": "a"}]}]}))
            .is_none()
    );
    let twice = json!({"questions": [
        {"question": "A ?", "options": [{"label": "a"}]},
        {"question": "A ?", "options": [{"label": "b"}]},
    ]});
    assert!(questions_of(&twice).is_none());
}

#[tokio::test]
async fn vs_codes_question_is_held_until_answered_there() {
    let (hooks, mut changes) = with_screen();
    let mut q = question("s");
    q["entrypoint"] = json!("claude-vscode");
    let (close, closed) = tokio::sync::oneshot::channel::<()>();
    let h = hooks.clone();
    let call = tokio::spawn(async move {
        h.event(&q, |_| false, async {
            let _ = closed.await;
        })
        .await
    });
    changes.recv().await.unwrap();
    assert_eq!(hooks.list()[0]["kind"], "question");
    // Answered in VS Code: Claude ends the hook, the request goes.
    drop(close);
    assert_eq!(call.await.unwrap(), json!({"decision": null}));
    assert_eq!(hooks.list(), json!([]));
    assert_eq!(hooks.settled()[0]["how"], "elsewhere");
    assert_eq!(hooks.settled()[0]["sessionId"], "s");
}

#[tokio::test]
async fn answered_from_mikky_is_not_told_as_elsewhere() {
    let (hooks, mut changes) = with_screen();
    let call = waiting(&hooks, ask("s", "ls"));
    changes.recv().await.unwrap();
    let id = hooks.list()[0]["id"].as_u64().unwrap();
    assert!(hooks.answer(id, Some("allow"), None));
    call.await.unwrap();
    assert_eq!(hooks.settled(), json!([]));
    // The next request waits; the session moves on in its terminal.
    let _call = waiting(&hooks, ask("s", "pwd"));
    while hooks.list() == json!([]) {
        changes.recv().await.unwrap();
    }
    let mut next = ask("s", "");
    next["hook_event_name"] = json!("PostToolUseFailure");
    hooks.event(&next, |_| false, std::future::pending()).await;
    assert_eq!(hooks.list(), json!([]));
    assert_eq!(hooks.settled()[0]["how"], "elsewhere");
}
