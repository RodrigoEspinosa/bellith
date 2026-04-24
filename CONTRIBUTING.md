# Contributing to Bellith

Thanks for your interest in contributing. This document covers the practical bits — how to build, what conventions to follow, and how to get a change merged.

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [SwiftLint](https://github.com/realm/SwiftLint) (optional but recommended) — `brew install swiftlint`

## Getting set up

```bash
git clone git@github.com:RodrigoEspinosa/bellith.git
cd bellith
make generate   # regenerate Bellith.xcodeproj from project.yml
make build      # build Debug
make run        # build and launch
make test       # run the test bundle
make lint       # SwiftLint, if installed
```

Open `Bellith.xcodeproj` in Xcode and run the **Bellith** target if you'd rather work in the IDE.

## Source of truth

[`project.yml`](./project.yml) is the source of truth for targets, files, and build settings. If you add files, change build phases, or adjust dependencies, edit `project.yml` and regenerate — **do not hand-edit the generated Xcode project**.

```bash
make generate
```

## Code layout

- `Bellith/App` — app lifecycle and `AppDelegate`
- `Bellith/Bridge` — GhosttyKit integration, terminal config, input translation
- `Bellith/Views` — windows, surfaces, tabs, sidebar, preferences, command palette
- `Bellith/Models` — settings, registries, profiles, session state
- `Bellith/Monitors` — system/process/network monitoring
- `Bellith/Utilities` — shared helpers
- `BellithTests` — unit tests

## Style

- Match the existing Swift style. SwiftLint config lives in [`.swiftlint.yml`](./.swiftlint.yml).
- Some strict rules (`line_length`, `identifier_name`, `file_length`, `type_body_length`, `trailing_comma`) are intentionally disabled.
- Opt-in rules (`modifier_order`, `closure_spacing`, `toggle_bool`) are enabled.
- Run `make lint` before opening a PR.

## Commits

We use [Conventional Commits](https://www.conventionalcommits.org/). Examples from history:

```
feat(ui): add command palette overlay
fix(preferences): persist theme selection across relaunches
build: signed DMG + Homebrew cask release pipeline
docs: clarify TERM handling
```

- Prefer a scope when it clarifies the area (`ui`, `app`, `preferences`, `shortcuts`, `build`, `docs`).
- Subjects are short, imperative, and lowercase after the prefix.
- One logical change per commit where practical.

## Tests

Add or update tests in `BellithTests` for behavior changes where it's reasonable. `make test` must pass before a PR is ready to review.

## Opening a pull request

1. Fork and branch off `master`. Use a descriptive branch name (`fix/tab-drag-glitch`, `feat/profiles`).
2. Keep PRs focused — one concern per PR makes review easier.
3. In the PR description, explain **why** the change is needed and any tradeoffs. Screenshots or screen recordings help a lot for UI changes.
4. Make sure CI is green (`make build`, `make test`, `make lint`).
5. Link related issues (`Closes #123`).

## Reporting bugs and requesting features

Use [GitHub Issues](https://github.com/RodrigoEspinosa/bellith/issues). For bugs, include:

- macOS version
- Bellith version (`Bellith > About` or the git SHA if built locally)
- Steps to reproduce
- Expected vs. actual behavior

For features, describe the use case before proposing a design — it's easier to agree on the problem than the solution.

## Security

Please do not file security issues as public GitHub issues. See [SECURITY.md](./SECURITY.md) for the responsible disclosure process.

## Code of Conduct

By participating in this project you agree to abide by the [Code of Conduct](./CODE_OF_CONDUCT.md).
