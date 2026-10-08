# Creative companion goal status

Audit date: 2026-10-02. The full creative companion goal is **not achieved**.

## What the current implementation proves

| Requirement | Current evidence | Remaining proof |
| --- | --- | --- |
| Native main app with a simple testing path | Studio contains shared Resolve, Logic, Media models and an in-memory guided demo. Focused Studio tests pass. | Rendered navigation, resizing, startup without a terminal, menus and review sheets in the current build. Native automation currently fails at helper startup. |
| Codex integration | Actual Codex MCP runs consumed synthetic saved evidence and checkpoint guidance. Protocol checks cover paging, proposals and receipt scope. | A real creative project through launch, proposal, native review, host execution and observed outcome. |
| Claude integration | Launch preparation supports Claude plan mode and MCP configuration. Fake-provider launch tests pass. A real-provider smoke script checks authentication first. | Authenticated Claude MCP consumption and a complete native workflow. Local auth preflight currently reports no login. |
| Resolve interaction | Typed plans support a separate working copy, whole-clip removal without ripple, or frame-positioned note markers. Proposal/checkpoint gates are tested. | Bellith-to-Resolve execution and source preservation in a disposable real timeline; playback review of the result. |
| Logic interaction | Saved project/transport observation, explicit play/stop requests, durable receipts, cancellation and recovery gates are tested with injected operations. | Real host feedback and recovery. Mute/solo execution is deliberately unavailable until qualified; review-only proposals exist. |
| Reversible, reviewable work | Proposals are nonexecuting; native approval is separate. Resolve uses working copies; interrupted Logic receipts cannot be replaced before recovery review. | End-to-end interrupted real-host workflow. Acknowledging observed state does not verify an earlier action. |
| Broad creative capabilities | These are not implemented by the current adapters. | Trimming/arrangement, mixing, plug-ins, automation, rendering and other requested workflows need typed operations, host evidence, native review and result verification. |

## Next milestones

1. Verify the current Studio build visually: no terminal at startup, stable window size when switching sections, complete guided demo, and exact proposal review links.
2. Qualify Resolve on a disposable timeline: inspect → copy-only proposal → native approval → distinct working timeline → structural comparison → user playback review. Then qualify removal and notes independently.
3. Qualify Logic on a disposable saved project: inspect → explicitly requested play/stop → native approval → observed feedback → interruption and recovery. Qualify mute/solo in isolation before enabling Apply.
4. Run authenticated Claude evidence qualification and both providers through the native companion flow.
5. Expand creative operations based on concrete workflows. Each operation needs an inspectable target, explicit parameters, preserved original or a defined recovery method, a native review preview, and observable result evidence. Passing current tests does not establish these missing capabilities.

## Validation entry points

- `scripts/tests/creative-evidence-tests.py <bundled-bellith-cli>`: Resolve/MCP lifecycle, scope, paging, proposal rejection and checkpoint evidence.
- `scripts/tests/logic-evidence-tests.py <bundled-bellith-cli>`: Logic proposals, receipt scope and interruption evidence.
- `scripts/tests/evidence-codex-smoke.py <bundled-bellith-cli> <codex> --checkpoint`: actual Codex synthetic checkpoint consumption, no proposal and unchanged fixture.
- `scripts/tests/evidence-claude-smoke.py <bundled-bellith-cli> <claude>`: authenticated Claude synthetic evidence consumption. Exit 2 indicates sign-in is needed; that is not a pass for authenticated integration.

These checks do not inspect or mutate real creative projects. Focused unit suites are not the full app test suite, and synthetic host operations do not prove live host compatibility.
