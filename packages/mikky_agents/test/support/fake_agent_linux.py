"""Small ACP process for the WSL lifecycle integration test; no AI/network."""
import json
import sys

pending = None
def send(value):
    print(json.dumps(value), flush=True)

for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    if method == "initialize":
        result = {"protocolVersion": 1, "agentCapabilities": {"loadSession": True}}
    elif method in ("session/new", "session/load"):
        result = {"sessionId": "mikky-wsl-test"}
    elif method == "session/prompt":
        pending = message["id"]
        send({"jsonrpc": "2.0", "id": "permission", "method": "session/request_permission", "params": {
            "sessionId": "mikky-wsl-test", "toolCall": {"toolCallId": "write", "title": "Write a.txt", "kind": "edit", "status": "pending"},
            "options": [{"optionId": "yes", "kind": "allow_once", "name": "Oui"}, {"optionId": "no", "kind": "reject_once", "name": "Non"}]}})
        continue
    elif method == "session/cancel":
        continue
    elif method is None:
        if pending is not None:
            send({"jsonrpc": "2.0", "id": pending, "result": {"stopReason": "end_turn"}})
            pending = None
        continue
    else:
        result = {}
    if "id" in message:
        send({"jsonrpc": "2.0", "id": message["id"], "result": result})
