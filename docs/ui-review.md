# UI cleanup review — 2026-10-03

Bellith remains a dense terminal and creative-workspace app. This pass preserves the existing theme, window structure, command map, and review-before-apply creative workflows.

## Changes

| Surface | Finding and cleanup |
| --- | --- |
| Workspace rail | A long workspace list could cover the fixed footer. Cards now live in an overlay-scroller list above the footer; selecting a workspace reveals its card. Workspace, add, and appearance tiles expose keyboard activation and accessibility press actions. |
| Title bar | Long workspace/multiplexer titles could crowd Studio. Title width now respects the available space; the pane chip collapses when it cannot fit, and the full title is available as a tooltip. |
| Status bar | Trailing shortcut hints could crowd leading mode/multiplexer pills. Their width now respects the space remaining after those pills. |
| Find | Clearing a query left stale match state and colors. Clearing now resets results and informs the search handler. Match navigation disables without results; narrow panels hide the count before crowding the input. Buttons and input have accessibility labels. |
| Motion | Shared animation durations now resolve to zero with Reduce Motion, covering existing chrome, sidebar, tab, palette, search, and overlay consumers. Explicit quick-terminal and dock durations also honor it. Preference toggles and broadcast pulses respect it. |
| Settings controls | Toggles have descriptive labels, values, and accessibility actions in Terminal, Sidebar, SSH, Features, and Quick Terminal. Opacity exposes bounded increment/decrement actions. Reset, step, font, link, and shortcut controls expose accessible activation; Reset and shortcut recording can start from the keyboard. |
| Theme refresh | Shared settings labels, values, and segments are refreshed recursively. Terminal's large preview label and Keybindings' count previously retained old colors after appearance changes. |
| Terminal preview | Family and metadata now have full-width rows rather than competing with the heading and preview command. |
| Smart panels | Shared headers truncate cleanly, and narrow/short panel dimensions cannot produce negative header or scroll frames. |
| Menus | Rebuilding the menu after settings changes reused an already-parented Recent Media submenu and raised an AppKit exception. It now gets a fresh instance, matching the Workspaces menu. |

## Review coverage

Source review covered the terminal shell and chrome, legacy title/tab/sidebar/status components, panes and splits, search and command overlays, badges and shortcut hints, GitHub popover and failure suggestions, settings registry and all eight panes, the six smart-panel registrations and their shared base, Studio navigation, media library, Resolve harness, Logic transport, and creative review sheets.

Studio already uses native sidebar selection, responsive workspace cards, scrolling content, and explicit review actions. Keep those patterns. Keep native file pickers and the existing connection/recovery states; UI cleanup should not widen host-operation permissions.

The running app was visually inspected in Studio and Appearance, Terminal, and SSH settings. This exposed the stale light-mode Terminal colors and cramped preview metadata. That running app was subsequently replaced during the session. These observations are not a visual certification of every screen in the final build.

## Validation and remaining limitations

- Debug build passed.
- Focused tests cover title collisions, overflow/selected-card visibility, accessible control actions, bounded opacity, narrow search layout, palette filtering, theme derivation, status-bar behavior, and Studio state.
- The full test suite exposed the menu-rebuild exception above; after fixing it, the rerun completed 272 tests with eight failed assertions across six tests in `BellithSettingsTests` and `TerminalConfigTests`.
- Those remaining failures concern default/resolved accent expectations, the built-in-settings migration fixture, generated-theme file naming, and rebrand configuration expectations. They are recorded separately from the passing UI regression tests; the full suite is not green.
- `make lint` could not run SwiftLint because it is not installed.
- Final interactive checks still needed: light/dark appearance changes in every settings pane, keyboard focus visibility/VoiceOver across custom controls, many workspaces at minimum window size, legacy tab overflow/dragging, GitHub loading/error states with live data, and creative review sheets with long real project content. No live Resolve/Logic mutation qualification is claimed.
