# Creative workspace preview

Open **File → Creative Workspace** (⇧⌘K). The development build also accepts
`--creative-workspace` to bring the preview forward at launch.

The proposed direction is a local project companion for music and video production.
The existing Bellith palette and compact framing surround a media library and preview.
The terminal remains available through **Open terminal**.

## Try it

1. Explore the clearly labeled sample project. Its entries illustrate the layout;
   they are not playable media.
2. Choose **Open folder** (⌘O) and select a folder containing audio, video, or images.
   Bellith scans recursively, skipping hidden files, symlinks, and app/document packages.
3. Filter by media type or search names and relative paths. Select an asset to preview it.
   Playback uses macOS AVKit; unsupported formats can be opened in their default app.
4. Choose **Prepare delivery** (⇧⌘E), review the complete project file list, and choose
   a destination. Bellith creates a unique folder containing `Media/` and `manifest.json`.
   Originals are copied without conversion, with relative folders preserved.

This preview holds one project in memory. Project history, saved notes, transcoding,
Direct DAW execution is handled separately in Resolve Goal Sessions; the project
companion below prepares an interactive CLI session. Reopen the folder after
relaunching or after changing its contents externally. Library filters do not change
which files are included in a delivery.

## Design decisions

- Library + detail window: project navigation, searchable media, preview, delivery.
- Native selection, text editing, file choosers, playback controls, and window behavior.
- Existing copper colors and compact typography maintain continuity with Bellith.
- Visible file operations with a review step; no processing or automatic playback on import.
- Keyboard commands and accessibility labels; no decorative animation.

## Project AI companion

After opening a media folder, choose **AI companion…** in the sidebar or
**File → Project AI Companion…** (⇧⌘J). Review a goal and select Codex or Claude.
The prompt includes the goal and selected media’s relative path. Choose **Start
companion** to create a new CLI terminal in the project folder. The command is passed
to GhosttyKit during surface creation, with no text injection into an existing shell.
**Copy launch command** remains available for manual use. The CLI uses its existing login/configured
integrations and starts in Codex read-only or Claude plan mode. It may read project
files when you run it. Renew an expired CLI login in the terminal as needed.

This interactive companion is distinct from Resolve Goal Sessions’ bounded planner
and reviewed executor. Its starting prompt requires tool evidence, an initial plan,
working copies, and review before changes; that prompt alone cannot prove host control
or enforce all behavior of user-configured tools. No Logic or Resolve capability is
claimed merely because a CLI started. Three launch tests execute a fake CLI through
the shell to check arguments with quotes, dollar substitutions, backticks, and newlines,
and reject control characters in folder paths. Native rendering and real Codex/Claude interactive launch remain to be checked.

## Local creative-app checks

The companion sheet checks DaVinci Resolve and Logic Pro installation/version,
running state, Bellith’s Accessibility permission, and observed standard windows or
blocking dialogs/sheets. Use **Check apps** to refresh after changing app state.
Window inspection runs off the main thread with bounded AX messaging timeouts and
without recursive track enumeration. It does not activate apps, change audio devices,
dismiss dialogs, or send window metadata to either CLI. An observed window is not
proof of project identity, timeline/track access, a MIDI binding, or editing capability.

Logic Pro was observed running through computer use on 2026-09-30 with an unavailable
audio-interface alert. The alert was left unchanged. The Bellith app check builds,
but its rendered states and permitted window-inspection route remain unverified.

## Direct companion startup

The reviewed launch creates a fresh terminal with an explicit `/bin/sh -c` command,
project working directory, and visible output after process exit. It bypasses the
normal tmux/zellij bootstrap and does not store a startup command for session restore;
reopening Bellith will not silently restart an agent. Failed surface creation keeps
the review sheet open and offers the manual command. Login prompts and CLI errors
remain in the new terminal. This follows the native Ghostty command model documented
in [Ghostty’s command reference](https://ghostty.org/docs/config/reference#command).

Seven focused XCTest checks pass, including a real Ghostty surface launching a
fake CLI with a quoted folder name and multiline prompt data. The fixture verifies
working directory and exact argv from the child process, without model calls or
creative-app writes. This proves the bundled GhosttyKit startup path, not CLI login,
remote inference, native sheet rendering, or host-editing capability.

## Bellith evidence tools for CLI companions

Companion launches now attach the bundled `bellith mcp` server through per-process
Codex `-c mcp_servers.bellith...` or Claude `--mcp-config` arguments. Existing global
CLI settings are not rewritten. The review sheet discloses that recorded Resolve goals,
plans, clip/marker metadata and checkpoints can be read by the chosen AI provider.

The `resolve_saved_session` tool reads the latest saved Goal Session and returns
versioned JSON with `liveInspection: false`, its save timestamp, and a requirement for
fresh inspection before execution. It never sends Resolve commands, reads audio samples,
or grants permissions. The saved session can belong to a different project; compare
project identity before using its contents. No-saved-session is an ordinary result;
corrupt state returns a tool error without reproducing its contents.

The CLI also supports `bellith creative status` for the same evidence without starting
the app. `--session-file <path>` selects an explicit checkpoint for diagnostics/tests.
The stdio server implements the 2025 MCP handshake and read-only tools lifecycle,
counter-offering `2025-11-25` for unsupported versions rather than claiming support for
the newer stateless protocol. See the [MCP protocol version reference](https://ruby.sdk.modelcontextprotocol.io/protocol-versions/).

Qualification: the built CLI passes disposable-file protocol checks; the real Codex
CLI discovered/called the server and returned a random synthetic saved goal exactly,
recognizing it as stale evidence with no edit capability. Claude launch settings
compile but a live Claude tool call remains unverified because its login is expired.
Native companion-sheet rendering and live host operations remain pending.

```sh
python3 scripts/tests/creative-evidence-tests.py /path/to/built/bellith
# Makes a live Codex request using only a disposable synthetic checkpoint:
python3 scripts/tests/evidence-codex-smoke.py /path/to/built/bellith /path/to/codex
```

## CLI proposals → native review

`resolve_propose_plan` accepts `sessionID`, the exact saved `goal`, `sourceSignature`,
and a typed `plan` using the same schema as the bounded planner. Only a draft/review
session without a working copy can receive a proposal. Unsupported operations,
blocked plans, unknown clips, stale IDs/signatures, and changed goals are rejected.
The CLI checks the checkpoint again before writing an atomic proposal under the
session’s `proposals/` directory. It returns `executed: false` and a native-review step.

In Resolve Goal Sessions choose **More → Review CLI proposals…**. Bellith validates
the proposal again against its in-memory session, loads it into the existing plan review,
and records its ID in activity. It does not create a working copy or send a host command.
A stale proposal leaves the existing plan intact. **Run reviewed plan** is still a
separate explicit action with fresh host-state checks. Proposal submission writes local
review data; it is not a read-only tool and does not change the creative project.

Proposal qualification: 21 focused native tests pass, including exact session/goal/
source validation and import into review without creating a working copy. The isolated
runner passes 17 shared-model/native-review checks plus 18 Lua assertions. Built-CLI
protocol checks verify an accepted proposal leaves `current.json` unchanged and reject
wrong goals, IDs, signatures and clip keys. Proposal schema restricts `blockedReason`
to the empty string: unsupported goals cannot be submitted, while pending human review
is not treated as an unsupported operation. Live proposal qualification is tracked
separately from these checks; host execution still requires permission and review.

The live Codex MCP proposal check now passes with `--propose`: a synthetic saved
session was read, one copy-only proposal was queued with matching goal/signature,
and the saved checkpoint remained in review. No host command was sent. Claude
submission, native menu rendering and live Resolve execution remain unverified.

## Choosing proposals

**More → Review CLI proposals…** opens a native selectable list with submission times
and a preview of the goal, removals, and note content. Listing or selecting a proposal
does not change the active plan. Older proposals can be selected; stale or otherwise
invalid proposals show their validation issue and cannot be loaded. The action is
labelled **Replace current plan for review** when a plan already exists.

Loading re-reads the chosen proposal and compares it with the displayed preview before
validating session identity and assigning the plan. Changed files require a refresh;
the previous plan is retained. **Run reviewed plan** remains separate. Files are bounded
in count/size and symlinks and mismatched proposal filenames are skipped. Eighteen
native session tests pass, including choosing an older proposal and rejecting a changed
preview. Native sheet rendering remains to be verified; these tests prove model behavior.

## Logic playback adapter

Open **File → Logic Playback…** (⇧⌘L). Choose **Inspect Logic**, review the observed project and transport state, choose Start or Stop, then explicitly apply the action. The adapter uses Logic’s named Accessibility controls, with fresh project/process and transport checks before execution. It refuses project switches, recording, ambiguous project windows, missing controls, and unexpected transport changes. A stopped Stop request leaves the playhead untouched. No global shortcut or recording command is sent. Results require an observed Play state acknowledgement; a timeout invalidates the observation and requires inspection.

This requires Bellith’s own macOS Accessibility permission, one project Tracks window, and English control labels. Plug-in, track, region, MIDI, automation, and mix control are still outside this adapter. The per-launch MCP bridge now exposes `logic_saved_transport` and `logic_propose_transport` to Codex/Claude. Saved observations are local evidence, not live state. A proposal queues only play or stop against the exact observation ID; native review and explicit application remain separate. Project paths and transport observations are saved locally; when the companion requests this MCP evidence, it may send the tool result to the selected AI provider, as disclosed in its launch sheet.

On 2026-09-30 computer use created a new empty Logic project with one audio track, input monitoring and record enable off. The named Play control changed from 0 to 1; Stop returned Play to 0 and changed its title to Go to Beginning. This confirms the host’s control behavior through computer use, not Bellith-to-Logic execution. The project was left stopped. Bellith execution remains unverified pending its Accessibility permission. Focused tests cover changed project/process/transport, recording conflicts, dynamic Stop labels, and disabled preview operations. Native panel rendering remains unverified because the separate QA app’s window automation timed out.

### Logic CLI proposal qualification

`logic_propose_transport` requires `observationID`, `action` (`play` or `stop`), and a nonempty reason of at most 2,000 characters. No executable, arbitrary AX selector, recording action, or project path can be supplied. New inspections assign a new observation ID; recording, missing observations, and mismatched IDs reject proposals. Submission leaves the saved observation unchanged. Review rereads the proposal and rejects changes after preview. Inspecting or applying invalidates the saved observation before host work, and only acknowledged results produce a new saved observation.

Choose **Review CLI proposals…** in Logic Playback, preview and load the request, then apply it explicitly. Loading never invokes the host. The panel keeps its actions visible while longer project/proposal text scrolls. Native rendering remains pending; the separate QA process is live but window automation cannot currently select it.

On 2026-09-30 a real Codex CLI run read a random synthetic Logic observation through MCP and queued exactly one play proposal for its exact observation ID. The saved fixture stayed byte-identical. This verifies Codex-to-Bellith proposal submission, not Bellith-to-Logic playback. Claude runtime verification and live Bellith transport execution are still pending.

```sh
python3 scripts/tests/logic-evidence-tests.py /path/to/built/bellith
# Optional real Codex call; synthetic observations only:
python3 scripts/tests/logic-evidence-tests.py /path/to/built/bellith /path/to/codex
```

### Interrupted Logic playback requests

Before invoking the host, Bellith atomically saves the requested action, expected project/transport observation, optional reviewed proposal ID, and a pending receipt. It writes an acknowledged receipt only when the returned project/process and playback state match the request and recording is off. Failures remain unverified; receipt-write failure before invocation blocks the host call. Individual receipts live under `LogicTransport/attempts`, with `last-attempt.json` for the most recent request.

On relaunch, an unfinished receipt is shown as needing inspection. There is no automatic retry or restoration of a live control target. The companion’s saved Logic evidence includes the last receipt, an interrupted/unverified flag, and `automaticRetryAllowed: false`. A fresh inspection reports the current host state without pretending to prove that a previous interrupted request caused it. Focused tests verify durable intent before invocation, acknowledgement after feedback, failed-action recovery without retry, persistence failures blocking invocation, and rejection of contradictory host results.

### Reviewing current state after an interruption

After a fresh inspection of the same project, outside recording, choose **Acknowledge inspected current state**. Bellith stores the reviewed observation and time separately from the original requested action. This clears the outstanding inspection warning, does not retry the action, and does not mark its original outcome as acknowledged. The MCP evidence distinguishes `interruptedActionRequiresReview` from `actionOutcomeVerified`; a reviewed interruption still reports an unverified original outcome.

A separate `com.rec.bellith.qa.review` Debug bundle includes synthetic valid and stale Logic proposals plus a pending receipt, with host/CLI execution disabled. It built and launched independently on 2026-09-30. Window-menu discovery succeeded, but the native automation pipe closed while switching to the Logic preview. The Logic panel, its proposal sheet, and the final companion form still lack completed rendered verification.

### Companion-to-review navigation

Proposal receipts include a `reviewURL` and `reviewCommand`, such as `bellith review logic <proposal-id>` or `bellith review resolve <proposal-id>`. The URL opens the appropriate native panel and selects that exact proposal for preview. It cannot encode a command, file path, approval, or execution action. Missing, stale, changed, or invalid proposals remain blocked by native validation. Selecting or loading is separate from applying/running. Repeated requests for the same ID reopen review; they never replay an action.

The CLI targets production bundle ID `com.rec.bellith`, and both Debug QA identities ignore external Bellith URL requests. Cold-start review links wait for app setup; they do not create a terminal or send input. `--print-url` prints the navigation URL without launching an app for inspection/testing. Native link routing and sheet rendering still need live UI verification; parser/model/protocol tests do not prove the rendered handoff.

### Read-only Logic track context

An explicit Logic inspection now attempts bounded discovery of exposed track headers. Saved evidence can include each header’s number/name and optional selection, mute, and solo state. Unknown fields stay absent; header discovery failure does not fabricate an empty project or prevent transport inspection. This is partial Accessibility context, not a complete track, region, plug-in, routing, or audio inventory. Only the observed English header format is recognized.

Track discovery is excluded from the final transport execution checks. It adds no track writes and no audio processing. The companion launch sheet discloses that requesting saved Logic evidence may send these names/states to its AI provider. Snapshot compatibility, header identity parsing, and MCP serialization are tested; Bellith’s live header capture and native rendering remain unverified pending Accessibility and functioning UI automation.

### Recent media projects

The workspace sidebar and **File → Open Recent Media Project** remember up to eight successfully opened media folders locally. Picking an entry explicitly rescans that folder; history loading never opens or scans folders, launches a CLI, or controls a creative app. Reopening a missing folder shows an error and preserves the current project. **Clear Recent List** removes navigation history only and leaves media/project files untouched. Regular files and remote HTTP URLs are not project-folder targets. The recent section scrolls while companion/terminal controls remain available.

The QA app’s window remains unverified: the 2026-09-30 crash report identifies `SkyComputerUseService` failing in `Array.remove(at:)` while reading its Accessibility tree. This confirms a helper crash, without identifying which UI element triggered it. No Bellith crash was established by that report, and the QA process was not restarted in this pass. Native recent-project rendering still needs live verification.

### Launching a companion from Logic

Requesting the companion refreshes Logic’s read-only inspection before opening the review sheet. The saved MCP observation is updated to that same context, including a different project if you switched projects. Inspection or persistence failures clear the old context and leave the review closed with an error. The refresh never presses playback controls or launches a CLI.

### Launching a companion from Resolve

After inspecting a timeline, choose **AI companion…** in Goal Sessions, or **File → Project AI Companion…** (⇧⌘J) while that window is active. Bellith saves the current checkpoint before showing the shared provider/goal/context review. Save failure leaves the review closed. The terminal starts in the private goal-session evidence folder, which is explicitly identified as separate from the Resolve project and media. The launch includes a compact typed summary with session/goal/phase, source and working timeline identities and signatures, and clip/marker counts. Full clip lists, marker text, plans, and event history are retrieved through the saved-session MCP tool, avoiding launch arguments that grow with timeline size. The companion is instructed to match the returned session ID before planning. This is saved evidence; no host inspection or edit occurs during the handoff. Supported CLI plan submissions still require separate native review and explicit execution. Rendered handoff and live terminal launch from Resolve remain unverified.

After inspecting a saved Logic project, choose **AI companion…** in Logic Playback, or **File → Project AI Companion…** (⇧⌘J) while that panel is active. Media and Logic now use the same provider/goal/context review sheet. The Logic launch shows its exact package path, observed playback state, inspection time, and available partial track headers. Its prompt includes that observation as typed JSON data. No audio samples are attached by Bellith. Existing CLI integrations may still read project files, as disclosed in the review sheet.

The companion terminal starts inside the inspected `.logicx` package, rather than its parent directory containing other projects. A missing/unsaved package or a mismatched root is rejected with a save-and-inspect instruction before creating a terminal. Launching requires the existing explicit Start action; merely requesting/opening review neither persists an observation nor invokes a CLI or host. Shell quoting, goal encoding, default read-only/plan mode, per-launch MCP configuration, and the shared Ghostty startup path are preserved. Native rendering and live Logic-origin CLI startup remain unverified; tests cover package scoping, encoded metadata, and rejection boundaries. Claude login still needs renewal.

Resolve saved-session MCP reads also support bounded source clip, source marker, and session event pages: supply sessionID, sourceSignature, collection, offset, and limit (1–50). Follow nextOffset until null and pass checkpointToken from the first response on later requests; changed checkpoint bytes reject the request. Pages omit plans, working context, and other collections explicitly. Marker coverage distinguishes unavailable data from an observed empty list. No-argument full-checkpoint reads remain available. Protocol fixtures verify exact page assembly, stale identities/tokens, bounds, and coverage.

The real Codex CLI passed synthetic paged-MCP qualification: three actual tool calls at offsets 0, 3, and 6, checkpoint-token reuse, and all seven clip keys returned in order. Run `python3 scripts/tests/evidence-codex-smoke.py <bundled-bellith-cli> <codex-cli> --paged` to repeat it. This establishes saved-evidence consumption, not host inspection, media understanding, or edit execution. Claude paging remains unqualified until its CLI login is restored.

The native whole-clip removal review supports searching names, kinds, track numbers, and exact clip keys, plus a selected-only filter. It always shows the total selected removal count separately from the filtered item count; filtering never changes the plan. Clip keys remain visible to distinguish identically named items. Rows render lazily, and new sessions reset filters. Rendered keyboard and scrolling behavior still require live UI verification.

Current QA retry: the rebuilt synthetic bundle opened Goal Sessions and Accessibility exposed the AI companion button, source context, and disabled host controls. Clicking AI companion ended the computer-use helper pipe before an observation returned; a subsequent inventory still reported the QA app running. Screenshot-only observation also failed. This verifies initial window accessibility exposure, not the companion sheet or its layout. No new helper crash report was available; the older helper assertion report does not establish the cause of this retry. Host applications were not launched, permissions were not changed, and no CLI ran from the QA preview.

Resolve-origin companions configure their per-launch MCP server with that goal session's `session.json`, rather than global `current.json`. Switching another Bellith session therefore does not silently redirect saved evidence. Proposal submission from this scoped checkpoint writes into the same session's native-review inbox; it does not create a nested session directory. Native import and host execution checks still reject stale or mismatched proposals. Media-origin companions and Logic evidence still use their current global evidence paths. Protocol fixtures verify scoped reads/proposals while global current state points to another session, and unchanged checkpoint bytes after submission.

Logic-origin companions bind their per-launch MCP server to the reviewed observation UUID. If a later inspection replaces or clears it, saved-transport reads fail before returning replacement project data; proposals targeting a different observation are rejected even if it is globally current. Inspect and launch a fresh companion to use the new state. This binding does not prevent unrelated host changes; native playback still performs its own fresh project/state checks. Protocol tests cover matching and mismatched reads, no replacement-name disclosure, and cross-observation proposal rejection.

Combined regression qualification passed 60 native creative tests, 18 Lua bridge assertions, and both CLI protocol scripts. The Ghostty startup integration test also passed with a synthetic Logic package, quoted package/tool paths, multiline goal data, and a fake Codex executable: the process received the correct working directory, read-only flags, per-launch MCP configuration, and exact observation UUID without typed terminal input. This does not prove the visible companion sheet, authenticated interactive model session, or live host operation. The same Ghostty integration test now passes for a fake Claude executable: plan-mode flags, quoted-path MCP JSON configuration, observation binding, working directory, and goal all reached the process correctly. Authenticated Claude interaction remains unqualified until user re-login.

Host-origin MCP launches now also pass `--creative-scope resolve` or `--creative-scope logic`. Tool discovery exposes only that host's saved evidence and proposal tools; direct calls to the other host's tools are rejected before reading its files. General media companions keep both tool families. This affects Bellith's per-launch server only, not other existing CLI integrations. Protocol tests verify discovery filtering, rejected cross-host calls, and invalid scope rejection; both fake-provider Ghostty startup paths verify the scope argument reaches the process.

Track-control groundwork: a typed mute/solo request now binds observation UUID, track number/name, control, and requested boolean state. Validation rejects unavailable controls, changed identities/transport, and recording. Feedback must show the requested target value, preserved target selection/other control, and unchanged remaining exposed track observations. The named AX track-write adapter is now implemented internally, but no native apply UI or MCP track-control tool is enabled. It rechecks the project/transport and exposed headers before pressing the uniquely named target, treats already-matching values as no-ops, and waits for isolated feedback. Compilation and contract tests pass; live AX behavior and rendered native review verification remain incomplete. It does not prove isolation across unexposed tracks. A read-only startup check observed Logic 12.3 and its missing-audio-interface alert; the alert was left untouched, so live track inspection/control remains unverified.

Internal track execution now persists pending intent in `track-attempts/<uuid>.json` and `last-track-attempt.json` before invoking the host. Verified feedback writes an acknowledged receipt; failures remain unverified and do not restore reviewable context. Relaunch loads the receipt without resuming. Native and MCP read-only evidence report unverified track attempts; no automatic retry exists. Injected-operation tests verify durable intent before invocation, contradictory feedback, acknowledged feedback, relaunch without retry, and persistence failure blocking invocation. Native apply remains disabled pending live qualification. MCP submission only queues native review data. The track review menu and sheet are now implemented: they show the project path, exact track number/name, current control value, requested value, and operation boundaries. Reviewing is non-executing, and repeated identical review requests can reopen after cancellation. The production model has no qualified track execution flag enabled; tests use injected host operations to exercise the reviewed execution path.

Track interruptions now support **Acknowledge inspected track state** after a new same-project, same-track inspection outside recording. The observed requested control must be known. The receipt stores the reviewed snapshot/time separately from execution feedback, clears the outstanding review warning, and keeps the original outcome unverified. No host action or retry occurs. Native contract tests and CLI fixtures verify the distinction between reviewed interruption and acknowledged execution; rendered recovery remains unverified.

Track proposals now have a typed private inbox and native **Track proposals…** sheet. Each proposal binds the observation, exact track number/name, mute/solo value, and a bounded reason. Loading re-reads and compares the full proposal, validates the current observation, and prepares a separate review without host invocation. Changed-after-preview or stale/unknown requests are rejected. Apply remains qualification-gated, and the logic_propose_track_control MCP tool now queues these typed requests for native Track proposals review; receipts explicitly report executed false and hostExecutionAvailable false. Unit tests cover preserved saved bytes, non-executing load, changed proposal rejection, invalid reasons, and missing observations; rendered inbox review remains unverified.

Real Codex qualification passed for a synthetic solo-on proposal using a host-scoped, observation-bound MCP server. The verifier checked exactly one completed proposal tool call, the saved request's exact UUID/track number/name/control/value, unchanged observation bytes, and a non-executing receipt. Repeat with `python3 scripts/tests/logic-evidence-tests.py <bundled-cli> <codex-cli> --track`. This verifies CLI-to-inbox submission only; it does not verify native rendering, sound, or live Logic execution. Claude track submission remains unqualified until CLI re-login.

Track proposal receipts now include an exact `bellith://review?tool=logic-track&proposal=<uuid>` URL and `bellith review logic-track <uuid>` command. The same strict navigation-only parser rejects extra fields, paths, fragments, and executable content. Production routing opens the track inbox for the requested UUID; unavailable requests show an error rather than selecting a replacement. Repeated links request a fresh preview. Navigation never loads or executes a proposal. Parser/native compilation and CLI `--print-url` round trips pass; rendered routing remains unverified.

Track-control preflight now compares the complete exposed header observation, including other tracks, selection, and coverage, against the reviewed snapshot before any host press. Previously, unrelated track changes could be discovered only during acknowledgement after the target action. Tests now reject sibling mute changes, selection changes, and disappearing exposed headers during preflight. This remains a partial exposed-header guard, not a full Logic project signature.

Loaded track proposals retain their complete immutable proposal value through native review, including UUID, submission time, request, and reason. The reason and UUID are shown again in final review, and matching execution receipts preserve the proposal for attribution. Different manual requests clear that attribution; manual-only receipts keep it absent. Older receipts without the optional proposal field remain readable. Injected-operation tests verify matching attribution and manual-request separation; this does not establish live host execution.

Live Logic inspection retry on 2026-10-01 reached the project chooser without the earlier audio-interface alert. An empty two-audio-track fixture was created with monitoring and record-enable off and no media added. Its Tracks window exposed `Track 1 “Audio 1”` and `Track 2 “Audio 2”`, both selected, each with named Mute and Solo checkboxes reporting zero; Play and Record also reported zero. This supports the observed English header/control mapping, but it was computer-use inspection, not Bellith adapter capture. Element clicks on the first track's Mute produced no observed state change. A screenshot-based coordinate retry failed with `noWindowsAvailable`; inventory still reported Logic running. No successful mute/solo write or isolated feedback was established, and production track Apply remains disabled. The fixture was not explicitly saved, no Accessibility permission was granted, and existing projects were not edited.

Logic's off-main-thread inspection and control workers now inherit caller cancellation explicitly; detached tasks previously continued independently. Workers check cancellation on entry, before playback presses, before track presses, and during feedback polling. Cancellation cannot undo a press already submitted; an interrupted attempt remains subject to the existing unverified-receipt review. All 24 focused Logic tests passed, including a worker-entry/caller-cancellation test that verifies the detached worker exits before its simulated host action. Live host cancellation remains unqualified, and SwiftLint was unavailable.

The Logic panel now exposes **Cancel operation** while busy and retains the active task until it finishes unwinding. Saved context is cleared before cancellation is checked; cancellation never restores an old observation or starts another host action. Playback/track receipt paths check cancellation before accepting returned feedback, leaving a started attempt in `needsAttention` even when an operation ignores cancellation and returns matching state. A focused injected-host test verifies late playback feedback is not acknowledged, the durable receipt requires inspection, and no reviewable snapshot/result is restored. All 25 Logic tests passed. The button and live-host cancellation still require rendered/runtime qualification.

Cancellation coverage now also verifies immediate inspection cancellation clears saved evidence without invoking the host, and late matching track feedback cannot acknowledge a cancelled attempt or restore current evidence. All 27 focused Logic tests passed. The existing QA preview was retried: Goal Session accessibility and the Window menu were readable, but choosing Logic Playback closed the native automation pipe before panel observation. This existing preview was not rebuilt for cancellation-button verification; no rendered cancellation claim follows from it.


### Unified Studio and guided testing

The main app now opens Bellith Studio in front of its restored terminal sessions. A native sidebar routes Start here, the guided demo, Resolve, Logic, and media in one window; existing File commands and exact review links select the corresponding Studio section and model. Resolve embeds without its duplicate navigation sidebar, retaining its New session and AI companion actions in Studio's workflow bar. Section switching retains the media/Resolve/Logic models; dismissed review requests are cleared so remounting a section does not reopen an old sheet. The rebrand terminal title bar includes a native Studio button, with File → Bellith Studio (⇧⌘S) available to both terminal layouts.

Start here presents current capabilities, local CLI presence without asserting authentication, an explicit read-only creative-app setup check, and a setup-free guided demo. The demo uses immutable synthetic source data and the real typed Resolve plan validator; it requires proposal preparation, a separate review, then explicit simulated application to a distinct working snapshot. Notes preserve clips; removals preserve their original positions and the gap. All demo state lives in memory; no host, AI, permission change, or project write occurs. Reset clears the result and proposal. This demonstrates the intended review experience, not live host execution or actual AI generation. See `docs/studio-quickstart.md` for the short testing route.

The regenerated project and final Studio build passed 67 selected creative tests, including the demo gates, navigation context, existing host contracts, and the fake Codex/Claude Ghostty startup integration. Both protocol scripts passed against the CLI bundled in the delivered app. SwiftLint was unavailable; diff whitespace checks passed. The runnable main app was copied to `/tmp/Bellith Studio/Bellith.app` and its signature verified. Native automation launched the preview and production bundles but closed its pipe before returning window observations. A new diagnostic report identified SkyComputerUseService's assertion in `Array.remove(at:)`, without establishing a Bellith crash. Inventory confirmed the production bundle running. Rendered Studio/sidebar/sheet/terminal-button verification and live host execution remain incomplete.

Studio home refinement based on the user’s 2026-10-01 screenshot: real workspace selection now precedes the demo, with three adaptive side-by-side workspace cards and specific action labels. A compact secondary demo row replaces the large primary banner. Setup details move into a collapsed native disclosure section with installed-provider summary; authentication is still not asserted. Key descriptions use callout text instead of small capability captions. The window remains scrollable, and the workspace cards fall back to vertical layout when needed. Build and three Studio tests passed; diff checks passed. The updated signed development app is `/tmp/Bellith Studio Refined/Bellith.app`. Its rendered revision remains unverified because the native automation helper previously crashed; the supplied screenshot verifies the preceding build only. Terminal startup behavior was not changed in this refinement.

The later startup/sizing fix removes automatic terminal restore/create from application startup. Open terminal restores deferred archives once and subsequently focuses an existing terminal. Studio-only shutdown leaves archive bytes untouched; a companion/new terminal opened before restoration is saved alongside deferred sessions. Explicitly closing restored terminals clears the primary legacy fallback too. Archive compatibility/preservation tests and existing Studio/session tests passed (15 total). Studio hosting sizingOptions is empty, so the NSWindow owns its size; embedded Resolve no longer imposes its standalone minimum height. The new signed build is `/tmp/Bellith Studio Fixed/Bellith.app`. The user’s screenshots confirm the older build opened terminals and grew on Resolve selection; the revised behavior remains visually unverified.

The Logic companion now exposes `logic_saved_action_results`, a read-only receipt-summary tool requiring the original observation UUID and enforcing the per-launch observation binding. It works after current context is cleared or replaced without returning replacement-project data. Summaries report exact attempt/proposal IDs when available, phase, verified outcome, and inspection requirement; reviewed interruptions remain unverified. Only latest retained playback/track receipts are covered, and missing receipts are not proof of no action. Bound saved-transport evidence also omits receipts belonging to other observations. The launch prompt explains matching proposal IDs before attribution. All 34 focused companion/Logic tests and both protocol scripts passed, including cleared/replaced context, mismatched IDs, pending/reviewed results, and no replacement-name disclosure. Actual model consumption and live action-result feedback remain unverified.

Real Codex saved-result qualification now passes via `python3 scripts/tests/logic-evidence-tests.py <bundled-cli> <codex> --results`. A cleared observation and synthetic reviewed-interruption receipt are used; random attempt/proposal IDs appear only in MCP evidence. The verifier requires one completed result-tool call, exact IDs, reviewed phase, unverified original outcome, no automatic retry, and inspect-before-new-action guidance, with unchanged fixture/receipt bytes. The first run used an invalid `originalObservationID` argument and was rejected without disclosure; schema/launch instructions now explicitly name `observationID`, and the corrected run passed. Artifact: `/var/folders/m_/g7z05nss3yd1pvkvp96xl7d80000gn/T/bellith-logic-evidence-1lpast1i`. Seven focused companion-launch tests passed after the instruction/schema update. This proves synthetic Codex receipt consumption, not live Logic action execution or authenticated Claude result consumption.

Resolve setup now precedes goal editing when Accessibility is missing, with a concrete Settings path and disabled Inspect/Run actions. The status describes Accessibility availability rather than verified computer control. Permission state refreshes on view appearance and app activation, without requesting/granting access. Model-level blocked inspection returns before changing phase, appending failure events, or writing session files. A regression test calls inspection twice with missing access and verifies those invariants; all 23 focused Resolve/Studio tests passed. Rendered setup and live permission transitions remain unverified.

Studio now offers explicit provider Sign in actions within Setup & connections. They construct shell-quoted `codex login` or `claude auth login` commands in the user home directory, then start a fresh local Ghostty terminal with bootstrap disabled and no project prompt/context. Nothing runs when opening Studio or expanding setup; missing CLI/terminal setup errors are shown without claiming authentication. Bellith neither reads nor stores credentials. A fake executable with spaces, an apostrophe, and command-substitution characters verified exact provider argv/cwd and no substitution side effect; all 11 focused launch/Studio tests passed. Native automation currently reports pipe startup failure even for inventory. A bounded Claude auth-status check reported loggedIn false, without printing account details or credentials. Actual sign-in UI and authenticated Claude qualification remain incomplete. The latest signed development build is `/tmp/Bellith Studio Setup/Bellith.app`.

The companion launch review now separates scope-specific shared context, existing CLI file access/integrations, and Bellith proposal approval rules into a native Before you start group. Resolve, Logic, and media disclosures reflect their respective evidence scopes, including saved action receipts for Logic and both host evidence families for general media companions. Start companion uses a prominent native button. Creative-app availability is an optional disclosure and runs only after Check apps, removing the prior automatic read on sheet appearance. Exact project/evidence paths, goals, and observed context remain visible. All 11 focused launch/Studio tests passed; diff checks passed and SwiftLint was unavailable. Rendered sheet and live media-origin companion handoff remain unverified.
