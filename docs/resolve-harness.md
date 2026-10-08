# Resolve goal sessions

Open **File → Resolve Goal Session** (⇧⌘G). A development launch can also use
`--resolve-harness`. The media library and terminal remain available from the sidebar.

This is the first bounded editing harness: a goal, inspected Resolve state, a structured
plan, reviewed execution, checkpoints, and verification evidence in a saved session.

## Current tool set

- Inspect the open project and timeline: names, IDs, tracks, item positions, and frame rate.
- Duplicate the inspected timeline into a uniquely named `Bellith - <session UUID>` copy.
- Remove explicitly selected whole timeline items from the working copy **without ripple**.
  Remaining clips stay in place; removals leave gaps. This does not trim at arbitrary frames.
- Add up to 20 reviewed one-frame Blue markers at explicit whole-frame offsets, without replacing existing markers. Marker plans and removal plans are separate.
- Verify requested markers/removals, remaining clip positions, and original timeline structure.
- Pause at an operation boundary, recover an interrupted session through inspection,
  and accept a result after playback review in Resolve.

Effects, semantic footage selection, transcription, frame-level cuts, exports, and grading
are not implemented. The planner must report an unsupported goal rather than substitute
an available operation. Structural checks cannot judge pacing, sound, or visual quality.

## Connection on this Mac

Resolve 21.1.0 (runtime 21.1.0.17), product `DaVinci Resolve`, was checked locally.
The bundled external Python client returned no Resolve connection. The documented
internal Lua Console accepted a read-only query, timeline inspection, and duplication.

Bellith uses macOS Accessibility to address Resolve by bundle ID and discover the
**Workspace → Console** menu and editable Console text area. Commands are generated
from a fixed adapter, with all request values escaped as Lua data. No model-generated
code, arbitrary shell command, global click coordinates, or installed Resolve plugin is
used. Keep the Console in **Lua** mode and its input empty. English menus are required
for automatic Console discovery in this version.

Resolve's Console on this installation does not expose Lua's `io` library. Responses
therefore appear as `BELLITH_RESULT:` JSON lines in the Console. Bellith reads matching
request IDs through Accessibility and writes evidence into its own session folder.
No change to Resolve's scripting security configuration is needed.

### First run

1. Open a project and timeline in Resolve.
2. In Bellith, open **File → Resolve Goal Session**.
3. Click **Enable Accessibility**, then grant Bellith access in macOS System Settings.
   This OS permission is required for Bellith itself to operate Resolve. Screen Recording
   is not needed; this first version does not capture or send screenshots.
4. Choose **Inspect Resolve**. Bellith opens the Lua Console and reads the current timeline.
5. Enter a concrete goal such as “Make a copy and remove the clip named Camera test.wav.”
6. Select **Codex** or **Claude** in the Planner picker, then choose **Plan with…**, or **More → Prepare a copy-only plan** for a local-only trial.
7. Review the plan and the individual audio/video items selected for removal, then
   **Run reviewed plan**. An audio and a video item are separate entries.
8. Watch and listen to the working copy in Resolve before accepting the result.

The native permission belongs to the specific Bellith build; macOS may require
re-enabling access after an ad-hoc development rebuild. Bellith does not change TCC settings.

## Planner

The Codex CLI supplies schema-constrained JSON using
[`codex exec --output-schema`](https://learn.chatgpt.com/docs/non-interactive-mode).
Bellith uses the existing CLI login and requires no API key of its own. Planning sends
the goal and timeline metadata (including project/clip names and frame positions) to
Codex; no media file or screenshot is attached. The UI states this before the planning action.

The planner process ignores user configuration and execution rules, disables shell tools,
apps, hooks, web search, and multi-agent features, uses a read-only sandbox, and runs in a
fresh session subdirectory. Its proposed clip IDs are validated against the inspection.
Bellith owns execution; the planner never submits Resolve commands.

Claude is also available through the installed `claude` CLI and its existing login.
It uses `--print --json-schema` and reads the `structured_output` response. Built-in
tools, MCP servers, hooks, slash commands, Chrome integration, and session persistence
are disabled for this planning call. Both providers use the same plan validation and
reviewed execution. Bellith checks `~/.local/bin`, `/opt/homebrew/bin`, and
`/usr/local/bin` for the selected CLI and records the provider in session activity.
Claude CLI flags were checked against the locally installed CLI. A live synthetic
planning attempt returned “OAuth session expired and could not be refreshed” despite
`claude auth status` reporting a login. Bellith displays that response; renew the Claude
CLI login before retrying. A successful live Claude plan and rendered provider picker
remain unqualified.


## Session and recovery

Sessions and Console responses are stored under
`~/Library/Application Support/Bellith/GoalSessions/<session UUID>/`.
The latest session is restored from `current.json`. Intent and checkpoints are written
atomically before sending a mutation. An interrupted mutation becomes **Needs attention**;
it never resumes automatically. Inspect the recorded working timeline to reconcile it.
A timeout may mean an operation already ran: do not create another copy or retry a removal
blindly. Unexpected state or a changed original requires a new review/session.

“Pause” stops at a verified operation boundary. A command already submitted to Resolve
cannot be recalled. Closing the session window requests the same pause.

## Validation

- `make generate` and `make build` validate app wiring and compilation.
- `bash scripts/test-harness.sh` runs Lua adapter checks and an isolated Swift test package
  using the actual model/test sources. Requires Swift and LuaJIT.
- The Xcode test target now imports the app module. The app exports its Swift module,
  and the terminal CLI uses `BellithCLI` to prevent a case-insensitive collision with
  `Bellith`. Use a fresh derived-data directory when validating this fix.
- Thirteen focused app XCTest checks pass for goal sessions, Claude response parsing,
  and Codex/Claude terminal presentation. The full suite ran 192 tests with eleven
  failures in appearance, theme generation, and settings migration; it is not green.
- Lua checks cover wrong project/timeline, stale state, original-target rejection,
  unknown/duplicate clip IDs, successful copy/removal, and stale retry refusal.
- Swift checks cover plan validation, ambiguous IDs, session recovery, and Lua string escaping.

A disposable `Bellith Harness Test` project and generated WAV fixtures were used for live
Console testing. No existing production timeline was edited. Full Bellith-to-Resolve
execution additionally requires Bellith's own macOS Accessibility grant.

Verified in this implementation pass: app build, native goal-window rendering, six Swift
tests, eleven Lua assertions, schema-constrained Codex planning on synthetic metadata,
and live Console inspection/duplication. Live removal was not verified: the Console
could not be reliably refocused during the UI test and the copy still showed both fixture
items. The complete native Accessibility route remains pending the Bellith permission
grant and an end-to-end run. Do not treat the mock removal checks as live qualification.

A live Codex invocation through `ResolveGoalPlanner` produced a schema-constrained
removal plan for synthetic metadata and passed clip-key validation. This verifies
planning only; it sent no command to Resolve.

## CLI qualification (2026-09-30)

The native test command used a fresh build directory:

```sh
xcodebuild -project Bellith.xcodeproj -scheme Bellith -configuration Debug \
  -derivedDataPath /tmp/bellith-qualification \
  -only-testing:BellithTests/ResolveGoalSessionTests \
  -only-testing:BellithTests/AIToolSessionDetectorTests test
```

Planning status is provider-neutral, and the terminal recognizes foreground `codex`
processes as AI sessions, including an explicitly selected model. Claude response
checks reject missing/malformed structured data and preserve actionable API errors.

To exercise the actual planner with synthetic metadata (uses the selected CLI login
and sends no project data), compile the shared app sources and smoke runner:

```sh
swiftc -module-cache-path /tmp/bellith-planner-cache \
  Bellith/Models/ResolveGoalSession.swift Bellith/Services/ResolveGoalPlanner.swift \
  scripts/tests/planner-smoke.swift -o /tmp/bellith-planner-smoke-runner
/tmp/bellith-planner-smoke-runner codex /tmp/bellith-codex-check
/tmp/bellith-planner-smoke-runner claude /tmp/bellith-claude-check
```

## Interrupted-operation reconciliation

Fresh inspection of a working copy requires the saved plan and recorded project/copy
identity. Its signature must agree with the inspected clip list and timeline fields.
Recovery checks frame rate, start frame, video/audio/subtitle track counts, and the
complete surviving clip records. The copy must either match the untouched source or
the complete reviewed removal result. Partial removals, moved surviving clips, changed
settings, blocked plans, malformed evidence, and an unexpected timeline stop recovery.
An unchanged copy with pending removals pauses; a matching completed result still needs
playback review. Empty results may shorten the timeline’s extent.

The running Bellith goal window was inspected on 2026-09-30 and still reported missing
Accessibility permission. No live Bellith-to-Resolve mutation was attempted in this pass.

## Timeline note plans

Example: “Make a copy and add a marker at frame offset 12 named Check audio with note
Listen locally.” Review every marker’s offset, title, and note before running.
Offsets are relative to timeline start, not absolute source timecodes. One-frame Blue
markers are added only to the working copy, with session ownership in `customData`.
Existing marker positions cannot be overwritten. Plans support up to 20 notes and
cannot combine notes with removals. Names/content derived from unseen media are unsupported.

Inspection now records markers in the structural signature. If an operation is
interrupted, recovery accepts only the unchanged copy or the complete reviewed note
result; partial notes or changes to existing notes require manual inspection. Markers
are annotations, not effects or audio processing. The installed vendor example
`Developer/Workflow Integrations/Scripts/HandleTimelineMarkers.js` documents the
`AddMarker` / `GetMarkers` APIs used here. Native model tests and mock Lua execution
pass; live Bellith-to-Resolve marker creation remains unverified pending permission.

Marker qualification in this pass: 15 native session tests and 18 Lua assertions pass.
The actual Codex planner returned the specified offset/title/note for a synthetic
fixture (`planner-smoke-runner codex <artifact-directory> notes`). This proves schema
planning and bounded mock execution, not live marker writes or editorial judgement.

## Console submission boundary

Bellith rechecks Resolve’s foreground PID, the Console input’s focused flag, the
application’s focused AX element, and the exact staged command immediately before
sending Return. Missing keyboard events or changed focus stop submission; the staged
command is left visible and must be cleared before retrying. Response polling uses
a monotonic 15-second deadline, including checks during AX traversal, instead of
counting polling iterations. A timeout still means a command may have run and needs
inspection before any retry. The final guard compiles; live submission remains
pending the explicit Accessibility approval requested in this session.

### Isolated native UI preview

A Debug build with `PRODUCT_BUNDLE_IDENTIFIER=com.rec.bellith.qa` opens the actual goal-session and media views using temporary synthetic data. It skips terminal startup and session restoration, does not save production window sessions, and disables host execution and companion launch. The proposal sheet loads its inbox when presented; selection previews a plan, and loading is a separate action. Native QA verified first-open listing, invalid-plan rejection, older-proposal selection, and loading into review. This does not qualify live Resolve or Logic editing.

### Planner cancellation and input lifecycle

The planner now reads its prompt from a private per-request file rather than a synchronous pipe write. A CLI that never reads stdin cannot block Bellith’s main thread waiting for the prompt. The 120-second timeout uses a monotonic clock. Both task cancellation and the native Pause/close cancellation path reject late output, keep the process tracked through cleanup, and wait for its exit. An unresponsive planner receives a graceful termination request followed by a bounded forced stop of that owned process. If exit cannot be confirmed, Bellith retains the process handle and rejects another planner until the process is no longer active. No host edits are sent by this path.

Local fake-CLI tests verify normal file input, a large prompt with a CLI that ignores stdin and SIGTERM, timeout cleanup, task cancellation, concurrent-request rejection, explicit cancellation, and reuse after exit. On 2026-09-30 a real Codex invocation through the updated runner returned a schema-constrained plan for a synthetic timeline. This verifies the input path and planning only; it does not qualify live Resolve execution or Claude authentication. Prompt/schema/log/result artifacts remain in the private session planner directory for review.

Claude was rechecked through the updated runner on 2026-09-30: it exited with “OAuth session expired and could not be refreshed.” No credentials were changed and no host edits were sent. Runtime Claude planning remains blocked on renewing that existing CLI login.
# CLI login recovery

Direct planning uses a 256,000-byte prompt budget rather than a fixed timeline-item cap. The budget includes the goal, complete snapshot, and planner instructions. A compact 500-item fixture passes through the real process runner; oversized input is rejected before CLI launch with instructions to use the session companion and paged saved-evidence tools. The budget is an input-size bound, not a guarantee of model quality or support for additional edit operations. Timeout and cancellation checks still cover file-backed input larger than a pipe buffer.

Failed planner runs recognize common expired-login/authentication diagnostics and direct you to sign in again using the selected CLI in a terminal, then retry in Bellith. Bellith never refreshes or changes credentials itself. Other failures direct you to local planner/response files. Raw CLI diagnostics are not copied into the planner's visible error or checkpoint event. Detection reads a bounded prefix of local diagnostic files and does not claim to validate login in advance. Fixture tests cover both providers' authentication failures and Claude error envelopes; live Claude recovery still requires user re-login.
