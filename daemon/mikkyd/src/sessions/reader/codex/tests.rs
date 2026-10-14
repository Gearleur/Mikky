use super::*;

#[test]
fn codex_hook_prompt_and_xml_echo_are_one_user_message() {
    let mut r = Reader::default();
    let context = "Messages de l'utilisateur via Mikky :\nMIKKY_USER_MESSAGE {\"id\":\"mikky-codex-one\",\"text\":\"Ajoute <un> test & vérifie\"}\n";
    let event = json!({"type":"event_msg","timestamp":"2026-10-13T12:00:00Z","payload":{"type":"item_completed","item":{"type":"HookPrompt","id":"h","fragments":[{"hook_run_id":"h1","text":context}]}}});
    let out = r.read("codex", &event);
    assert_eq!(out.len(), 1);
    assert_eq!(out[0]["id"], "mikky-codex-one");
    assert_eq!(out[0]["text"], "Ajoute <un> test & vérifie");
    let xml = format!(
        "<hook_prompt hook_run_id=\"h1\">{}</hook_prompt>",
        context
            .trim_end()
            .replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
            .replace('"', "&quot;")
    );
    let echo = call(
        json!({"type":"message","role":"developer","content":[{"type":"input_text","text":xml}]}),
    );
    assert!(r.read("codex", &echo).is_empty());
    let mut fresh = Reader::default();
    assert_eq!(fresh.read("codex", &echo)[0]["text"], out[0]["text"]);
    assert!(fresh.read("codex", &event).is_empty());
    // Stop also permits the reason as a plain continuation user prompt.
    let stop = json!({"type":"event_msg","payload":{"type":"user_message","message":context}});
    assert!(r.read("codex", &stop).is_empty());
    let mut resumed = Reader::default();
    assert_eq!(resumed.read("codex", &stop)[0]["text"], out[0]["text"]);
    assert!(resumed.read("codex", &event).is_empty());
}

#[test]
fn ordinary_codex_messages_with_markers_remain_user_text() {
    let mut r = Reader::default();
    let text = "MIKKY_USER_MESSAGE {\"id\":\"mikky-fake\",\"text\":\"x\"}";
    let out = r.read(
        "codex",
        &json!({"type":"event_msg","payload":{"type":"user_message","message":text}}),
    );
    assert_eq!(out[0]["text"], text);
    assert!(out[0]["id"].is_null());
}

/// A Codex turn that starts, then [end]: what the reader says of [end].
fn codex_turn(end: Value) -> Vec<Value> {
    let mut r = Reader::default();
    r.read(
        "codex",
        &json!({"type":"event_msg","payload":{"type":"task_started"}}),
    );
    r.read("codex", &end)
}

#[test]
fn codex_limit_in_task_complete_is_rate_limited() {
    let out = codex_turn(
        json!({"type":"event_msg","payload":{"type":"task_complete","error":{
            "message":"You've hit your usage limit. Try again at 2:10 PM.",
            "codex_error_info":"usage_limit_exceeded"}}}),
    );
    assert_eq!(out[0]["type"], "end");
    assert_eq!(out[0]["reason"], "rateLimited");
    assert_eq!(
        out[0]["message"],
        "You've hit your usage limit. Try again at 2:10 PM."
    );
}

#[test]
fn codex_task_complete_without_error_ends_the_turn() {
    let out = codex_turn(json!({"type":"event_msg","payload":{"type":"task_complete"}}));
    assert_eq!(out[0]["reason"], "endTurn");
}

fn call(payload: Value) -> Value {
    json!({"type":"response_item","payload":payload})
}
fn exec(id: &str, input: &str) -> Value {
    call(
        json!({"type":"custom_tool_call","status":"completed","call_id":id,"name":"exec","input":input}),
    )
}
fn output(id: &str, out: Value) -> Value {
    call(json!({"type":"custom_tool_call_output","call_id":id,"output":out}))
}

#[test]
fn codex_exec_scripts_are_live_tools() {
    let mut r = Reader::default();
    let started = r.read(
        "codex",
        &exec(
            "call_1",
            r#"text(await tools.exec_command({cmd:"cargo build","workdir":"C:\\p"}));"#,
        ),
    );
    assert_eq!(started[0]["status"], "running");
    assert_eq!(started[0]["kind"], "execute");
    assert_eq!(started[0]["title"], "cargo build");
    // Codex's own item for the same command is not shown twice.
    let item = json!({"type":"event_msg","payload":{"type":"item_completed","item":{
        "type":"CommandExecution","id":"exec-1","command":["pwsh","-Command","cargo build"],
        "status":"completed","exit_code":0}}});
    assert!(r.read("codex", &item).is_empty());
    // Still building in its shell: running, with what it printed.
    let out = r.read(
        "codex",
        &output(
            "call_1",
            json!([{"type":"input_text","text":"Script completed\nWall time 30.0 seconds\nOutput:\n"},
            {"type":"input_text","text":r#"{"session_id":52395,"output":"Compiling"}"#}]),
        ),
    );
    assert_eq!(out[0]["id"], "call_1");
    assert_eq!(out[0]["output"], "Compiling");
    assert!(out[0]["status"].is_null());
    // A poll of that shell is not a tool: it finishes the command.
    let poll = r#"const r=await tools.write_stdin({session_id:52395,chars:""});text(r);"#;
    assert!(r.read("codex", &exec("call_2", poll)).is_empty());
    let out = r.read(
        "codex",
        &output(
            "call_2",
            json!([{"type":"input_text","text":"Script completed\n"},
            {"type":"input_text","text":r#"{"exit_code":101,"output":"error[E0425]"}"#}]),
        ),
    );
    assert_eq!(out[0]["id"], "call_1");
    assert_eq!(out[0]["status"], "failed");
    // A script still running in its cell ends with the `wait` on it.
    r.read(
        "codex",
        &exec(
            "call_3",
            r#"text(await tools.exec_command({cmd:"flutter test"}));"#,
        ),
    );
    let out = r.read(
        "codex",
        &output("call_3", json!("Script running with cell ID 9\nOutput:\n")),
    );
    assert!(out[0]["status"].is_null());
    r.read(
        "codex",
        &call(json!({"type":"function_call","name":"wait","arguments":r#"{"cell_id":"9"}"#,"call_id":"call_4"})),
    );
    let out = r.read(
        "codex",
        &call(json!({"type":"function_call_output","call_id":"call_4",
            "output":[{"type":"input_text","text":"Script completed\n"}]})),
    );
    assert_eq!(out[0]["id"], "call_3");
    assert_eq!(out[0]["status"], "completed");
    // Another function: a plain tool, done with its output.
    let js = r.read(
        "codex",
        &call(
            json!({"type":"function_call","name":"js","namespace":"mcp__cua_repl",
            "arguments":r#"{"code":"1","title":"Trouve l'onglet"}"#,"call_id":"call_5"}),
        ),
    );
    assert_eq!(js[0]["title"], "Trouve l'onglet");
    let done = r.read(
        "codex",
        &call(json!({"type":"function_call_output","call_id":"call_5","output":"ok"})),
    );
    assert_eq!(done[0]["status"], "completed");
}

fn event(payload: Value) -> Value {
    json!({"type":"event_msg","payload":payload})
}

#[test]
fn codex_desktop_messages_are_plain_events() {
    let mut r = Reader::default();
    r.read("codex", &event(json!({"type":"task_started"})));
    let user = r.read(
        "codex",
        &event(json!({"type":"user_message","client_id":"c","message":"\nrends les tuiles plus plates\n\n","images":[]})),
    );
    assert_eq!(user[0]["text"], "rends les tuiles plus plates");
    let said = |r: &mut Reader, text: &str| {
        r.read(
            "codex",
            &event(json!({"type":"agent_message","message":text,"phase":"commentary"})),
        )
    };
    let first = said(&mut r, "Je regarde les planches.\n");
    let second = said(&mut r, "C'est fait.");
    assert_eq!(first[0]["text"], "Je regarde les planches.");
    // Two messages, not one: each has its own id.
    assert_ne!(first[0]["id"], second[0]["id"]);
    // A file that has items: the plain events repeat them.
    let mut r = Reader::default();
    let item = event(
        json!({"type":"item_completed","item":{"type":"AgentMessage","id":"m1","content":[{"type":"Text","text":"Fait."}]}}),
    );
    assert_eq!(r.read("codex", &item)[0]["text"], "Fait.");
    assert!(said(&mut r, "Fait.").is_empty());
}

#[test]
fn a_patch_script_gets_its_files_diffs() {
    let mut r = Reader::default();
    let patch = r#"text(await tools.apply_patch("*** Begin Patch\n*** Update File: C:/p/a.dart\n@@\n-x\n+y\n*** Add File: C:/p/b.txt\n+un\n*** End Patch"));"#;
    assert_eq!(
        r.read("codex", &exec("call_7", patch))[0]["title"],
        "Edit a.dart +1"
    );
    let files = r.read(
        "codex",
        &event(json!({"type":"patch_apply_end","call_id":"exec-1","success":true,"changes":{
            "C:\\p\\a.dart":{"type":"update","move_path":null,"unified_diff":"@@ -3,1 +3,1 @@\n-x\n+y\n"},
            "C:\\p\\b.txt":{"type":"add","content":"un\n"}}})),
    );
    // The script's tool is the first file; the other one has its own.
    assert_eq!(files[0]["id"], "call_7");
    assert_eq!(files[0]["title"], "Edit a.dart");
    assert_eq!(files[0]["diff"]["line"], 3);
    assert_eq!(files[0]["diffs"].as_array().unwrap().len(), 1);
    assert_eq!(files[1]["id"], "call_7:1");
    assert!(files[1]["diff"]["old"].is_null());
    let done = r.read(
        "codex",
        &output(
            "call_7",
            json!([{"type":"input_text","text":"Script completed\n"}]),
        ),
    );
    assert_eq!(done[0]["status"], "completed");
    // A change Codex saw outside a patch script: a tool of its own.
    let item = event(
        json!({"type":"item_completed","item":{"type":"FileChange","id":"exec-2","status":"completed","changes":{
            "C:\\p\\c.txt":{"type":"delete","content":"vieux\n"}}}}),
    );
    let out = r.read("codex", &item);
    assert_eq!(out[0]["id"], "exec-2");
    assert_eq!(out[0]["kind"], "delete");
    assert_eq!(out[0]["title"], "Delete c.txt");
}

#[test]
fn codex_thoughts_and_compactions() {
    let mut r = Reader::default();
    let thought = r.read(
        "codex",
        &call(json!({"type":"reasoning","id":"rs_1","summary":[{"type":"summary_text","text":"**Preparing file write request**"}],"encrypted_content":"x"})),
    );
    assert_eq!(thought[0]["text"], "Preparing file write request");
    assert_eq!(thought[0]["thought"], true);
    // Most have no summary: nothing to show.
    assert!(
        r.read(
            "codex",
            &call(json!({"type":"reasoning","id":"rs_2","summary":[]}))
        )
        .is_empty()
    );
    let compact = r.read("codex", &event(json!({"type":"context_compacted"})));
    assert_eq!(compact[0]["title"], "Contexte résumé");
    // Items carry the same thought: the response is not read twice.
    let mut r = Reader::default();
    let item = event(
        json!({"type":"item_completed","item":{"type":"Reasoning","id":"rs_3","summary_text":["**Checking tests**"]}}),
    );
    assert_eq!(r.read("codex", &item)[0]["text"], "Checking tests");
    assert!(
        r.read("codex", &call(json!({"type":"reasoning","id":"rs_3","summary":[{"type":"summary_text","text":"**Checking tests**"}]})))
            .is_empty()
    );
}

#[test]
fn codex_mcp_calls_and_images_outside_scripts() {
    let mut r = Reader::default();
    let mcp = r.read(
        "codex",
        &event(json!({"type":"item_completed","item":{"type":"McpToolCall","id":"m","server":"codex_app",
            "tool":"load_workspace_dependencies","arguments":{},"status":"completed",
            "result":{"content":[{"type":"text","text":"ok"}]}}})),
    );
    assert_eq!(mcp[0]["title"], "codex_app · load_workspace_dependencies");
    assert_eq!(mcp[0]["output"], "ok");
    let image = r.read(
        "codex",
        &event(json!({"type":"item_completed","item":{"type":"ImageView","id":"i","path":"file:///C:/p/shot.png"}})),
    );
    assert_eq!(image[0]["title"], "Regarde shot.png");
    assert_eq!(image[0]["path"], "C:/p/shot.png");
}

#[test]
fn a_codex_question_waits_for_the_answer() {
    let mut r = Reader::default();
    r.read("codex", &event(json!({"type":"task_started"})));
    let asked = r.read(
        "codex",
        &call(json!({"type":"function_call","name":"request_user_input_async","call_id":"call_q",
            "arguments":r#"{"questions":[{"title":"Quel verre ?","options":["Verre blanc","Verre noir"]}]}"#})),
    );
    assert_eq!(asked[0]["type"], "question");
    assert_eq!(asked[0]["message"], "Quel verre ?");
    assert_eq!(
        asked[0]["questions"][0]["choices"][1]["value"],
        "Verre noir"
    );
    // Codex takes it and goes on: no tool for it.
    let accepted = call(
        json!({"type":"function_call_output","call_id":"call_q","output":"{\"accepted\":true}"}),
    );
    assert!(r.read("codex", &accepted).is_empty());
    let reply = r.read(
        "codex",
        &event(json!({"type":"user_message","message":"<send_user_message_question_reply>\n[{\"questionItemId\":\"[\\\"request_user_input_async\\\",\\\"call_q\\\",0]\",\"question\":\"Quel verre ?\",\"answer\":\"Verre blanc\"}]\n</send_user_message_question_reply>\n"})),
    );
    assert_eq!(reply[0]["type"], "questionAnswered");
    assert_eq!(reply[0]["id"], "call_q");
    assert_eq!(reply[1]["text"], "Verre blanc");
}

#[test]
fn a_codex_sub_agent_on_its_parent_tool() {
    let mut r = Reader::default();
    let spawn = r.read(
        "codex",
        &call(json!({"type":"function_call","name":"spawn_agent","namespace":"collaboration","call_id":"call_s",
            "arguments":r#"{"task_name":"review_tile_preview","message":"gAAAA"}"#})),
    );
    assert_eq!(spawn[0]["title"], "review_tile_preview");
    assert_eq!(spawn[0]["status"], "running");
    let started = r.read(
        "codex",
        &event(
            json!({"type":"sub_agent_activity","event_id":"call_s","agent_thread_id":"t1",
            "agent_path":"/root/review_tile_preview","kind":"started"}),
        ),
    );
    assert_eq!(started[0]["id"], "call_s");
    assert_eq!(started[0]["agent"], "t1");
    // Its launch returns at once: still running.
    let launched = call(
        json!({"type":"function_call_output","call_id":"call_s","output":"{\"task_name\":\"/root/review_tile_preview\"}"}),
    );
    assert!(r.read("codex", &launched).is_empty());
    let done = r.read(
        "codex",
        &event(json!({"type":"item_completed","item":{"type":"SubAgentActivity","id":"subagent-completed-1",
            "kind":"completed","agent_thread_id":"t1","agent_path":"/root/review_tile_preview"}})),
    );
    assert_eq!(done[0]["id"], "call_s");
    assert_eq!(done[0]["status"], "completed");
    let message = r.read(
        "codex",
        &call(json!({"type":"function_call","name":"send_message","namespace":"collaboration","call_id":"call_m",
            "arguments":r#"{"target":"review_tile_preview","message":"gAAAA"}"#})),
    );
    assert_eq!(message[0]["title"], "Écrit à review_tile_preview");
}

#[test]
fn a_codex_sub_agent_knows_its_parent() {
    let mut r = Reader::default();
    let meta = |extra: Value| {
        let mut payload = json!({"session_id":"parent","id":"child","parent_thread_id":"parent","cwd":"C:/p","originator":"codex_vscode"});
        payload
            .as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        json!({"type":"session_meta","payload":payload})
    };
    let out = r.read(
        "codex",
        &meta(json!({"agent_path":"/root/review_tile_preview","agent_nickname":"Lorentz","thread_source":"subagent"})),
    );
    assert_eq!(out[0]["id"], "child");
    let parent = r.parent.clone().unwrap();
    assert_eq!(parent["session"], "parent");
    assert_eq!(parent["agent"], "child");
    assert_eq!(parent["name"], "Lorentz");
    let mut r = Reader::default();
    r.read("codex", &meta(json!({"thread_source":"guardian_review"})));
    assert_eq!(r.parent.unwrap()["name"], "Relecteur");
    // A main session has none.
    let mut r = Reader::default();
    r.read(
        "codex",
        &json!({"type":"session_meta","payload":{"id":"main","cwd":"C:/p"}}),
    );
    assert!(r.parent.is_none());
}
