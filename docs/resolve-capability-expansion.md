# Resolve capability expansion investigation

Checked 2026-10-02 against the vendor documentation installed at `/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/`.

This investigation does not enable or qualify any new operation in Bellith.

## Trimming and arrangement

The installed `DaVinciResolveScript.pyi` documents `TimelineItem.GetSourceStartFrame`, `GetSourceEndFrame`, source-time accessors, timeline start/end/duration, and available left/right extension. The inspected TimelineItem API does not provide a direct start/end range setter.

`README.md` documents `MediaPool.AppendToTimeline` with a media-pool item, source start/end, media type, track index and record frame. This is an insertion API; treating it as an in-place trim would be an inference requiring host qualification. Deleting and reinserting an item may affect attributes that the current snapshot does not capture, including linked audio, transitions, effects, grades, retiming and take selection.

Source start/end frames and media-pool item identity are exposed as optional typed inspection fields, preserving a valid zero origin and leaving missing/invalid ranges or source identity unknown. Before supporting trim/rearrangement, establish which item attributes can be transferred and verified. Validate frame conventions and linked audio on disposable host fixtures. Do not implement trimming as whole-clip deletion followed by insertion while assuming equivalence.

## Independently documented operations

The installed stub documents `TimelineItem.GetClipEnabled()` and `SetClipEnabled(enabled)`, plus timeline `GetIsTrackEnabled` and `SetTrackEnable`. These are useful candidates for reversible comparison workflows, separate from trimming. Documentation is evidence of API availability, not proof that Bellith can call them successfully in the installed host.

A clip-enable implementation requires:

- Optional enabled-state coverage in clip inspection, with unknown distinct from true or false.
- Source and working-copy identity checks that include enabled state, rather than relying only on clip layout.
- A typed request identifying an inspected clip and explicit desired boolean; no toggle semantics.
- Native review showing the target and before/after state on a separate working copy.
- Post-action observation proving the requested state changed and unrelated clips, layout, markers and original source remain intact.
- Checkpoint recovery that recognizes already-applied state without silently retrying a host action.

Track enable needs analogous track identity/state coverage. Neither should be advertised in MCP supported operations before implementation and live qualification.

## Evidence pointers

Installed vendor source: `DaVinciResolveScript.pyi`, TimelineItem methods near lines 2311–2341 and 2476–2481; Timeline track enable methods near lines 2170–2175. `README.md` append descriptor near lines 532–535.

Bellith inspects clip name/kind/track/timeline extent in `Bellith/Resources/ResolveHarness/resolve_bridge.lua` and models those fields in `Bellith/Models/ResolveGoalSession.swift`. Enabled state is optional inspection evidence and included in checkpoint identity; missing or unsupported host responses remain unknown. Fixture checks cover false versus unavailable state, signature changes, and rejection of unexpected working-copy enabled-state changes. Optional typed source ranges are exposed in saved evidence and shown in clip review. Live capture of these attributes remains unverified; this does not enable trim execution.
