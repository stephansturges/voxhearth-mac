# Threat model

This threat model applies to any signed VoxHearth 0.4 release built from this
repository. It distinguishes the installed runtime, which is designed for
offline operation, from the connected build and release system. Source on
`main` is not an official release until matching signed assets are published.

## Security and privacy goals

VoxHearth aims to:

1. keep microphone samples and transcripts on the user's Mac;
2. avoid durable VoxHearth audio and transcript history;
3. make runtime networking and silent updates absent and auditable;
4. insert text with the narrowest practical macOS mechanisms;
5. make release source, dependency, and model inputs immutable and verifiable;
6. prevent an altered or unnotarized artifact from being presented as an
   official release; and
7. avoid logging content that could reconstruct a user's dictation.

## Data flow and trust boundaries

```text
                    connected release boundary
 Git source ─┐
 FluidAudio subset ┼─ provenance checks ─ build ─ sign ─ Apple notarize ─ DMG
 HF models ──┤
 llama.cpp source + reviewed metallib ─┘
                                      │
──────────────────────── installed runtime boundary ────────────────────────
                                      ▼
 microphone → process memory → Core ML/ANE → final text ─┬─→ focused app
                                                         │
                      S1-mini by Superwhisper ← text only┘
                         sealed llama.cpp/Metal      └─ optional clipboard
```

Trusted components are the selected source revision, reviewed vendored
FluidAudio subset, checksum-locked model revisions, GitHub-hosted release workflow,
Apple's code-signing/notarization system, macOS frameworks, and the local user
account. The focused application is a recipient, not part of VoxHearth's
privacy boundary.

## Threats and mitigations

| Threat | Mitigation | Residual risk |
| --- | --- | --- |
| Audio or transcripts are sent to a service | No runtime networking implementation; no network entitlement, updater, telemetry, or remote model API; the vendored ASR subset omits FluidAudio downloader/cache clients; source scans and the final binary gate reject networking APIs and linked CFNetwork/Network frameworks. | The app is deliberately not sandboxed because cross-app text insertion requires Accessibility. A malicious future change could restore networking unless review and CI controls catch it. Host firewall monitoring provides additional assurance. |
| Sensitive content is left on disk | Audio capture and transcript state are memory-only; no history/database/audio-file path exists. A failed-insertion transcript is eligible for Retry/Discard for at most two minutes before automatic discard. | macOS may page process memory, capture diagnostics, or expose data to a privileged process. The destination app may persist inserted text. |
| Logs leak content | Logger accepts only a closed enum of event identifiers plus error type names. | OS-level crash reports or diagnostics outside VoxHearth's implementation are governed by macOS settings. |
| Live preview exposes or persists dictated text | Preview is opt-in and off by default; it uses a passive in-process panel rather than Notification Center, retains no history, and clears on cancellation or shortly after completion. Only the separately produced final transcript is inserted. | Nearby people and display-capture or screen-sharing software can observe visible preview text. Repeated local inference uses additional compute and can delay final transcription on slower Macs. |
| Global activation becomes an input logger | Carbon receives only the configured keyboard shortcut. Optional pointer activation subscribes only to middle/extra-button down/up events and filters immediately to the selected button number; it does not observe keys, movement, scrolling, or primary/secondary clicks. | Accessibility permission is powerful; a compromised VoxHearth binary could misuse it. Signature and source verification matter. |
| Clipboard leaks transcript | Clipboard path is off by default; when enabled, prior contents are snapshotted and conditionally restored. | Clipboard managers, Universal Clipboard, or other same-user processes can observe the temporary value. |
| Model changes after review | Exact Hugging Face commit plus per-file sizes and SHA-256 values; fetch occurs only during build; verifier rejects missing and extra files. Model bytes are inside the signed app. | Model behavior itself is not formally verified and can make inaccurate or biased transcriptions. |
| Cleanup exfiltrates a transcript or loads replacement code | S1-mini by Superwhisper receives text only after final English ASR. Its GGUF and the sealed precompiled Metal library load from fixed signed-bundle-relative paths with exact size/hash manifests. The linked llama.cpp subset has no downloader, server, socket, dynamic-backend discovery, environment steering, or runtime shader compiler. Product evaluation runs with networking denied and hostile `GGML_*` values. | macOS frameworks and privileged local software remain outside this guarantee; a malicious future source change must be caught by review, static gates, or runtime observation. |
| Cleanup hallucinates, loses, or misroutes text | One typed session owns final ASR, immutable directive parsing, cleanup, recovery, and exactly-once insertion. Invalid/late/timed-out output falls back to the command-stripped raw transcript. A previous cleanup cannot mutate a newer session. | A structurally valid rewrite can still alter meaning. Users must review consequential text. |
| A `list` or `email` mention unexpectedly becomes a command | Detection is optional and requires the complete word at the start of a new final transcript under a frozen delimiter grammar. Later mentions, substrings, stems, and filler-prefixed mentions do not activate it. | Beginning ordinary dictation with exactly `list` or `email` intentionally activates the configured command; users can disable either detector. |
| Cleanup exhaustion blocks microphone release or the next shortcut | Audio stops before preview cancellation and cleanup. Cleanup has a bounded deadline, runs outside the capture critical path, and a new press expedites a new session without awaiting old work. | Severe system-wide scheduler or memory pressure can still delay the process; lifecycle diagnostics identify the stage without logging content. |
| Dependency substitution | The reviewed FluidAudio subset and provenance are committed with the app; its origin is pinned by full Git commit; GitHub Actions are pinned by full commit; release SBOM and source archive record the inputs. | A compiler/platform or repository compromise remains possible. Source review and signed provenance reduce, but do not eliminate, this class. |
| Release artifact is replaced | Developer ID signature, Apple notarization ticket, published SHA-256, and GitHub provenance/SBOM attestations; verification instructions are public. | The Apple developer account, repository release permissions, or signing secrets could be compromised. Branch/environment protection and key rotation are operator responsibilities. |
| Silent update introduces new behavior | There is no updater or appcast. Updates are manual signed DMG installs. | Users must actively check for and install security updates. |

## Explicit non-goals

VoxHearth does not attempt to protect dictation from:

- a compromised macOS installation, kernel, firmware, microphone driver, or
  administrator/root account;
- malware running as the user that can inspect memory, Accessibility events, or
  the pasteboard;
- the application receiving inserted text, including its sync and telemetry;
- someone who can hear the speaker or access the physical microphone;
- model errors, hallucinations, bias, or unsuitable use in safety-critical
  contexts; or
- the network activity needed on a separate build/release machine.

## Release gates

A release fails if any of these conditions is not met:

- all tests and static offline-contract scans pass;
- all three model trees and the sealed Metal library match their committed manifests exactly;
- the app contains the expected bundle ID, minimum OS, exact legal files, models, and S1-mini/Qwen/llama.cpp attribution;
- the app has no network, iCloud, associated-domain, app-group, or debug
  entitlement; the signed entitlement dictionary must exactly equal
  `Documentation/Distribution/VoxHearth.entitlements` (microphone input only);
- direct dynamic-library dependencies must remain within the reviewed set:
  Accelerate, Foundation, Metal, MetalKit, AVFAudio, AVFoundation, AppKit,
  ApplicationServices, AudioToolbox, Carbon, CoreAudio, CoreFoundation,
  CoreGraphics, CoreML, ServiceManagement, SwiftUI, the system Swift runtime,
  libSystem, libc++, and libobjc. Any newly linked framework fails closed until
  this allowlist is deliberately reviewed and updated;
- the app and DMG have the expected Developer ID team, valid signatures,
  accepted notarization, and stapled tickets;
- checksums, SPDX SBOM, provenance metadata, complete corresponding source, and
  GitHub provenance and SBOM attestations accompany the DMG; and
- the release tag resolves to the exact source revision being built.

See [VERIFY_RELEASE.md](VERIFY_RELEASE.md) for independent verification and
[SECURITY.md](../SECURITY.md) for private reporting.
