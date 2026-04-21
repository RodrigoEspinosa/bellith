# Security posture

This document records Bellith's stance on the App Sandbox, Hardened Runtime, and the privacy manifest, so future maintainers can re-evaluate each decision instead of re-deriving it.

## App Sandbox: disabled

`com.apple.security.app-sandbox = false` in `Bellith/Bellith.entitlements`.

A terminal emulator's core job is to `fork`/`exec` arbitrary user processes (login shell, `ssh`, `vim`, `node`, whatever the user types). The App Sandbox forbids spawning processes outside a narrow allowlist and denies the `PTY` master/child setup that GhosttyKit relies on. There is no sandbox profile that preserves this behaviour — every shipping macOS terminal (Terminal.app, iTerm2, Warp, Alacritty, Ghostty itself) runs outside the sandbox for the same reason.

Distribution is still safe because the app is signed with Developer ID, notarized, runs under Hardened Runtime, and does not ship with the Mac App Store entitlement — Gatekeeper still verifies signature + notarization ticket on first launch.

## Hardened Runtime: enabled

`ENABLE_HARDENED_RUNTIME = YES` in `project.yml` for both the `Bellith` app target and the `bellith-cli` helper. Notarization requires this, and it protects against library-injection / code-tampering attacks regardless of the sandbox status.

The minimal entitlements needed to keep the app functional are declared in `Bellith/Bellith.entitlements`:

| Entitlement | Why Bellith needs it |
|---|---|
| `com.apple.security.cs.allow-jit` | Child shells (`node`, `python`, language runtimes with JIT) write executable pages. Hardened runtime blocks this by default. |
| `com.apple.security.cs.allow-unsigned-executable-memory` | JIT children write executable pages that are not code-signed. |
| `com.apple.security.cs.disable-library-validation` | GhosttyKit is a third-party `XCFramework` with its own signing identity; without this, `dlopen` of the framework is denied under Hardened Runtime. |
| `com.apple.security.cs.allow-dyld-environment-variables` | User shells and build tools rely on `DYLD_LIBRARY_PATH`, `DYLD_FRAMEWORK_PATH`, etc. for custom toolchains. |

These are the same entitlements iTerm2 ships with, minus the App-Group one (we do not use app groups).

We intentionally do **not** grant:

- `com.apple.security.cs.debugger` — no need to attach to other processes outside our child chain.
- `com.apple.security.get-task-allow` — disabled in Release; this keeps `lldb` from attaching to shipped builds.

## Privacy manifest

`Bellith/PrivacyInfo.xcprivacy` is bundled into `Contents/Resources/`. Apple requires one for notarization of any new binary that touches a "required reason" API.

Declared usage:

- `NSPrivacyAccessedAPICategoryUserDefaults` with reasons `CA92.1` (own preferences) and `1C8F.1` (system-global `NSUserDefaults` domain, read for locale).

`NSPrivacyTracking = false`, `NSPrivacyCollectedDataTypes = []`, `NSPrivacyTrackingDomains = []`. Bellith does not collect, transmit, or aggregate user data.

If the app starts calling further required-reason APIs (file timestamps, disk space, system boot time, active keyboard), extend the manifest before the next release.

## Notarization dry-run

```bash
make build
codesign -dvvv "$(xcodebuild -project Bellith.xcodeproj -scheme Bellith -showBuildSettings | awk '/BUILT_PRODUCTS_DIR/{print $3}')/Bellith.app"
```

Expect to see `flags=0x10000(runtime)` and the full entitlement list above. CI's notarization step (see #50) is the authoritative check — run `notarytool submit --wait` on the packaged DMG.
