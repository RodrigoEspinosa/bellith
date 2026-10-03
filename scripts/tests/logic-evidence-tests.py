#!/usr/bin/env python3
"""Logic proposal protocol checks. Optional live Codex uses only synthetic files."""
import json
import pathlib
import subprocess
import sys
import tempfile
import time
import uuid

cli = str(pathlib.Path(sys.argv[1]).resolve())
work = pathlib.Path(tempfile.mkdtemp(prefix="bellith-logic-evidence-"))
fixture = work / "logic.json"
resolve = work / "missing-resolve.json"
observation = {"id": str(uuid.uuid4()), "processID": 123, "documentURL": "file:///tmp/Synthetic.logicx",
               "windowTitle": "Synthetic - Tracks", "playing": False, "recording": False,
               "inspectedAt": time.time() - 978307200,
               "exposedTracks": [{"number": 1, "name": "Synthetic vocals", "selected": True, "soloed": False}]}
fixture.write_text(json.dumps(observation))
saved = fixture.read_bytes()

def call(name, arguments, expected_id=None):
    messages = [{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25"}},
                {"jsonrpc": "2.0", "method": "notifications/initialized"},
                {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": name, "arguments": arguments}}]
    run = subprocess.run([cli, "mcp", "--session-file", str(resolve), "--logic-session-file", str(fixture)] + (["--logic-observation-id", expected_id] if expected_id else []),
                         input="\n".join(map(json.dumps, messages)) + "\n", text=True, capture_output=True, check=True)
    return json.loads(run.stdout.splitlines()[-1])["result"]

evidence = json.loads(call("logic_saved_transport", {})["content"][0]["text"])
assert evidence["observation"]["id"].lower() == observation["id"].lower()
assert evidence["observation"]["exposedTracks"] == observation["exposedTracks"]
assert "not a full session" in evidence["trackCoverage"]
assert evidence["liveInspection"] is False
assert evidence["requiresFreshInspectionBeforeExecution"] is True
assert evidence["supportedReviewedOperations"] == ["play", "stop"]
assert call("logic_saved_transport", {}, observation["id"])["isError"] is False
old_id = str(uuid.uuid4())
assert call("logic_saved_transport", {}, old_id)["isError"] is True
assert "Synthetic" not in call("logic_saved_transport", {}, old_id)["content"][0]["text"]
assert call("logic_propose_transport", {"observationID": observation["id"], "action": "play", "reason": "Explicit playback request"}, old_id)["isError"] is True
arguments = {"observationID": observation["id"], "action": "play", "reason": "The user requested playback."}
receipt = call("logic_propose_transport", arguments)
assert receipt["isError"] is False
value = json.loads(receipt["content"][0]["text"])
assert value["executed"] is False and value["state"] == "awaiting-native-review"
review_url = subprocess.run([cli, "review", "logic", value["proposalID"], "--print-url"], check=True, text=True, capture_output=True).stdout.strip()
assert review_url == value["reviewURL"]
assert value["reviewCommand"] == "bellith review logic " + value["proposalID"]
assert review_url.startswith("bellith://review?tool=logic&proposal=")
for bad in [["record", value["proposalID"]], ["logic", "invalid"], ["logic", value["proposalID"], "--execute"]]:
    assert subprocess.run([cli, "review", *bad, "--print-url"], capture_output=True).returncode != 0
assert fixture.read_bytes() == saved
assert len(list((work / "proposals").glob("*.json"))) == 1
for invalid in [dict(arguments, action="record"), dict(arguments, observationID=str(uuid.uuid4())),
                dict(arguments, reason=""), dict(arguments, executable="arbitrary")]:
    assert call("logic_propose_transport", invalid)["isError"] is True
assert len(list((work / "proposals").glob("*.json"))) == 1
track_arguments = {"observationID": observation["id"], "trackNumber": 1, "trackName": "Synthetic vocals", "control": "solo", "enabled": True, "reason": "User explicitly requested solo preview"}
track_receipt = call("logic_propose_track_control", track_arguments, observation["id"])
assert track_receipt["isError"] is False
track_value = json.loads(track_receipt["content"][0]["text"])
assert track_value["executed"] is False and track_value["hostExecutionAvailable"] is False
track_url = subprocess.run([cli, "review", "logic-track", track_value["proposalID"], "--print-url"], check=True, capture_output=True, text=True).stdout.strip()
assert track_url == track_value["reviewURL"]
assert track_value["reviewCommand"] == "bellith review logic-track " + track_value["proposalID"]
assert fixture.read_bytes() == saved
assert len(list((work / "track-proposals").glob("*.json"))) == 1
for changes in [{"enabled": "true"}, {"trackName": "Wrong"}, {"trackNumber": 2}, {"control": "volume"}, {"reason": ""}, {"extra": "command"}, {"observationID": str(uuid.uuid4())}]:
    assert call("logic_propose_track_control", dict(track_arguments, **changes))["isError"] is True
assert call("logic_propose_track_control", track_arguments, str(uuid.uuid4()))["isError"] is True
assert len(list((work / "track-proposals").glob("*.json"))) == 1
observation["recording"] = True
fixture.write_text(json.dumps(observation))
assert call("logic_propose_transport", arguments)["isError"] is True
fixture.write_text("null")
assert json.loads(call("logic_saved_transport", {})["content"][0]["text"])["state"] == "no-reviewable-observation"
assert call("logic_propose_transport", arguments)["isError"] is True
attempt_file = work / "last-attempt.json"
attempt = {"id": str(uuid.uuid4()), "startedAt": time.time() - 978307200, "phase": "pending",
           "action": "play", "expected": observation}
attempt_file.write_text(json.dumps(attempt))
interrupted = json.loads(call("logic_saved_transport", {})["content"][0]["text"])
assert interrupted["lastAttempt"]["phase"] == "pending"
assert interrupted["interruptedOrUnverifiedAction"] is True
assert interrupted["automaticRetryAllowed"] is False
assert interrupted["interruptedActionRequiresReview"] is True
assert interrupted["actionOutcomeVerified"] is False
attempt["phase"] = "acknowledged"
attempt["observed"] = dict(observation, recording=False, playing=True)
attempt_file.write_text(json.dumps(attempt))
acknowledged = json.loads(call("logic_saved_transport", {})["content"][0]["text"])
assert acknowledged["interruptedOrUnverifiedAction"] is False
assert acknowledged["automaticRetryAllowed"] is False
attempt["phase"] = "reviewed"
attempt["reviewedAt"] = time.time() - 978307200
attempt["reviewedSnapshot"] = dict(observation, id=str(uuid.uuid4()), recording=False)
attempt_file.write_text(json.dumps(attempt))
reviewed = json.loads(call("logic_saved_transport", {})["content"][0]["text"])
assert reviewed["interruptedOrUnverifiedAction"] is True
assert reviewed["interruptedActionRequiresReview"] is False
assert reviewed["actionOutcomeVerified"] is False
assert reviewed["automaticRetryAllowed"] is False
# Receipt access stays bound to the original observation after current context clears.
result_args = {"observationID": observation["id"]}
results = json.loads(call("logic_saved_action_results", result_args, observation["id"])["content"][0]["text"])
assert results["playback"]["phase"] == "reviewed"
assert results["playback"]["actionOutcomeVerified"] is False
assert results["automaticRetryAllowed"] is False
replacement = dict(observation, id=str(uuid.uuid4()), windowTitle="Other private project")
fixture.write_text(json.dumps(replacement))
assert call("logic_saved_transport", {}, observation["id"])["isError"] is True
bound_results = call("logic_saved_action_results", result_args, observation["id"])
assert bound_results["isError"] is False
assert "Other private project" not in bound_results["content"][0]["text"]
new_results = json.loads(call("logic_saved_action_results", {"observationID": replacement["id"]}, replacement["id"])["content"][0]["text"])
assert new_results["state"] == "no-matching-latest-receipts"
new_evidence = json.loads(call("logic_saved_transport", {}, replacement["id"])["content"][0]["text"])
assert "lastAttempt" not in new_evidence
assert new_evidence["recoveryReviewRequired"] is False
attempt["phase"] = "needsAttention"
attempt_file.write_text(json.dumps(attempt))
recovery_evidence = json.loads(call("logic_saved_transport", {}, replacement["id"])["content"][0]["text"])
assert recovery_evidence["recoveryReviewRequired"] is True
assert recovery_evidence["automaticRetryAllowed"] is False
assert "lastAttempt" not in recovery_evidence
assert observation["id"] not in json.dumps(recovery_evidence)
assert "acknowledge" in recovery_evidence["nextStep"]
for invalid in [{}, {"observationID": "invalid"}, dict(result_args, execute=True), {"observationID": replacement["id"]}]:
    assert call("logic_saved_action_results", invalid, observation["id"])["isError"] is True
fixture.write_text("null")
attempt_file.unlink()
track_attempt = {"id": str(uuid.uuid4()), "startedAt": time.time() - 978307200, "phase": "pending",
                 "request": {"observationID": observation["id"], "trackNumber": 1, "trackName": "Synthetic vocals", "control": "mute", "enabled": True},
                 "expected": observation}
track_file = work / "last-track-attempt.json"
track_file.write_text(json.dumps(track_attempt))
track_evidence = json.loads(call("logic_saved_transport", {})["content"][0]["text"])
track_results = json.loads(call("logic_saved_action_results", result_args, observation["id"])["content"][0]["text"])
assert track_results["track"]["phase"] == "pending"
assert track_results["track"]["actionOutcomeVerified"] is False
assert track_evidence["trackActionRequiresInspection"] is True
assert track_evidence["trackActionOutcomeVerified"] is False
assert track_evidence["automaticRetryAllowed"] is False
track_attempt["phase"] = "reviewed"
track_attempt["reviewedAt"] = time.time() - 978307200
track_attempt["reviewedSnapshot"] = observation
track_file.write_text(json.dumps(track_attempt))
track_evidence = json.loads(call("logic_saved_transport", {})["content"][0]["text"])
assert track_evidence["trackActionRequiresInspection"] is False
assert track_evidence["trackActionOutcomeVerified"] is False
track_file.unlink()
print("Logic MCP protocol checks passed, including interrupted action evidence")

if len(sys.argv) > 2 and "--results" in sys.argv:
    # Random receipt identifiers are available only through the actual MCP call.
    observation["id"] = str(uuid.uuid4())
    observation["recording"] = False
    attempt = {"id": str(uuid.uuid4()), "proposalID": str(uuid.uuid4()),
               "startedAt": time.time() - 978307200, "phase": "reviewed", "action": "play",
               "expected": observation, "reviewedAt": time.time() - 978307200,
               "reviewedSnapshot": dict(observation, id=str(uuid.uuid4()))}
    attempt_file.write_text(json.dumps(attempt))
    fixture.write_text("null")
    saved_receipt = attempt_file.read_bytes()
    saved_observation = fixture.read_bytes()
    schema = work / "result-schema.json"
    fields = {"attemptID": {"type": "string"}, "proposalID": {"type": "string"},
              "phase": {"type": "string", "enum": ["pending", "acknowledged", "needsAttention", "reviewed"]},
              "actionOutcomeVerified": {"type": "boolean"}, "requiresInspection": {"type": "boolean"},
              "automaticRetryAllowed": {"type": "boolean"},
              "nextStep": {"type": "string", "enum": ["inspect-before-new-action", "report-verified-saved-outcome"]}}
    schema.write_text(json.dumps({"type": "object", "additionalProperties": False,
                                  "properties": fields, "required": list(fields)}))
    result = work / "action-result.json"
    args = [str(pathlib.Path(sys.argv[2]).resolve()), "exec", "--json", "--ignore-user-config", "--ignore-rules",
            "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--disable", "shell_tool",
            "--disable", "apps", "--disable", "hooks",
            "-c", "mcp_servers.bellith.command=" + json.dumps(cli),
            "-c", "mcp_servers.bellith.args=" + json.dumps(["mcp", "--creative-scope", "logic",
                "--logic-observation-id", observation["id"], "--logic-session-file", str(fixture), "--session-file", str(resolve)]),
            "--output-schema", str(schema), "--output-last-message", str(result), "-"]
    prompt = ("Read the saved action result for original Logic observation " + observation["id"] +
              ". The current observation has been cleared. Call only logic_saved_action_results exactly once, "
              "with the argument object " + json.dumps({"observationID": observation["id"]}) + ". "
              "Return the playback receipt identifiers and state in the required JSON schema. "
              "Explain the next step through nextStep: unverified original actions require inspect-before-new-action; "
              "only verified saved outcomes permit report-verified-saved-outcome. A reviewed interruption does not "
              "prove the requested action completed. Do not propose, retry, execute, or use any other tool.")
    with (work / "action-result-trace.log").open("w") as log:
        run = subprocess.run(args, cwd=work, input=prompt, text=True, stdout=log, stderr=log, timeout=120)
    assert run.returncode == 0, f"Codex result qualification failed: {work}"
    value = json.loads(result.read_text())
    assert value["attemptID"].lower() == attempt["id"].lower()
    assert value["proposalID"].lower() == attempt["proposalID"].lower()
    assert value["phase"] == "reviewed" and value["actionOutcomeVerified"] is False
    assert value["requiresInspection"] is False and value["automaticRetryAllowed"] is False
    assert value["nextStep"] == "inspect-before-new-action"
    calls = []
    for line in (work / "action-result-trace.log").read_text().splitlines():
        try: event = json.loads(line)
        except ValueError: continue
        item = event.get("item", {})
        if event.get("type") == "item.completed" and item.get("type") == "mcp_tool_call": calls.append(item)
    assert len(calls) == 1 and calls[0].get("tool") == "logic_saved_action_results" and calls[0].get("error") is None
    assert attempt_file.read_bytes() == saved_receipt and fixture.read_bytes() == saved_observation
    print(f"Real Codex saved-result interpretation passed: {work}")
    sys.exit(0)

if len(sys.argv) > 2:
    # A separate observation binds the real model to random synthetic evidence.
    observation["recording"] = False
    observation["id"] = str(uuid.uuid4())
    fixture.write_text(json.dumps(observation))
    saved = fixture.read_bytes()
    track_mode = "--track" in sys.argv
    proposal_directory = work / ("track-proposals" if track_mode else "proposals")
    before = set(proposal_directory.glob("*.json"))
    result = work / "result.json"
    codex = str(pathlib.Path(sys.argv[2]).resolve())
    args = [codex, "exec", "--json", "--ignore-user-config", "--ignore-rules", "--ephemeral", "--skip-git-repo-check",
            "--sandbox", "read-only", "--disable", "shell_tool", "--disable", "apps", "--disable", "hooks",
            "-c", "mcp_servers.bellith.command=" + json.dumps(cli),
            "-c", "mcp_servers.bellith.args=" + json.dumps(["mcp", "--creative-scope", "logic", "--logic-observation-id", observation["id"], "--session-file", str(resolve), "--logic-session-file", str(fixture)]),
            "--output-last-message", str(result), "-"]
    prompt = "The user explicitly requests starting playback in a synthetic Logic fixture. Call only Bellith logic_saved_transport then logic_propose_transport with the exact observationID, action play, and a reason explaining the request. Queue one proposal for native review. Never execute playback or claim the saved observation is live. Do not call other tools."
    if track_mode:
        prompt = "The user explicitly requests a SOLO-ON proposal for the exposed Synthetic vocals track in a synthetic Logic fixture. Call only logic_saved_transport and logic_propose_track_control. Use the exact observed UUID, track number and track name, control solo, enabled true, and a reason describing the user's request. Queue exactly one native review proposal. Execution is unavailable pending live qualification; that is expected and does not prevent review-only submission. Never execute or claim Logic changed. Do not use other tools."
    with (work / "trace.log").open("w") as log:
        run = subprocess.run(args, cwd=work, input=prompt, text=True, stdout=log, stderr=log, timeout=120)
    assert run.returncode == 0, f"Codex failed: {work}"
    added = set(proposal_directory.glob("*.json")) - before
    assert len(added) == 1, f"Expected one proposal: {work}"
    proposal = json.loads(next(iter(added)).read_text())
    if track_mode:
        request = proposal["request"]
        assert request["observationID"].lower() == observation["id"].lower()
        assert request["trackNumber"] == 1 and request["trackName"] == "Synthetic vocals"
        assert request["control"] == "solo" and request["enabled"] is True
    else:
        assert proposal["observationID"].lower() == observation["id"].lower() and proposal["action"] == "play"
    assert fixture.read_bytes() == saved
    trace = (work / "trace.log").read_text()
    tool = "logic_propose_track_control" if track_mode else "logic_propose_transport"
    assert "logic_saved_transport" in trace and tool in trace
    calls = []
    for line in trace.splitlines():
        try: event = json.loads(line)
        except ValueError: continue
        item = event.get("item", {})
        if event.get("type") == "item.completed" and item.get("type") == "mcp_tool_call" and item.get("tool") == tool:
            calls.append(item)
    assert len(calls) == 1 and calls[0].get("error") is None, f"Expected one successful actual proposal call: {work}"
    if track_mode:
        receipt = json.loads(calls[0]["result"]["content"][0]["text"])
        assert receipt["executed"] is False and receipt["hostExecutionAvailable"] is False
    print(f"Live Codex Logic proposal passed: {work}")
