# AGENTS.md

## Project Snapshot

- Bellith is a native macOS terminal emulator built in Swift on top of `GhosttyKit`.
- Toolchain targets are currently macOS `14.0+`, Xcode `16.0+`, Swift `5.10`.
- Main project config lives in [`project.yml`](./project.yml). The Xcode project is generated.

## Source Of Truth

- Treat [`project.yml`](./project.yml) as the source of truth for project structure and build settings.
- Regenerate [`Bellith.xcodeproj`](./Bellith.xcodeproj/project.pbxproj) with `make generate` or `xcodegen generate` after changing targets, files, build settings, or scripts.
- `GhosttyKit` is a binary dependency defined in [`Package.swift`](./Package.swift) and referenced from `Frameworks/GhosttyKit.xcframework`.

## Common Commands

- `make generate` regenerates the Xcode project from `project.yml`.
- `make build` builds the `Bellith` app in `Debug`.
- `make test` runs the unit test bundle.
- `make lint` runs SwiftLint if installed.
- `make lint-fix` applies SwiftLint autofixes if installed.
- `make run` builds and opens the app.

## Code Layout

- `Bellith/App`: app lifecycle and app delegate.
- `Bellith/Bridge`: GhosttyKit integration and terminal configuration/input translation.
- `Bellith/Views`: windowing, terminal surfaces, preferences UI, smart panels.
- `Bellith/Models`: settings, registries, profiles, session state.
- `Bellith/Monitors`: system/process/network monitoring.
- `Bellith/Utilities`: shared helpers.
- `BellithTests`: unit tests.

## Conventions

- Use Conventional Commits. The existing history follows formats like:
  - `feat(ui): add ...`
  - `fix(preferences): adjust ...`
  - `docs: add ...`
- Prefer a scope when it clarifies the area. Existing scopes include `ui`, `app`, `preferences`, and `shortcuts`.
- Keep commit subjects short, imperative, and lowercase after the prefix.
- Match the existing Swift style and run `make lint` when relevant.
- Add or update tests in `BellithTests` for behavior changes when practical.

## SwiftLint Notes

- SwiftLint uses [`.swiftlint.yml`](./.swiftlint.yml).
- Several strict style rules are intentionally disabled, including `line_length`, `identifier_name`, `file_length`, `type_body_length`, and `trailing_comma`.
- Opt-in rules such as `modifier_order`, `closure_spacing`, and `toggle_bool` are enabled.

## Practical Guidance For Future Agents

- Prefer editing app source under `Bellith/` and tests under `BellithTests/`.
- Avoid manual edits to generated Xcode project structure when a `project.yml` change is the real fix.
- If a change affects project wiring, build scripts, targets, or dependencies, regenerate the Xcode project before finishing.
