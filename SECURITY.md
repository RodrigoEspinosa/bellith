# Security Policy

## Supported versions

Security fixes are issued against the latest released version of Bellith. Older versions do not receive backports.

| Version | Supported |
| ------- | --------- |
| Latest release | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, use GitHub's [private vulnerability reporting](https://github.com/RodrigoEspinosa/bellith/security/advisories/new) for this repository. If that isn't available to you, email the maintainer at the address listed on their [GitHub profile](https://github.com/RodrigoEspinosa).

When reporting, please include:

- A description of the vulnerability and its impact
- Steps to reproduce (a proof-of-concept is ideal)
- The Bellith version and macOS version you tested on
- Any suggested mitigations

You should expect an acknowledgement within **72 hours** and a more detailed response within **7 days**, including an assessment and a rough timeline for a fix.

## Scope

In scope:

- The Bellith macOS application itself
- The release pipeline and signed artifacts (DMG, Homebrew cask)
- Bundled configuration handling (preferences, profiles, session state)
- Process sandboxing and entitlements

Out of scope:

- Vulnerabilities in [GhosttyKit](https://ghostty.org) or upstream Ghostty — please report those to the Ghostty project directly
- Vulnerabilities in third-party shells, SSH clients, or tools launched inside a Bellith terminal session
- Attacks that require an attacker to already have code execution as the user on the victim's Mac

## Disclosure

Once a fix is ready, we will:

1. Publish a patched release (signed + notarized)
2. Credit the reporter in the release notes, unless they prefer to remain anonymous
3. Open a [GitHub Security Advisory](https://github.com/RodrigoEspinosa/bellith/security/advisories) with details and any CVE assigned

Thanks for helping keep Bellith and its users safe.
