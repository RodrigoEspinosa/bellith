#!/usr/bin/env python3
"""Exercise the built CLI with disposable session evidence; no model calls."""
import json
import pathlib
import subprocess
import sys
import tempfile
import uuid

cli = pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="bellith-evidence-") as directory:
    fixture = pathlib.Path(directory) / "current.json"
    empty = subprocess.run([str(cli), "creative", "status", "--session-file", str(fixture)], check=True, capture_output=True, text=True)
    assert json.loads(empty.stdout)["state"] == "no-saved-session"
    fixture.write_text(json.dumps({"id": str(uuid.uuid4()), "goal": "Synthetic evidence fixture", "phase": "review", "events": []}))
    def request(identifier, method, params=None):
        result = {"jsonrpc": "2.0", "method": method}
        if identifier is not None:
            result["id"] = identifier
        if params is not None:
            result["params"] = params
        return json.dumps(result)
    messages = [request(1, "tools/list"), request(2, "initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "fixture", "version": "1"}}),
                request(None, "notifications/initialized"), request(3, "tools/list"),
                request(4, "tools/call", {"name": "resolve_saved_session", "arguments": {}}),
                request(5, "tools/call", {"name": "edit_timeline", "arguments": {}}),
                request(6, "tools/call", {"name": "resolve_saved_session", "arguments": "invalid"}),
                request(7, "ping"), "malformed"]
    run = subprocess.run([str(cli), "mcp", "--session-file", str(fixture)], input="\n".join(messages) + "\n", check=True, capture_output=True, text=True)
    responses = [json.loads(line) for line in run.stdout.splitlines()]
    by_id = {reply["id"]: reply for reply in responses}
    assert len(responses) == 8
    assert by_id[1]["error"]["code"] == -32002
    assert by_id[2]["result"]["protocolVersion"] == "2025-11-25"
    tools = by_id[3]["result"]["tools"]
    assert [tool["name"] for tool in tools] == ["resolve_saved_session", "resolve_propose_plan", "logic_saved_transport", "logic_propose_transport", "logic_propose_track_control", "logic_saved_action_results"]
    assert tools[0]["annotations"]["readOnlyHint"] is True
    assert tools[1]["inputSchema"]["properties"]["plan"]["properties"]["blockedReason"]["enum"] == [""]
    evidence = json.loads(by_id[4]["result"]["content"][0]["text"])
    assert evidence["session"]["goal"] == "Synthetic evidence fixture"
    assert evidence["liveInspection"] is False
    assert evidence["requiresFreshInspectionBeforeExecution"] is True
    assert evidence["savedAt"]
    assert evidence["workflow"]["automaticRetryAllowed"] is False
    assert evidence["workflow"]["userAcceptedResult"] is False
    assert evidence["workflow"]["playbackQualityVerifiedByThisTool"] is False
    original_fixture = fixture.read_bytes()
    for phase in ["duplicating", "editing", "paused", "needsAttention", "readyForReview", "accepted"]:
        fixture.write_text(json.dumps({"id": str(uuid.uuid4()), "goal": "Result fixture", "phase": phase, "events": []}))
        saved = subprocess.run([str(cli), "creative", "status", "--session-file", str(fixture)], check=True, capture_output=True, text=True)
        workflow = json.loads(saved.stdout)["workflow"]
        assert workflow["phase"] == phase
        assert workflow["automaticRetryAllowed"] is False
        assert workflow["playbackQualityVerifiedByThisTool"] is False
        assert workflow["userAcceptedResult"] is (phase == "accepted")
        assert workflow["workingCopyRecorded"] is False
        assert workflow["nextStep"]
    fixture.write_bytes(original_fixture)
    assert by_id[5]["error"]["code"] == -32602
    assert by_id[6]["error"]["code"] == -32602
    assert by_id[7]["result"] == {}
    assert by_id[None]["error"]["code"] == -32700
    for scope, disallowed in [("resolve", "logic_saved_transport"), ("logic", "resolve_saved_session")]:
        scoped_messages = [messages[1], messages[2], request(20, "tools/list"), request(21, "tools/call", {"name": disallowed, "arguments": {}})]
        scoped_run = subprocess.run([str(cli), "mcp", "--session-file", str(fixture), "--creative-scope", scope], input="\n".join(scoped_messages) + "\n", check=True, capture_output=True, text=True)
        scoped_replies = {reply["id"]: reply for reply in map(json.loads, scoped_run.stdout.splitlines())}
        exposed = scoped_replies[20]["result"]["tools"]
        assert len(exposed) == (2 if scope == "resolve" else 4) and all(tool["name"].startswith(scope + "_") for tool in exposed)
        assert scoped_replies[21]["error"]["code"] == -32602
    assert subprocess.run([str(cli), "mcp", "--creative-scope", "all"], capture_output=True).returncode != 0
    session_id = str(uuid.uuid4())
    source = {"projectID": "fixture", "projectName": "Fixture", "timelineID": "source", "timelineName": "Source",
              "startFrame": 0, "endFrame": 24, "frameRate": "24", "product": "Mock", "version": "test",
              "clips": [{"key": "clip-a", "name": "A", "kind": "audio", "track": 1, "startFrame": 0, "endFrame": 24,
                         "enabled": False, "sourceStartFrame": 0, "sourceEndFrame": 23, "mediaPoolItemID": "synthetic-media-id"}],
              "signature": "fixture-source", "markers": []}
    fixture.write_text(json.dumps({"id": session_id, "goal": "Remove A", "phase": "draft", "events": [], "source": source}))
    def page(value):
        lines = [messages[1], messages[2], request(9, "tools/call", {"name": "resolve_saved_session", "arguments": value})]
        run = subprocess.run([str(cli), "mcp", "--session-file", str(fixture)], input="\n".join(lines) + "\n", check=True, capture_output=True, text=True)
        return {reply["id"]: reply for reply in map(json.loads, run.stdout.splitlines())}[9]["result"]
    paging = {"sessionID": session_id.upper(), "sourceSignature": "fixture-source", "collection": "clips", "offset": 0, "limit": 1}
    paged = page(paging)
    assert paged["isError"] is False
    data = json.loads(paged["content"][0]["text"])
    assert data["page"]["items"][0]["key"] == "clip-a"
    assert data["page"]["items"][0]["enabled"] is False
    assert data["page"]["items"][0]["sourceStartFrame"] == 0
    assert data["page"]["items"][0]["sourceEndFrame"] == 23
    assert data["page"]["items"][0]["mediaPoolItemID"] == "synthetic-media-id"
    full_read = subprocess.run([str(cli), "creative", "status", "--session-file", str(fixture)], check=True, capture_output=True, text=True)
    assert json.loads(full_read.stdout)["session"]["source"]["clips"][0] == data["page"]["items"][0]
    assert data["page"]["nextOffset"] is None and data["page"]["total"] == 1
    assert "clips" not in data["session"]["source"] and "events" not in data["session"]
    assert data["workflow"]["phase"] == "draft"
    assert data["workflow"]["automaticRetryAllowed"] is False
    assert json.loads(page(dict(paging, offset=1))["content"][0]["text"])["page"]["items"] == []
    for changes in [{"sessionID": str(uuid.uuid4())}, {"sourceSignature": "stale"}, {"offset": -1}, {"offset": True}, {"offset": 2}, {"limit": 51}, {"limit": 0}, {"collection": "unknown"}]:
        assert page(dict(paging, **changes))["isError"] is True
    unknown_clip = {key: value for key, value in source["clips"][0].items()
                    if key not in ["enabled", "sourceStartFrame", "sourceEndFrame", "mediaPoolItemID"]}
    unknown_source = dict(source, clips=[unknown_clip])
    fixture.write_text(json.dumps({"id": session_id, "goal": "Remove A", "phase": "draft", "events": [], "source": unknown_source}))
    unknown_item = json.loads(page(paging)["content"][0]["text"])["page"]["items"][0]
    assert all(key not in unknown_item for key in ["enabled", "sourceStartFrame", "sourceEndFrame", "mediaPoolItemID"])
    large_source = dict(source, clips=[dict(source["clips"][0], key=f"clip-{index}") for index in range(123)])
    fixture.write_text(json.dumps({"id": session_id, "goal": "Remove A", "phase": "draft", "events": [], "source": large_source}))
    collected = []
    offset = 0
    token = None
    while True:
        result = page(dict(paging, offset=offset, limit=50, **({"checkpointToken": token} if token else {})))
        assert result["isError"] is False
        envelope = json.loads(result["content"][0]["text"])
        token = envelope["checkpointToken"]
        chunk = envelope["page"]
        assert chunk["total"] == 123 and len(chunk["items"]) <= 50
        collected.extend(item["key"] for item in chunk["items"])
        if chunk["nextOffset"] is None:
            break
        offset = chunk["nextOffset"]
    assert collected == [f"clip-{index}" for index in range(123)]
    empty_markers = json.loads(page(dict(paging, collection="markers"))["content"][0]["text"])["page"]
    assert empty_markers["coverage"] == "saved-collection" and empty_markers["items"] == []
    missing_markers = dict(large_source)
    missing_markers.pop("markers")
    fixture.write_text(json.dumps({"id": session_id, "goal": "Remove A", "phase": "draft", "events": [], "source": missing_markers}))
    assert page(dict(paging, checkpointToken=token))["isError"] is True
    unknown = json.loads(page(dict(paging, collection="markers"))["content"][0]["text"])["page"]
    assert unknown["coverage"] == "unavailable"
    fixture.write_text(json.dumps({"id": session_id, "goal": "Remove A", "phase": "draft", "events": [], "source": source}))
    original = fixture.read_bytes()
    proposal = {"sessionID": session_id, "goal": "Remove A", "sourceSignature": "fixture-source",
                "plan": {"summary": "Duplicate and remove A, leaving gaps", "blockedReason": "", "removeClipKeys": ["clip-a"], "markerNotes": []}}
    def submit(value):
        lines = [messages[1], messages[2], request(8, "tools/call", {"name": "resolve_propose_plan", "arguments": value})]
        run = subprocess.run([str(cli), "mcp", "--session-file", str(fixture)], input="\n".join(lines) + "\n", check=True, capture_output=True, text=True)
        return {reply["id"]: reply for reply in map(json.loads, run.stdout.splitlines())}[8]["result"]
    result = submit(proposal)
    assert result["isError"] is False
    receipt = json.loads(result["content"][0]["text"])
    assert receipt["state"] == "awaiting-native-review" and receipt["executed"] is False
    review_url = subprocess.run([str(cli), "review", "resolve", receipt["proposalID"], "--print-url"], check=True, text=True, capture_output=True).stdout.strip()
    assert review_url == receipt["reviewURL"]
    assert receipt["reviewCommand"] == "bellith review resolve " + receipt["proposalID"]
    assert fixture.read_bytes() == original, "A proposal must not modify current session state"
    inbox = pathlib.Path(directory) / session_id / "proposals"
    queued = json.loads((inbox / (receipt["proposalID"] + ".json")).read_text())
    assert queued["plan"]["removeClipKeys"] == ["clip-a"]
    for field, value in [("sessionID", str(uuid.uuid4())), ("sourceSignature", "stale"), ("goal", "Different task")]:
        invalid = dict(proposal)
        invalid[field] = value
        assert submit(invalid)["isError"] is True
    invalid = dict(proposal)
    invalid["plan"] = dict(proposal["plan"], removeClipKeys=["unknown"])
    assert submit(invalid)["isError"] is True
    assert len(list(inbox.glob("*.json"))) == 1
    for phase in ["inspecting", "planning", "duplicating", "editing", "paused", "needsAttention", "readyForReview", "accepted"]:
        state = json.loads(original)
        state["phase"] = phase
        fixture.write_text(json.dumps(state))
        before = fixture.read_bytes()
        assert submit(proposal)["isError"] is True, f"Proposal accepted during {phase}"
        assert fixture.read_bytes() == before
        assert len(list(inbox.glob("*.json"))) == 1
    state = json.loads(original)
    state["working"] = dict(source, timelineID="working", timelineName="Working")
    fixture.write_text(json.dumps(state))
    assert submit(proposal)["isError"] is True
    assert len(list(inbox.glob("*.json"))) == 1
    fixture.write_bytes(original)
    scoped = pathlib.Path(directory) / session_id.upper() / "session.json"
    scoped.parent.mkdir(parents=True, exist_ok=True)
    scoped.write_bytes(original)
    scoped_original = scoped.read_bytes()
    queued_before = len(list((scoped.parent / "proposals").glob("*.json")))
    fixture.write_text(json.dumps({"id": str(uuid.uuid4()), "goal": "Other window", "phase": "draft", "events": []}))
    scoped_lines = [messages[1], messages[2], request(10, "tools/call", {"name": "resolve_saved_session", "arguments": {}}),
                    request(11, "tools/call", {"name": "resolve_propose_plan", "arguments": proposal})]
    scoped_run = subprocess.run([str(cli), "mcp", "--session-file", str(scoped)], input="\n".join(scoped_lines) + "\n", check=True, capture_output=True, text=True)
    scoped_replies = {reply["id"]: reply for reply in map(json.loads, scoped_run.stdout.splitlines())}
    assert json.loads(scoped_replies[10]["result"]["content"][0]["text"])["session"]["goal"] == "Remove A"
    assert scoped_replies[11]["result"]["isError"] is False
    assert len(list((scoped.parent / "proposals").glob("*.json"))) == queued_before + 1
    assert not (scoped.parent / session_id.upper()).exists(), "Scoped proposals must not nest another session directory"
    assert scoped.read_bytes() == scoped_original
    fixture.write_text('{"private": "malformed secret data"}')
    run = subprocess.run([str(cli), "mcp", "--session-file", str(fixture)], input="\n".join(messages[:5]) + "\n", check=True, capture_output=True, text=True)
    replies = {reply["id"]: reply for reply in map(json.loads, run.stdout.splitlines())}
    assert replies[4]["result"]["isError"] is True
    assert "malformed secret data" not in run.stdout
print("Creative evidence: missing/valid/corrupt state, MCP lifecycle, tool scope, proposals and errors passed")
