# Auto-update (Sparkle)

Bellith ships with [Sparkle 2](https://sparkle-project.org) for in-app updates. This doc covers the one-time setup needed before the first tagged release, plus how the release → appcast pipeline fits together.

## One-time setup

### 1. Generate an EdDSA key pair

Sparkle 2 requires every update to be signed with an EdDSA keypair. Sparkle's `generate_keys` tool stores the private half in the macOS Keychain and prints the public half to stdout.

```bash
# Clone or brew-install Sparkle to get the tools
brew install --cask sparkle

# Generate the keys (prompts before overwriting an existing entry)
generate_keys
```

The output ends with a line like:

```
SUPublicEDKey in Info.plist: A1B2C3D4E5F6...
Private key stored in Keychain item "https://sparkle-project.org"
```

### 2. Wire the public key into the app

Replace the `SUPublicEDKey` placeholder in `Bellith/Info.plist` with the value printed above, and commit. Shipping the wrong public key means every update will fail signature verification — double-check before tagging.

### 3. Wire the private key into CI

Export the private key and add it as a GitHub Actions secret so the appcast workflow can sign release DMGs:

```bash
# Prints the private key to stdout
generate_keys -x -
```

Copy the output and add it as `SPARKLE_ED_PRIVATE_KEY` in **Repo Settings → Secrets and variables → Actions**. This is the only secret specific to the appcast workflow; the signing/notarization secrets listed in the release workflow cover the rest.

### 4. Enable GitHub Pages

The appcast workflow publishes to the `gh-pages` branch. Enable Pages with `gh-pages` as the source (**Settings → Pages → Source: Deploy from a branch → `gh-pages` / `/`**). The feed URL in `Info.plist` (`SUFeedURL`) already points at `https://rodrigoespinosa.github.io/bellith/appcast.xml`; update that URL if the fork or username is different.

## Release → appcast flow

```
tag vX.Y.Z pushed
       │
       ▼
release.yml       ── builds signed DMG, notarizes, staples, creates GitHub Release
       │
       ▼ (release: published event)
appcast.yml       ── downloads DMG, signs with Sparkle EdDSA, appends <item> to appcast.xml,
                      pushes to gh-pages, GitHub Pages serves the feed within ~60 s
```

Existing Bellith installs poll `SUFeedURL` once per `SUScheduledCheckInterval` (24h) and also on-demand via **Bellith → Check for Updates…**. Sparkle verifies the DMG against the `SUPublicEDKey` baked into the app before unpacking, so a compromised GitHub Release alone can't push malicious code — the attacker would also need the Keychain-protected private key.

## Testing the flow locally

```bash
# Dry-run the signing step against a locally built DMG:
generate_keys -x - | sign_update --ed-key-file - path/to/Bellith-0.2.0.dmg
```

If the output line starts with `sparkle:edSignature="..." length="..."`, the key pair works. Drop that line into a local `appcast.xml`, serve the directory with `python3 -m http.server`, and point `SUFeedURL` (temporarily, in a Debug build) at `http://localhost:8000/appcast.xml` to exercise the end-to-end update flow.

## Beta / stable channels

Not enabled yet. When it's time to split channels, add a second feed URL and switch between them via `SPUUpdaterDelegate.feedURLString(for:)` in `UpdaterController.swift` based on a user preference. The delegate hook already exists; only the preferences plumbing is missing.
