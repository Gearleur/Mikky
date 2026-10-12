use super::*;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, DuplexStream, duplex};
use tokio::sync::mpsc;

/// A scripted agent on the other end of the pipes.
struct Agent {
    input: BufReader<DuplexStream>,
    output: DuplexStream,
}

impl Agent {
    async fn next(&mut self) -> Value {
        let mut s = String::new();
        self.input.read_line(&mut s).await.unwrap();
        serde_json::from_str(&s).unwrap()
    }

    async fn send(&mut self, v: Value) {
        self.output
            .write_all(format!("{v}\n").as_bytes())
            .await
            .unwrap();
    }

    /// Answers the next request with `result`; returns it.
    async fn answer(&mut self, result: Value) -> Value {
        let r = self.next().await;
        self.send(json!({"jsonrpc": "2.0", "id": r["id"], "result": result}))
            .await;
        r
    }
}

fn start() -> (Run, Agent) {
    let (client_in, agent_out) = duplex(1 << 16);
    let (agent_in, client_out) = duplex(1 << 16);
    (
        Run::start(client_in, client_out),
        Agent {
            input: BufReader::new(agent_in),
            output: agent_out,
        },
    )
}

async fn opened() -> (Run, Agent) {
    opened_with(false).await
}

async fn opened_with(steering: bool) -> (Run, Agent) {
    let (run, mut agent) = start();
    let open = tokio::spawn({
        let run = run.clone();
        async move { run.open("/tmp/x", None, Some("default")).await }
    });
    assert_eq!(
        agent
            .answer(json!({"protocolVersion": 1, "_meta":{"steering":{"supported":steering}}}))
            .await["method"],
        "initialize"
    );
    agent.answer(json!({"sessionId": "s1"})).await;
    let mode = agent.answer(json!({})).await;
    assert_eq!(
        mode["params"],
        json!({"sessionId": "s1", "modeId": "default"})
    );
    assert_eq!(open.await.unwrap().unwrap(), "s1");
    (run, agent)
}

fn subscribe(run: &Run) -> mpsc::UnboundedReceiver<RunEvent> {
    let (tx, rx) = mpsc::unbounded_channel();
    run.subscribe(Box::new(move |e| tx.send(e).is_ok()));
    rx
}

fn permission(id: &str) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "method": "session/request_permission", "params": {"options": [
        {"optionId": "yes", "kind": "allow_once"},
        {"optionId": "always", "kind": "allow_always"},
        {"optionId": "no", "kind": "reject_once"},
    ]}})
}

/// Waits until the run holds what the agent just sent.
async fn settle(run: &Run, n: usize) {
    for _ in 0..200 {
        let pending = {
            let s = run.state.lock().unwrap();
            s.asked.len() + s.questions.len()
        };
        if pending >= n {
            return;
        }
        tokio::time::sleep(std::time::Duration::from_millis(5)).await;
    }
    panic!("nothing pending");
}

#[tokio::test]
async fn permissions_pick_the_option_the_user_meant() {
    let (run, mut agent) = opened().await;
    assert!(!run.answer(true, false, None));
    for (allow, always, want) in [
        (true, false, "yes"),
        (true, true, "always"),
        (false, false, "no"),
    ] {
        agent.send(permission("p")).await;
        settle(&run, 1).await;
        assert!(run.answer(allow, always, None));
        let r = agent.next().await;
        assert_eq!(
            r["result"]["outcome"],
            json!({"outcome": "selected", "optionId": want})
        );
    }
}

#[tokio::test]
async fn questions_and_cancel() {
    let (run, mut agent) = opened().await;
    agent
            .send(json!({"jsonrpc": "2.0", "id": 7, "method": "elicitation/create", "params": {"mode": "form"}}))
            .await;
    settle(&run, 1).await;
    assert!(run.answer_question(Some(json!({"question_0": "Postgres"}))));
    assert_eq!(
        agent.next().await["result"],
        json!({"action": "accept", "content": {"question_0": "Postgres"}})
    );

    agent.send(permission("p2")).await;
    settle(&run, 1).await;
    run.cancel();
    assert_eq!(agent.next().await["method"], "session/cancel");
    assert_eq!(
        agent.next().await["result"],
        json!({"outcome": {"outcome": "cancelled"}})
    );
    assert!(!run.answer(true, false, None));
}

#[tokio::test]
async fn subscribers_get_the_backlog_then_the_rest_then_closed() {
    let (run, mut agent) = opened().await;
    let mut rx = subscribe(&run);
    // initialize, session/new, set_mode: asked and answered.
    let mut backlog = vec![];
    for _ in 0..6 {
        let Some(RunEvent::Traffic(t)) = rx.recv().await else {
            panic!()
        };
        backlog.push(t);
    }
    assert!(backlog[0].outgoing && !backlog[1].outgoing);
    agent
        .send(json!({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": "s1"}}))
        .await;
    let RunEvent::Traffic(t) = rx.recv().await.unwrap() else {
        panic!()
    };
    assert_eq!(t.message["method"], "session/update");
    drop(agent);
    run.wait_closed().await;
    assert!(matches!(rx.recv().await, Some(RunEvent::Closed)));
    assert!(!run.alive());
    let mut late = subscribe(&run);
    let mut last = None;
    while let Some(e) = late.recv().await {
        last = Some(e);
    }
    assert!(matches!(last, Some(RunEvent::Closed)));
}

fn start_prompt(run: &Run) -> tokio::task::JoinHandle<Result<Value, RpcError>> {
    let run = run.clone();
    tokio::spawn(async move { run.prompt("work").await })
}

fn start_steering(run: &Run) -> tokio::task::JoinHandle<Result<Value, RpcError>> {
    let run = run.clone();
    tokio::spawn(async move { run.steer("next").await })
}

#[tokio::test]
async fn steering_accepts_without_ending_the_active_prompt() {
    for outcome in ["injected", "startedNewTurn"] {
        let (run, mut agent) = opened_with(true).await;
        let active = start_prompt(&run);
        let prompt = agent.next().await;
        let send = start_steering(&run);
        let request = agent.answer(json!({"outcome":outcome})).await;
        assert_eq!(request["method"], "_session/steering");
        assert_eq!(
            request["params"]["_meta"]["steering"]["idleBehavior"],
            "promptRequired"
        );
        assert_eq!(send.await.unwrap().unwrap()["outcome"], outcome);
        assert!(!active.is_finished());
        assert!(run.working());
        agent
            .send(json!({"id":prompt["id"],"result":{"stopReason":"end_turn"}}))
            .await;
        active.await.unwrap().unwrap();
        if outcome == "startedNewTurn" {
            assert!(run.working());
            agent.send(json!({"method":"session/update","params":{"update":{"sessionUpdate":"session_info_update","_meta":{"codex":{"threadStatus":{"type":"idle"}}}}}})).await;
            for _ in 0..100 {
                if !run.working() {
                    break;
                }
                tokio::task::yield_now().await;
            }
        }
        assert!(!run.working());
    }
}

#[tokio::test]
async fn steering_falls_back_only_when_not_accepted() {
    for reply in [
        json!({"result":{"outcome":"promptRequired"}}),
        json!({"result":{"outcome":"failed"}}),
        json!({"error":{"code":-32601,"message":"unsupported"}}),
    ] {
        let (run, mut agent) = opened_with(true).await;
        let active = start_prompt(&run);
        let prompt = agent.next().await;
        let send = start_steering(&run);
        let steering = agent.next().await;
        let mut response = reply;
        response["id"] = steering["id"].clone();
        agent.send(response).await;
        let fallback = agent.answer(json!({"stopReason":"end_turn"})).await;
        assert_eq!(fallback["method"], "session/prompt");
        send.await.unwrap().unwrap();
        agent
            .send(json!({"id":prompt["id"],"result":{"stopReason":"end_turn"}}))
            .await;
        active.await.unwrap().unwrap();
    }
}

#[tokio::test]
async fn idle_or_unadvertised_steering_uses_prompt() {
    for supported in [false, true] {
        let (run, mut agent) = opened_with(supported).await;
        let send = start_steering(&run);
        assert_eq!(
            agent.answer(json!({"stopReason":"end_turn"})).await["method"],
            "session/prompt"
        );
        send.await.unwrap().unwrap();
    }
    let (run, mut agent) = opened().await;
    let active = start_prompt(&run);
    let prompt = agent.next().await;
    let send = start_steering(&run);
    assert_eq!(
        agent.answer(json!({"stopReason":"end_turn"})).await["method"],
        "session/prompt"
    );
    send.await.unwrap().unwrap();
    agent
        .send(json!({"id":prompt["id"],"result":{"stopReason":"end_turn"}}))
        .await;
    active.await.unwrap().unwrap();
}

#[tokio::test]
async fn ambiguous_steering_failure_is_not_sent_twice() {
    let (run, mut agent) = opened_with(true).await;
    let active = start_prompt(&run);
    agent.next().await;
    let send = start_steering(&run);
    let request = agent.next().await;
    agent
        .send(json!({"id":request["id"],"error":{"code":-32603,"message":"uncertain"}}))
        .await;
    assert!(send.await.unwrap().is_err());
    assert!(
        tokio::time::timeout(std::time::Duration::from_millis(30), agent.next())
            .await
            .is_err()
    );
    drop(agent);
    let _ = active.await;
}

#[tokio::test]
async fn unknown_requests_get_an_error() {
    let (_run, mut agent) = opened().await;
    agent
        .send(json!({"jsonrpc": "2.0", "id": 3, "method": "fs/read_text_file", "params": {}}))
        .await;
    assert_eq!(agent.next().await["error"]["code"], -32601);
}
