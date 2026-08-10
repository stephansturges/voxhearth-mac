# Security policy

## Supported versions

Published v0.1.x releases receive security fixes. A version is published only
when its tag and signed GitHub Release both exist. Source on `main`, older
release assets, locally modified builds, and upstream TypeWhisper builds are
not supported VoxHearth releases.

| Version | Supported |
| --- | --- |
| Tagged v0.1.x release | Yes |
| `main` or other unreleased source | No |
| Older or untagged builds | No |

## Report privately

Use GitHub's **Security → Report a vulnerability** form in the VoxHearth
repository. If private vulnerability reporting is unavailable, open a public
issue containing only a request for a private contact channel—do not include
technical details there.

Never attach real private audio or transcripts, clipboard contents, account
data from another app, Apple signing material, API keys, certificates, private
keys, passwords, access tokens, or personal information. Use synthetic test
content and redact paths, usernames, bundle data, and system logs.

A useful report includes:

- affected release version and SHA-256;
- macOS and Mac architecture;
- concise impact and expected/observed behavior;
- minimal synthetic reproduction steps;
- whether microphone, Accessibility, clipboard fallback, or launch at login was
  enabled; and
- non-sensitive logs or a small proof of concept, if needed.

Please allow maintainers time to reproduce, prepare a fix, and publish a signed
release before public disclosure. GitHub's private advisory can be used for
coordination and credit. VoxHearth currently has no paid bug bounty.

## In scope

- unexpected runtime network traffic or data exfiltration;
- audio/transcript persistence or content-bearing logs;
- clipboard restoration/data-loss failures;
- global-hotkey capture beyond the registered shortcut;
- unsafe Accessibility/text insertion behavior;
- model manifest, path traversal, or bundle-integrity bypasses;
- signature, notarization, workflow, secret-handling, dependency, provenance,
  or release-asset substitution weaknesses; and
- permissions or settings behavior that contradicts the privacy statement.

Model transcription mistakes alone are not security vulnerabilities, but a
crafted input that causes memory corruption, code execution, or unintended data
disclosure is in scope.

## Release trust

Official assets are attached to tagged GitHub Releases. A release includes a
Developer ID-signed and Apple-notarized DMG, checksums, SBOM, provenance, source,
and GitHub artifact attestation. Follow
[Documentation/VERIFY_RELEASE.md](Documentation/VERIFY_RELEASE.md) before
installing. Do not bypass Gatekeeper when verification fails.

The installed application intentionally has no updater. Security releases must
be downloaded and installed manually after independent verification.
