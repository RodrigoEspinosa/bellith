# Try Bellith Studio

Open the supplied **Bellith.app** development build. Studio opens on its own. Saved terminal sessions stay deferred until you choose Open terminal. You can return to it from the terminal's **Studio** button or **File → Bellith Studio** (⇧⌘S).

## Start without setup

1. Choose **Try the guided demo** on Start here.
2. Leave the opening-note example selected, or toggle the Camera test removal.
3. Choose **Show example proposal**, then **Review these changes**.
4. Choose **Apply to demo working copy** and inspect the result.
5. Choose **Start over** to try the other example.

This demo is a prepared example, not an AI response. It uses the real typed plan validator and synthetic timeline data in memory. It never connects to a CLI or creative app, requests permissions, or writes project files. It does not qualify live host control.

## Try your own project

All workflows share Studio's sidebar; switching sections retains the models and current project/session evidence.

- **DaVinci Resolve:** open your timeline in Resolve, inspect it in Bellith, set a goal, then use the planner or AI companion. Review the exact supported plan before running it on a working copy. Live Bellith-to-Resolve execution remains unverified.
- **Logic Pro:** open one saved `.logicx` project, inspect it, then launch a companion or review playback requests. Track mute/solo proposals are reviewable; track execution remains disabled pending qualification. Playback and interrupted actions require current host inspection.
- **Media library:** open a folder, preview media, and start a companion with a project goal. Delivery creates media copies and a manifest.

**Start here → Check creative apps** reads local app availability and reports missing prerequisites. It never grants Accessibility access or operates a host. CLI detection reports whether Codex/Claude is installed; it does not assert a working login. Expand **Setup & connections** and choose **Sign in** beside Codex or Claude. This opens the provider’s CLI login flow in a new local terminal; complete authentication yourself. The manual terminal setup option remains available.

Companion startup still requires a separate context/goal review and explicit Start. Proposals never apply automatically. **Cancel operation** in Logic cannot undo a host press that was already submitted; inspect the host afterward before retrying.

## Current validation

Run `make test-creative` for the focused creative app suites, Resolve Lua bridge checks, and both built MCP protocol suites. It requires Xcode, Python 3 and LuaJIT. Logs are retained in the printed artifact directory. Set `BELLITH_CREATIVE_DERIVED_DATA` to reuse a specific derived-data directory. This command does not call a model provider or control a creative host, and it is not the full app suite.

Claude evidence qualification is available through `scripts/tests/evidence-claude-smoke.py <bundled-bellith-cli> <claude-executable>`. It checks authentication without displaying account details, then uses a disposable synthetic checkpoint and only Bellith's saved-session read tool. It verifies an actual MCP call, structured evidence, unchanged checkpoint bytes, and no queued proposals. Exit code 2 means sign-in is required. The current local preflight reports no login; authenticated Claude evidence consumption remains unverified.

The unified Studio build passed 67 focused creative tests, including original preservation, explicit demo approval, navigation context, existing review links and Logic receipts, and both fake-provider Ghostty launch paths. This is not the full app test suite.

Native automation could confirm the rebuilt preview process running, but its Accessibility helper crashed in `Array.remove(at:)` before returning a window observation. Rendered Studio layout, sidebar navigation, and live host execution still need hands-on verification. SwiftLint was unavailable.

Startup and sizing update: Studio-only visits preserve saved terminal archives. Opening a companion before restoring old terminals preserves both in the archive. Open terminal restores saved windows once, then focuses an existing terminal on subsequent requests. Studio disables intrinsic hosting-view window sizing so selecting Resolve cannot impose its preferred window height; embedded Resolve uses available space. Build and 15 focused session/Studio tests passed; visible startup and section-switch behavior still need verification in the updated build.

Explicit terminal commands from Studio now work with no focused terminal: New Tab creates a terminal window, and terminal CLI links use an existing terminal or create one. Returning through the terminal Studio button retains the last Studio section instead of always returning home. The changes compiled and 19 focused session, Studio, review-link, and Ghostty launch tests passed; native menu/link routing remains unverified.
