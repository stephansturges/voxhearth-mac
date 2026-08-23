# S1-mini transcript cleanup integration

Status: implementation-ready plan awaiting product-owner go/no-go

Last revised: 2026-08-20

Planning authority: the user owns scope and acceptance; Codex is the sole
repository writer; Claude Opus/max supplied read-only architectural review.
Model behavior is grounded in the official S1-mini model card, not inferred
from the model name.

## 1. Outcome

VoxHearth will optionally run S1-mini by Superwhisper after final English ASR
and before text insertion. Cleanup is disclosed during onboarding, checked by
default, uses semi-formal styling by default, runs entirely on-device, and
never processes audio or live-preview snapshots.

The feature includes two independently configurable session-prefix commands:

- a new dictation beginning with the complete word `list` selects the trained
  `Structure: lists` mode;
- a new dictation beginning with the complete word `email` selects the trained
  `Context: email` mode.

The command is recognized only at the beginning of that one final transcript.
Mentioning either word later does nothing. A recognized command is removed
before normalization and insertion. It never persists to a later session.

The runtime target is the official pinned Q4_K_M GGUF through a minimal,
statically linked llama.cpp/ggml Metal backend. CPU+Accelerate remains compiled
as the benchmark control and bounded fallback. MLX is out of scope for v1
because Superwhisper does not publish an official S1-mini MLX artifact.

## 2. Settled product decisions

- Performance floor: Apple M2 with 16 GB unified memory.
- Supported cleanup language: the current settings language, after
  `normalizedForSelectedModel()`, must be `.english` when final ASR completes.
  Automatic language detection is not added by this feature.
- Cleanup default: checked after disclosure.
- Styling default: `semi-formal`.
- `list` prefix detection default: checked.
- `email` prefix detection default: checked.
- Prefix detection is exact, deterministic, first-word-only, and session-local.
- A recognized prefix is a command, not intended output, and is removed from
  the normalization input and every automatic fallback insertion.
- The original ASR transcript remains immutable and memory-only for the active
  session; it is never logged or persisted.
- There is no app or DMG size ceiling. Exact sizes, hashes, disk requirements,
  expected-file sets, and duplicate-payload checks remain mandatory.
- Public redistribution is product-owner-cleared provided all naming, license,
  attribution, provenance, source, signing, notarization, and verification
  obligations in this plan pass.
- Publishing a particular artifact still requires a later explicit instruction.

The exact-prefix rule means `email Stephan about the meeting` intentionally
selects email formatting when email detection is enabled. This is not treated
as a parser false positive: it follows the product rule. Users who commonly
begin ordinary dictation with that verb can disable the email checkbox or say
`send an email ...` instead.

## 3. Authoritative model contract

Primary source:

- https://huggingface.co/superwhisper/s1-mini
- inspected model-card commit:
  `65f84bcda1d13df582c4a8443c1c5aa53c0c66db`
- inspected README SHA-256:
  `b22a4ce83218b21af2e71c7e0d28b686239a0028299cdbc87e4238b2568cfd97`

Payload source:

- repository: `superwhisper/s1-mini-GGUF`
- revision: `8eab4779866f477ae6e7f237ca45fc2c65153f50`
- file: `s1-mini-q4_k_m.gguf`
- bytes: `484219808`
- SHA-256:
  `3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634`

Payload provenance was retrieved from the Hugging Face revision API with blob
metadata enabled. At the pinned revision the GGUF LFS object reports the same
size and SHA-256. P8's build-only download and local SHA-256 computation remain
the authoritative fail-closed gate.

License source:

- identity: Apache License 2.0 plus the repository's additional naming term;
- SBOM expression: `Apache-2.0 AND LicenseRef-S1-mini-Naming-Clause`, with the
  complete additional term included as extracted licensing information;
- required identification: `S1-mini by Superwhisper` with exact capitalization;
- GGUF source:
  `https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/8eab4779866f477ae6e7f237ca45fc2c65153f50/LICENSE`;
- model-card/weight source:
  `https://huggingface.co/superwhisper/s1-mini/resolve/65f84bcda1d13df582c4a8443c1c5aa53c0c66db/LICENSE`;
- bytes: `11878`;
- SHA-256:
  `d956d2d305a0639211c9cbde71501accb0e1474cc9ddf79a47820a522aff6f98`.

The two pinned repositories currently return byte-identical license files with
that size and digest. The shipped license resource must be the complete pinned
file, including its redistribution terms and additional naming term. Automated
attribution checks verify both upstream pins remain identical, compare the
shipped digest, and assert the composite SBOM expression rather than rephrasing
or mislabelling the additional term as plain Apache-2.0.

The implementation must follow these model-card facts:

- The exact documented system prompt, trained control-line syntax, and
  thinking-disabled assistant prefix are part of the input contract.
- The only trained styling values are `casual`, `semi-casual`, `semi-formal`,
  and `formal`.
- The only trained structure values are `prose` and `lists`.
- The only trained context values are `general` and `email`.
- The axes are independent. VoxHearth must not invent a new value or rewrite
  the control prompt to describe its prefix commands.
- `lists` permits Markdown bullets, is intended for at least three real items,
  and may correctly leave non-enumerable content as prose.
- `email` permits a greeting, body, and sign-off separated by blank lines.
- Generation is greedy with thinking disabled.
- A normal output-token ceiling is approximately `1.3 * inputTokens + 32`.
- Individual passes should remain below roughly 1,000 input tokens.

During implementation, the exact trusted strings will be extracted from the
pinned card/template, recorded in provenance, and protected by byte and token-ID
goldens. This document intentionally does not create an alternative prompt.

## 4. Prefix-command contract

### 4.1 Static enablement

Parse a directive only when all of the following are true:

- cleanup is enabled;
- cleanup disclosure version is current;
- the settings language, after `normalizedForSelectedModel()`, is `.english` at
  final-ASR completion;
- the S1-mini asset URL is inside the bundle, is a regular file, and has the
  expected size according to a process-cached verification result;
- the matching directive checkbox is enabled.

Model readiness is not a static condition. Once a command is recognized, a
runtime not-ready or backend failure still uses the command-stripped fallback.

Never hash 484 MB on the per-session path. Full digest verification occurs at
build/package verification and at most once per process during preparation.
The signed resource seal is the normal runtime integrity control. Static
enablement resolution must remain sub-millisecond.

When static cleanup is ineffective, do not parse or remove anything. Insert the
original transcript according to the existing path and never touch S1-mini.

### 4.2 Recognition grammar

Run the parser exactly once after final ASR and before prompt construction.
Never run it on live preview.

1. Skip leading Unicode whitespace only.
2. Compare the first ASCII word case-insensitively to `list` or `email`.
3. Require an exact word boundary.
4. Require either, subject to the P1 real-ASR evidence freeze:
   - one or more Unicode whitespace characters after the word; or
   - exactly one attached `:` or `,`, followed by one or more Unicode
     whitespace characters.
5. Skip the accepted separator whitespace and require a non-empty payload.
6. Remove exactly the command and accepted delimiter from the effective input.
7. Do not inspect any later word for another directive.

Recognition is English-only ASCII comparison, not locale-sensitive case
folding, fuzzy matching, stemming, regex, or natural-language classification.
It scans only the prefix and has no backtracking.

The whitespace/colon/comma delimiter set is provisional until P1 records real
final-ASR strings for spoken commands across both Parakeet variants, with and
without a pause. A punctuation delimiter such as a period may be added only if
that evidence shows the ASR emits it immediately after the exact command word;
the frozen strings become parser fixtures and settings/onboarding copy must
match the final accepted spoken forms.

Normative examples:

| Final transcript | Settings | Result | Effective transcript |
|---|---|---|---|
| `list milk eggs bread` | list on | `listGeneral` | `milk eggs bread` |
| ` LIST: milk eggs bread` | list on | `listGeneral` | `milk eggs bread` |
| `email, Hi John ...` | email on | `proseEmail` | `Hi John ...` |
| `listing the options` | list on | ordinary | unchanged |
| `listening to Michael` | list on | ordinary | unchanged |
| `emailing John today` | email on | ordinary | unchanged |
| `my email is ...` | email on | ordinary | unchanged |
| `the list Michael sent ...` | list on | ordinary | unchanged |
| `in reference to the list ...` | list on | ordinary | unchanged |
| `uh list milk eggs bread` | list on | ordinary | unchanged |
| `list email John ...` | both on | `listGeneral` | `email John ...` |
| `email list milk ...` | both on | `proseEmail` | `list milk ...` |
| `list` | list on | ordinary | unchanged |
| `email   ` | email on | ordinary | unchanged |
| `list:items` | list on | ordinary | unchanged |
| `list milk eggs bread` | list off | ordinary | unchanged |

A BOM, zero-width character, quote, or punctuation before the word is not
whitespace and therefore prevents recognition. Unicode homoglyphs do not
match. These constraints deliberately prefer predictable false negatives over
content-deleting false positives.

### 4.3 Format mapping

Use one exhaustive enum rather than independent runtime booleans:

```text
CleanupFormat.proseGeneral -> Structure: prose, Context: general
CleanupFormat.listGeneral  -> Structure: lists, Context: general
CleanupFormat.proseEmail   -> Structure: prose, Context: email
```

The selected styling is orthogonal and maps to its exact trained value.

Modes never latch. Every new session starts at `proseGeneral` until its own
final transcript is parsed.

### 4.4 Immutable source and command-aware fallback

Represent the transformation without storing duplicate command-bearing and
stripped strings:

- `FinalTranscript` owns the immutable ASR text and `DictationSessionID`.
- `DirectiveParse` owns the `FinalTranscript`, recognized directive, format,
  and a validated UTF-8 payload-start offset.
- `NormalizationInput` derives the untrusted model payload from that range.
- `InsertableTranscript` is the only type `TextInserting` accepts.

For a recognized directive, every automatic fallback contains the effective
transcript without the command. For an ordinary session, fallback contains the
original. The original command-bearing value cannot reach insertion after
recognition, and a value stamped for one session cannot be inserted by another.

An explicit whole-session Cancel remains different from cleanup-stage
cancellation: whole-session Cancel inserts nothing and returns to idle.

Allocate `DictationSessionID` exactly once when a start is accepted and carry it
unchanged through capture, final ASR, cleanup, insertion, pending recovery, and
completion. It is not derived from the baseline `sessionEpoch`. The epoch
remains a separate supersede/abandon token and may continue changing at start,
stop, or cancellation without changing ownership of the accepted session.

## 5. State machine and orchestration

The final path is:

```text
hotkey release
  -> synchronous microphone stop
  -> join/cancel live preview
  -> final ASR
  -> clear final-ASR task
  -> resolve static cleanup enablement
  -> parse the current final transcript once
  -> cleaning(format)
  -> validate/select cleaned or fallback text
  -> insertion
  -> idle
```

Required rules:

- S1-mini receives text only after final ASR; it never receives audio.
- Cleanup never runs on live-preview snapshots.
- Normalization never runs on MainActor or a Swift cooperative executor.
- Overlay and observable state mutations run on MainActor.
- Exactly one S1-mini normalization request exists per dictation session.
- Chunking, if used, is internal to that request and never produces a partially
  cleaned insertion.
- The selected `InsertableTranscript` is protected by a session-keyed automatic
  insertion guard. It permits at most one automatic selection-to-insertion
  attempt for a session. A deliberate user retry creates one separately tracked
  retry attempt; it never reopens automatic fallback.
- Late output from an aborted or superseded generation is discarded using its
  generation and session IDs.

### 5.1 Press during cleanup

A new activation press during `.cleaning` must never feel ignored:

1. Set the normalizer abort flag synchronously before any await.
2. Change the overlay immediately to the format-aware fallback state.
3. Select and insert the session fallback exactly once.
4. Record deferred-start intent.
5. Wait no more than the spike-set expedite restart bound, provisionally 100 ms,
   for insertion to reach a terminal outcome.
6. If the activation remains physically held at that bound, start the new audio
   capture even when the previous insertion is still resolving. Do not make the
   first audio sample wait on a cross-process Accessibility timeout.
7. If the previous insertion later fails or is uncertain, retain it in the
   session-keyed pending store. It remains recoverable while the new capture is
   active and can never be inserted automatically into that new session.
8. If the activation was released, do not create a phantom recording.

The same deferred-start principle applies while final transcription or
insertion is finishing.

Replace the single implicitly cleared pending value with a small session-keyed
`PendingInsertionStore`. New starts never clear it implicitly. Copy, confirmed
Insert Anyway/Retry, Discard, or the documented two-minute expiry removes an
entry. Cap it at three entries; if all three remain unresolved, refuse a fourth
capture with a content-free recovery-required status rather than dropping text.
The recovery UI identifies entries by relative order/time only, never logs or
persists their content, and makes clear that they belong to previous dictations.

Add a user-reachable whole-session Cancel action while `.cleaning` in the
menu-bar popover, with keyboard access and an accessible label. It aborts the
cleanup generation, discards the current session without insertion, and clears
only that session's transient original/effective values. The overlay remains
passive and noninteractive. A hotkey press during cleanup remains expedite, not
Cancel.

## 6. Core interfaces

Introduce these Sendable types or equivalent verified baseline names:

- `DictationSessionID`
- `FinalTranscript`
- `RecognizedDirective { list, email }`
- `CleanupFormat { proseGeneral, listGeneral, proseEmail }`
- `DirectiveParse`
- `NormalizationInput`
- `InsertableTranscript`
- `DictationOutcome`
- `CleanupStyling`
- `CleanupSettings`
- `CleanupStatus`
- `CleanupFallbackReason`
- `S1MiniError`
- `PendingInsertionEntry` and session-keyed `PendingInsertionStore`

`TextInserting.insert` changes from accepting `String` to accepting
`InsertableTranscript`. Its initializer is module-internal and available only
to the parser/policy selection boundary. Update pending insertion and retry to
retain the typed value and its session ID.

Keep `DictationSessionID` and the baseline `sessionEpoch` as distinct named
fields. Tests must demonstrate that start-to-insertion identity remains stable
even though the epoch changes, and that a previous session's typed value cannot
be automatically inserted by a later session.

The pure `CleanupDirectiveParser`:

- performs no I/O, persistence, logging, actor hop, model call, or regex;
- scans only enough scalars to decide the prefix;
- returns a typed result with the validated payload offset;
- never transforms payload text.

`CleanupPolicy` owns:

- static effective-enablement;
- directive-aware fallback selection;
- filler-only classification;
- exhaustive format-to-control mapping;
- token and deadline planning;
- output validation;
- the only cleaned-output construction of `InsertableTranscript`.

## 7. Prompt and output contract

### 7.1 Prompt assembly

- Resolve trusted control markers once and assert that required markers are
  single tokens.
- Tokenize trusted system, control-line, role, and assistant-prefix pieces with
  special-token recognition enabled as required.
- Tokenize the effective user transcript separately with special-token
  recognition disabled.
- Concatenate token arrays in the exact trained order.
- Never strip or interpret control-token-looking text from user content.
- Preserve literal `<|...|>`-looking user text in fallback and comparison.
- Use greedy decoding and the exact thinking-disabled assistant prefix.

Create twelve mandatory portable token-ID goldens: four styling values by the
three `CleanupFormat` cases. Add a whole-template seam-fidelity test around
every trusted/untrusted boundary.

### 7.2 Token budgets and long structured input

Use exact tokenizer counts, never character estimates.

Start with the documented output ceiling, then apply format-specific minimum
headroom validated by fixtures because a short email may legitimately add
layout and sign-off tokens:

```text
maxNewTokens = min(
  remainingContext,
  max(ceil(1.3 * inputTokens + 32), formatFloor)
)
```

Provisional floors for the spike are 64 for ordinary prose, 96 for lists, and
128 for email. Hitting the bound without EOG is truncation and falls back.

Ordinary prose may chunk at sentence boundaries below the measured token cap.
Lists and email are single-pass only because independent chunks would destroy
global structure. If a structured effective transcript exceeds the safe
single-pass budget, do not silently turn it into prose and do not run multiple
formatting passes. Insert the directive-stripped effective transcript
unformatted, show `Too long to format - inserted without the command`, and log
only `inputTooLong` alongside the already permitted `CleanupFormat` enum.

Run a budget preflight before any generation for every format. If
`remainingContext < formatFloor`, or the input exceeds the measured safe pass
budget and no valid plan exists, make zero model calls and insert the session
fallback immediately. This includes ordinary prose with no safe sentence
boundary below the cap. Use the content-free `inputTooLong` reason; directive
sessions use the command-aware copy, while ordinary prose says
`Too long to clean up - using original transcript`.

### 7.3 Validation

Accept cleaned output only when generation terminates on EOG/end-of-message.
Reject to fallback on:

- deadline or cancellation;
- special-token, think-marker, prompt, or control-line leakage;
- invalid control characters other than tab and U+000A newline; explicitly
  reject U+000D, U+0085, U+2028, and U+2029 from model output;
- Unicode replacement/unpaired scalar problems;
- format-adjusted runaway length;
- ungrounded repetition;
- loss of a literal URL, email, backticked span, or `://` identifier;
- empty output when deterministic filler-only classification disagrees;
- non-EOG token-bound termination.

Do not reject an email address or URL solely because the exact written form was
not present in the raw transcript. Permit traceable inverse text normalization
from spoken `at`, `dot`, `dash`, `hyphen`, `underscore`, `slash`, `colon`, and
spelled digits using a bounded published substitution table. Reject an address
that cannot be traced to the effective input.

Do not require bullets under `listGeneral`; the model card explicitly permits
non-enumerable content to remain prose. Preserve internal newlines and blank
lines verbatim.

## 8. Runtime and model lifecycle

### 8.1 Backend

- Production target: llama.cpp/ggml Metal with all supported layers offloaded.
- Control and fallback: CPU+Accelerate in the same static runtime.
- Out of scope: MLX, remote packages, Hub/downloader code, server, RPC,
  subprocess inference, dynamic backend loading, and every unused ggml backend.
- Backend choice is injected in tests and capability-based in production; it
  must never read process environment configuration.

Metal unavailability during preparation selects CPU before a request. A Metal
failure during generation inserts fallback and demotes later sessions to CPU.
The only permitted same-request CPU retry is when Metal fails before producing
any token and before consuming 25% of the deadline. Otherwise never double the
user-visible wait.

### 8.2 Shader packaging

- Pin the spike-proven llama.cpp revision and exact vendored file manifest.
- Compile the pinned `ggml-metal.metal` during packaging with the recorded Xcode
  Metal compiler.
- Ship one signed resource at
  `Contents/Resources/Metal/ggml-llama.metallib`.
- Patch the loader to accept exactly that bundle-relative URL.
- Remove embedded raw-source compilation, executable-directory fallback,
  environment-selected paths, and all `GGML_METAL_*` environment steering.
- Require zero `getenv(` under the vendored runtime.
- Record shader source hash, metallib hash, and `xcrun metal --version`.
- Include shader source, patches, manifest, and build script in the source
  bundle.

Plain `swift build` and `swift test` remain useful without full Xcode or a
metallib and use CPU locally. Release packaging requires full Xcode and the
verified metallib. Release verification enforces the hash recorded by that
release build; a different toolchain must create and record a new artifact.

### 8.3 Ownership and residency

- `LlamaRuntime.shared` performs process-wide backend init and installs one
  non-capturing logging callback exactly once.
- Never call global backend free from ordinary model unload.
- No llama.cpp or Metal API call occurs from `deinit`.
- One `S1MiniNormalizer` actor owns one model and one context.
- Blocking C/C++ work runs on one dedicated serial queue: user-initiated for
  active cleanup and utility for warm-up/unload.
- Warm-up begins only after cleanup disclosure, only when checked, and strictly
  after Parakeet preparation.
- Warm-up performs real fixed prefill and at least two decode steps so lazy
  Metal pipelines compile before user-visible work, then clears KV.
- Clear KV before/after requests and between ordinary-prose chunks.
- Retain context while enabled and active unless measured pressure behavior
  requires release.
- Memory-pressure warning may release context; critical pressure, disable,
  unsupported configuration, termination, or the measured long-idle interval
  fully unloads weights/context.
- Termination drains the serial queue with a bounded wait.

## 9. Failure and fallback matrix

| Condition | Inserted value | Status/action |
|---|---|---|
| Cleanup statically inactive | original | no parse/model touch |
| Directive recognized, model not ready | effective | warm in background |
| Backend unavailable | effective/original per parse | demote or warn |
| Metal request failure | session fallback | demote later sessions |
| Deadline | session fallback | `deadline` |
| Non-EOG truncation | session fallback | `truncated` |
| Invalid output | session fallback | `invalidOutput` |
| Structured input too long | effective | no model pass; explain |
| Prose too long/no safe chunk plan | original | no model pass; explain |
| Hotkey expedite | session fallback | abort; new capture starts if still held within the bounded restart budget, independently of late insertion recovery |
| Cleanup-stage cancellation | session fallback | exactly once |
| Explicit whole-session Cancel | nothing | return idle |
| Valid filler-only empty output | nothing | successful empty result |
| Insertion failure | selected typed value | retain in memory for retry |
| Insertion uncertain | selected typed value | no automatic second attempt; retain for explicit user action |
| Multiline, AX unavailable, clipboard disabled | selected typed value | safe pending state with Copy/confirmed Insert Anyway/Discard; setting remains unchanged |
| Multiline destination blocked as terminal | selected typed value | safe pending state; never auto-paste |

Preparation is never on the critical path. If the runtime is not prepared when
the user finishes a session, fallback immediately and prepare for later.

`insertionUncertain` is not an ordinary failure: the text may already exist in
the destination. Never retry it automatically or fall through to another tier.
Show the existing could-not-confirm warning, retain the typed value, and allow
only an explicit user retry after warning that duplication is possible. The
automatic insertion guard remains armed; the explicit retry has its own attempt
identifier and cannot race another retry.

## 10. Settings, onboarding, and visible behavior

### 10.1 Settings schema

Add nested `CleanupSettings` with defaults:

```text
isEnabled = true
styling = semiFormal
listDirectiveEnabled = true
emailDirectiveEnabled = true
```

Do not persist redundant structure/context controls; runtime structure/context
come exclusively from `CleanupFormat`.

Extend the integrated baseline's hand-written `AppSettings` decoding and add a
hand-written `CleanupSettings` decoder using `decodeIfPresent` per field.
Existing explicit values always win. A
pre-cleanup settings payload preserves every existing field and receives the
new defaults without causing the entire settings object to reset.

Store disclosure separately as integer key
`VoxHearth.cleanupDisclosureVersion.v1`; absent means zero. Cleanup cannot
become effective until the required version has been advanced past.

Write disclosure version 1 only when the cleanup disclosure step is completed
or explicitly advanced past, whether the cleanup checkbox finishes checked or
unchecked. For an existing installation with completed onboarding but an
absent/old cleanup disclosure version, add
`OnboardingLaunchReason.cleanupDisclosureRequired` and present the cleanup
disclosure before cleanup can run. Dismissing/skipping leaves version zero and
settings shows `Cleanup is off until the new model disclosure is completed.`

For existing users, evaluate this launch reason at app launch before accepting
a dictation, never during an active or just-completed session. Present it once
per app launch for the required disclosure version. A dismissal does not nag
again during that launch; it is offered again on the next launch, and Settings
always exposes a `Complete cleanup setup` action in the meantime.

Changing a prefix checkbox only changes settings. It does not load a model when
cleanup is disabled, undisclosed, unsupported, or unavailable.

### 10.2 Settings copy

Section: `Transcript cleanup (S1-mini by Superwhisper)`

Main toggle: `Clean up transcripts with a second on-device model`

Explain that VoxHearth runs a second local AI model after each finished English
transcript, improves filler/punctuation/formatting, adds approximately 484 MB
(462 MiB) of model payload before packaging overhead, consumes additional
memory and processing, and adds a short post-release delay. Render the size
from the manifest rather than hard-coding a drifting unit label.

Explain that multiline list/email output first uses Accessibility insertion. In
apps that refuse Accessibility insertion, automatic multiline paste requires
the existing clipboard-compatibility option; if it is disabled, VoxHearth keeps
the result available for explicit Copy, one-shot confirmed Insert Anyway, or
Discard rather than enabling or changing clipboard behavior silently.

Style picker: Casual, Semi-casual, Semi-formal (default), Formal.

List toggle:

`Format dictations starting with "list" as lists`

Explain that only the first word of a new dictation counts, the word is removed,
later mentions do nothing, and formatting is conservative and intended for
three or more actual items.

Email toggle:

`Format dictations starting with "email" as emails`

Explain that only the first word of a new dictation counts, the word is removed,
later mentions do nothing, and the result may include greeting, body, sign-off,
and blank lines.

Keep the sub-toggles visible but disabled with a reason when cleanup is not
effective. Do not make unavailable behavior disappear from the settings UI.

### 10.3 Onboarding and test area

Onboarding order becomes privacy, cleanup, permissions, try-it.

The cleanup step contains:

- second-model resource/delay disclosure;
- English-only explanation;
- default-checked cleanup option;
- styling picker;
- both prefix-command checkboxes and exact behavior;
- preparation only after advancing past disclosure.

The try-it step performs one capture and one production cleanup generation.
Show the original and selected result. When a directive fires, explicitly say
which mode was selected and that the command word would be removed on insertion.

Add static, clearly labelled examples for:

- ordinary semi-formal cleanup;
- `list` producing a three-item list;
- `email` producing greeting/body/sign-off layout;
- `the list ...` and `my email ...` not triggering.

Static examples perform no model work. Trial tasks are cancelled and joined on
Clear, disappearance, and completion before strings and callbacks are cleared.

### 10.4 Overlay

- Final ASR: `Finishing transcription...`
- Ordinary cleanup: `Cleaning up with S1-mini by Superwhisper...`
- List: `Formatting list with S1-mini by Superwhisper...`
- Email: `Formatting email with S1-mini by Superwhisper...`

Compact visual variants retain the full accessible label. The spinner starts
only when cleanup actually begins and has an independent timeout.

When cleanup is effective, do not publish the raw final ASR string into the
overlay between final ASR and insertion. During `.cleaning`, publish status only.
After selection, publish the same `InsertableTranscript` chosen for insertion,
or the same effective fallback, so the final preview cannot show a command word
that the insertion removed.

Fallback copy:

- ordinary: `Cleanup skipped - using original transcript`
- list/email: `Formatting skipped - inserted without the "list" command` or
  corresponding email form
- structured too long: `Too long to format - inserted without the command`

All copy is content-free.

Post accessibility announcements for cleanup start, fallback, insertion
uncertainty, and formatted-text-ready transitions. Every recovery control has a
VoiceOver label, keyboard focus order, and keyboard activation.

## 11. Multiline insertion safety

List and email output makes multiline insertion a first-class safety problem.
Synthetic Return events can submit a chat message, trigger search, or execute a
shell command. Therefore:

- Single-line order remains Accessibility, Unicode, clipboard.
- Multiline order is Accessibility direct-set, then clipboard paste.
- Never synthesize Return key events for multiline output.
- Define a line separator as any of U+000A, U+000D, U+0085, U+2028, or U+2029
  for routing purposes. Output validation permits only U+000A and rejects the
  other four before selection; fallback strings containing any of them still
  take the non-Unicode route.
- Select the multiline route before consulting diagnostic insertion-mode
  overrides. The existing `VoxHearth.diagnostics.insertionMode = unicode-first`
  must not make `postUnicodeText` reachable for any string containing a line
  separator.
- Clear modifier flags on every Unicode event used for single-line insertion.
- Prefer Accessibility for expedited insertion while the hotkey remains held;
  otherwise wait up to the existing bounded release interval before fallback.

Add an injectable `MultilineDestinationSafety` classifier using only focused
application/AX metadata, never field content. For a documented fixed set of
terminal application bundle identifiers, do not paste multiline output
automatically. Retain the chosen text in the existing short-lived pending
insertion state and show `Formatted text ready - copy or insert when safe`.
Add a concrete recovery-card state with accessible, keyboard-operable controls:

- `Copy` explicitly places the selected text on the pasteboard and reports
  success. It intentionally leaves the value on the pasteboard and does not run
  the temporary snapshot/restore behavior used by automatic paste;
- `Insert Anyway` is a one-shot user-authorized override that never changes the
  persisted `clipboardCompatibilityEnabled` setting. It uses one temporary
  snapshot/paste/restore attempt, never Unicode/Return synthesis;
- `Discard` clears the pending text;
- ordinary insertion failures retain `Retry`, but blocked-terminal and
  clipboard-disabled states do not loop through an ordinary Retry action.

Retain this state for the existing 120-second window and say `Available for 2
minutes` in its copy. Expiry clears the in-memory value and posts a content-free
expiry status. Do not log the bundle identifier.

For a destination classified as a terminal, the confirmation says:
`This destination may run pasted lines as commands. Insert anyway? VoxHearth
will remove trailing line breaks, but the destination may still execute earlier
lines.` Derive a one-shot paste payload by removing trailing line-separator
scalars only; keep the pending/source value unchanged. Never assume bracketed
paste is enabled.

When Accessibility is unavailable and clipboard compatibility is disabled,
route multiline output to the same recoverable pending state rather than
throwing an unhandled insertion failure or enabling clipboard automatically.

Unknown destinations retain the Accessibility/clipboard behavior. Document the
residual risk that destination applications ultimately decide how pasted
newlines behave. Manual acceptance must cover plain fields, rich editors, chat
composers, Terminal, and at least one third-party terminal.

A bundle-identifier classifier cannot distinguish embedded terminals from
ordinary editors inside VS Code or JetBrains hosts. Do not block the entire host
application in v1. Document this blind spot, exercise both integrated terminals
manually, and treat their behavior as an explicit residual risk.

The passive overlay announcement says `Formatted text ready. Open the VoxHearth
menu-bar popover to copy or insert it. Available for 2 minutes.` The recovery
controls live only in that popover. VoiceOver acceptance begins at this
announcement and must reach and activate Copy using the keyboard.

## 12. Privacy, security, and logging

- No transcript, command payload, address, recipient, greeting, output, prompt,
  or model token is logged or persisted.
- The logger accepts fixed event identifiers plus `CleanupFormat` and
  `CleanupFallbackReason` enums only; it exposes no free-text cleanup API.
- llama.cpp/ggml logs route to a process-lifetime non-capturing no-op callback.
- No runtime networking, downloader, socket, server, RPC, subprocess, updater,
  remote font/asset, or dynamic backend loading is present.
- Model and metallib paths derive only from `Bundle.main.resourceURL` and must
  remain within the signed bundle.
- Linked frameworks must equal a documented allowlist.
- Release entitlements must equal the existing microphone entitlement set; no
  JIT, unsigned-memory, dyld-environment, or library-validation exception.
- Source scans, binary string/symbol scans, network-denied functional tests,
  resource sealing, and immutable payload manifests fail closed.

## 13. Implementation sequence

### P0 - Reconcile the integrated baseline

Start from integrated diagnostics/lifecycle baseline
`d4be74c8b1435b303a7f8f291d43c632b9e92527`, preserving the current dirty and
untracked model-script work non-destructively.

The preservation inventory is: modified `scripts/fetch-model.sh`,
`scripts/local-check.sh`, `scripts/model-smoke.sh`, and
`scripts/verify-model.py`; untracked
`Models/parakeet-tdt-ctc-110m-coreml.json` and `scripts/fetch-models.sh`.
Record whether the in-flight 110M work already implements multi-payload fetch,
verification, and bundle staging before changing any overlapping file. Preserve
it via an explicit WIP commit or stash including untracked files; never discard
or overwrite it.

Verify and record:

- actual overlay/session state names;
- live-preview cancellation and actor boundaries;
- model-selection/settings fields;
- hand-written decoding status;
- resolved-language behavior;
- lifecycle activity-token placement;
- current ASR-only latency promotion guard;
- Parakeet compute units;
- insertion tiers and framework allowlist.
- existing `sessionEpoch` semantics, insertion uncertainty, diagnostic
  insertion-mode override, pending-transcript expiry/retry, and final-preview
  publication;
- existing multi-model staging path and manifest naming.

Stop before implementation if Parakeet now uses the GPU, because that changes
the Metal contention premise. Run the untouched baseline local check.

### P1 - Throwaway two-machine backend spike

On an isolated branch, pin llama.cpp and test CPU+Accelerate and Metal on the
M2/16 GB floor and development Mac. Do not merge spike code.

Measure all three formats and both backends:

- load, metallib, and pipeline-compilation time;
- real dummy warm-up and zero post-warm-up compilation;
- p50/p95/p99 and release-to-insertion at 10, 40, and 150 words;
- tokens/sec, exact token/output bounds, short-email EOG behavior;
- physical footprint/slope, Metal allocated bytes, live objects, tasks, threads,
  contexts, idle CPU;
- hotkey-to-cue, audio start/stop, Parakeet final latency, overlay and
  WindowServer frame behavior;
- expedite-press-to-first-audio-sample p50/p95 with a deliberately slow
  Accessibility destination, setting the restart wait so p95 is no more than
  100 ms above the ordinary accepted-start promotion guard;
- energy, thermal state, memory pressure, sleep/wake, user switch, forced Metal
  failures, and 24-hour residency;
- `n_ctx`, `n_ubatch`, thread count, chunk budget, long-idle interval, and final
  measured deadline thresholds.
- final-ASR strings for at least 20 spoken `list ...` and `email ...` examples
  across both Parakeet variants, with and without a pause; freeze the observed
  safe delimiter set and store the real outputs as parser fixtures;
- every forbidden source/binary string or undefined-symbol match from the
  pinned runtime closure by running the existing release-binary gate against
  the spike release binary before any vendoring phase is accepted;
- static enablement resolution time, proving no per-session digest calculation
  and sub-millisecond cached asset checks.

Metal remains the target if it provides a meaningful end-to-end or CPU-headroom
benefit and passes every UX/resource gate. There is no arbitrary required
percentage win. If Metal fails a responsiveness, thermal, energy, or stability
gate, use CPU and repeat the full acceptance suite.

### P2 - Vendor and harden the runtime

Files:

- `Package.swift`
- `Vendor/LlamaLocal/**`
- `Vendor/LlamaLocal/UPSTREAM.md`
- `Vendor/LlamaLocal/FILES.json`
- `Vendor/LlamaLocal/PATCHES.md`
- `scripts/check-vendored-llama.py`
- `scripts/build-metallib.sh`
- `scripts/local-check.sh`
- `LICENSES/llama.cpp-MIT.txt`

Vendor the exact spike-proven directory-granular closure, excluding tools,
examples, server, RPC, dynamic backends, unrelated accelerators, and common app
helpers. Pin every byte and patch. Add a plain SwiftPM target with CPU,
Accelerate, and Metal only. Verify Swift debug/release builds without CMake.

Extend `local-check.sh` source pathspecs to include `Vendor/LlamaLocal/**` for
networking, updater, telemetry, dynamic-loading, environment, and durable-file
API scans. Add C/C++/Objective-C patterns for `sys/socket.h`, `getaddrinfo`,
socket/connect APIs, curl, `dlopen`, and `getenv(`, with only the documented
read-only model/metallib open/mmap path allowed. Mutation tests temporarily add
`getenv(` and a socket header and must make the gate fail.

Enumerate every `https?://`, downloader-like, socket, and forbidden undefined
symbol match in the linked release binary. Remove unreachable strings from the
compiled closure or patch them in the pinned, documented patch set. Do not
weaken the existing fail-closed pattern. Any truly required exception must be
an exact reviewed symbol/string allowlist entry tied to the runtime pin, never a
broad regex exemption.

### P3 - Add typed cleanup core

Files:

- `Sources/VoxHearthCore/TranscriptTypes.swift`
- `Sources/VoxHearthCore/CleanupModels.swift`
- `Sources/VoxHearthCore/CleanupDirectiveParser.swift`
- `Sources/VoxHearthCore/CleanupPolicy.swift`
- `Sources/VoxHearthCore/S1MiniPrompt.swift`
- `Sources/VoxHearthCore/S1MiniNormalizer.swift`
- `Sources/VoxHearthCore/LlamaRuntime.swift`
- `Sources/VoxHearthCore/LlamaBackendSelection.swift`
- relevant protocols/models/logger files

Implement types, parser, policy, prompt assembly, actor/queue ownership, warm-up,
generation, validation, cancellation, resource counters, backend selection, and
privacy-safe events. Unit-test without model bytes first.

### P4 - Settings and migration

Files:

- `Sources/VoxHearthCore/AppSettings.swift`
- `Sources/VoxHearthApp/VoxHearthFrontendModel.swift`
- `Tests/VoxHearthCoreTests/AppSettingsTests.swift`

Add cleanup settings, extend the integrated baseline's resilient decoding, add
disclosure versioning and the disclosure re-prompt launch reason, implement
effective-enablement policy and mutation methods, and prove old settings
survive while directive toggles do not prepare a model.

### P5 - Orchestration and insertion

Files:

- `Sources/VoxHearthCore/DictationController.swift`
- `Sources/VoxHearthCore/TextInsertionService.swift`
- `Sources/VoxHearthCore/CoreProtocols.swift`
- corresponding controller/insertion tests

Integrate final-session parsing, `.cleaning`, typed insertion, full fallback
matrix, expedite/deferred start, pending retry, and multiline safety. Compile
failure must prove no bare string or `FinalTranscript` can reach insertion.

Allocate stable `DictationSessionID` at accepted start and keep it distinct from
`sessionEpoch`. Scope the automatic one-shot guard and explicit retry attempt as
defined above. Make multiline routing occur before diagnostic-mode selection;
`postUnicodeText` must be unreachable for line separators even under
`unicode-first`. Add explicit branches for clipboard-disabled multiline,
blocked terminals, and `insertionUncertain`. Implement the session-keyed pending
store so a bounded expedited restart cannot clear, overwrite, or automatically
reuse the prior session's retained value.

### P6 - Settings, onboarding, examples, and overlay

Files:

- `Sources/VoxHearthApp/SettingsRootView.swift`
- `Sources/VoxHearthApp/OnboardingView.swift`
- `Sources/VoxHearthApp/CleanupExamples.swift`
- `Sources/VoxHearthApp/FrontendPresentation.swift`
- `Sources/VoxHearthApp/ApplicationPresentation.swift`
- `Sources/VoxHearthApp/LiveTranscriptOverlayController.swift`
- `Sources/VoxHearthApp/VoxHearthFrontendModel.swift`
- `Sources/VoxHearthApp/MenuBarContentView.swift`
- `Sources/VoxHearthCore/LifecycleActivityScope.swift`
- `Sources/VoxHearthCore/LivePreviewSession.swift`
- corresponding presentation tests

Implement exact copy/states, accessible controls, one-capture comparison, static
examples, joined task cleanup, post-disclosure preparation, and content-free
status reporting. Add the concrete 120-second safe-pending recovery card with
Copy, confirmed Insert Anyway, and Discard; keep ordinary Retry only for
ordinary confirmed failures. Add accessibility announcements and keyboard
navigation for every transition/control. Suppress raw final-preview publication
during cleanup and publish only the selected insertable result afterwards.

### P7 - Complete test and evaluation matrix

Add:

- table-driven parser tests for every normative row and boundary;
- realistic maximum-capture-size prefix-cost test;
- parser fixtures captured from both real Parakeet variants with and without a
  pause after the command;
- twelve token-ID prompt goldens and seam-fidelity test;
- adversarial control-token containment;
- list, prose-under-lists, technical-list, full-email, no-signoff-email,
  spoken-address, hallucinated-address, filler, correction, number/date/currency,
  long-input, timeout, failure, and expedite fixtures;
- both CPU and Metal semantic runs with one monotonic `RATCHET.json`;
- insertion fidelity and terminal safety tests;
- diagnostic `unicode-first` plus multiline proving zero Unicode calls;
- AX-unavailable multiline with clipboard compatibility on and off;
- pending-state control matrix; Copy leaves the value on the pasteboard, while
  one-shot Insert Anyway preserves the stored compatibility preference and uses
  temporary snapshot/restore;
- blocked-terminal confirmation naming execution risk and a paste payload with
  no trailing line separator;
- routing tests for U+000A/U+000D/U+0085/U+2028/U+2029 and validation rejection
  of every model-output separator except U+000A;
- ambiguous Accessibility outcome proving zero automatic second attempts;
- expedite plus slow/failing insertion proving first audio starts within the
  bounded restart budget while pending text survives under its original ID;
- prose exceeding the budget with no sentence boundary and
  `remainingContext < formatFloor`, proving zero generation calls;
- stable session identity across start/stop epoch changes;
- multiple pending session entries surviving independent starts without being
  inserted into or overwritten by a later session;
- a user-reachable menu-bar Cancel during cleaning proving zero insertion;
- directive cleanup with overlay enabled, proving final publication matches the
  selected insertion and never republishes the command;
- an existing completed-onboarding profile with missing disclosure version;
- non-English settings proving zero parser/model calls and unchanged insertion;
- accessibility/presentation tests for every safe-pending state;
- exhaustive mapping from each over-budget condition to the single
  `inputTooLong` fallback reason plus `CleanupFormat`;
- network-denied real-model smoke;
- post-warm-up, soak, memory, task/thread, energy, thermal, and responsiveness
  checks.

Output byte identity across GPU families is advisory. Prompt/token identity and
semantic assertions are mandatory.

### P8 - Package model and metallib

Files:

- `Models/s1-mini-gguf.json`
- model verification/fetch scripts
- metallib and app-bundle scripts
- release binary/verification/source-bundle scripts

Add the exact model manifest, build-only fetch, sealed metallib staging,
free-space preflight, exact sizes/hashes, and structural asset checks. The model
directory may contain exactly the approved payload roots plus the single
`Manifests` directory; each root must appear once, `Manifests` must contain
exactly one uniquely named manifest per approved root and nothing else, and no
payload digest may be duplicated under another root. No size threshold may fail
the build.

Use a concrete multi-root layout:

```text
Contents/Resources/Models/<bundleRoot>/<manifest-approved payloads>
Contents/Resources/Models/Manifests/<bundleRoot>.json
```

`build-app-bundle.sh` performs the free-space preflight before staging, stages
each approved root and uniquely named manifest, then runs union/root/digest
checks before signing and again from `verify-release.sh` after signing. It must
not reuse or overwrite a single `Resources/Models/manifest.json`. Migrate both
`scripts/build-app-bundle.sh` and `scripts/verify-release.sh` away from their
hard-coded manifest/root paths. Negative tests add an extra file under
`Manifests`, remove one per-root manifest, and verify both pre-signing and
post-signing checks fail.

### P9 - Documentation and licensing

Update:

- `NOTICE`
- `THIRD_PARTY_NOTICES.md`
- `Documentation/MODEL_PROVENANCE.md`
- `Documentation/PRIVACY.md`
- `Documentation/THREAT_MODEL.md`
- `Documentation/BUILDING.md`
- `Documentation/RELEASE.md`
- `Documentation/VERIFY_RELEASE.md`
- `LICENSES/**`
- `scripts/check-attribution.py`
- SBOM/provenance scripts
- README and changelog

Required licensed presentation is `S1-mini by Superwhisper`. Include the pinned
S1-mini license and naming clause, Qwen3-0.6B license/attribution, llama.cpp MIT
license, model card/payload/runtime pins, source manifest/patch record, built-app
Legal resources, SBOM relationships, and source bundle. Automated checks prove
presence and consistency, not a general legal conclusion; document any
non-automatable obligation honestly.

`scripts/check-attribution.py` verifies required exact naming strings, the
pinned complete S1-mini license digest from both official repositories and their
byte equality, the `Apache-2.0 AND LicenseRef-S1-mini-Naming-Clause` SBOM
expression and extracted term, Qwen and llama.cpp license resources,
model/runtime revision agreement, built-app Legal contents, and SBOM/provenance
relationships. Wire it into `local-check.sh`, packaging, and release
verification; removing any required line, file, hash, or license identifier must
make it fail.

### P10 - Local implementation acceptance

On the M2/16 GB floor and development Mac:

- run all deterministic checks;
- build the ad-hoc app with all three model payloads and metallib;
- verify resource sealing and offline operation;
- run semantic, latency, responsiveness, memory, energy, thermal, and soak gates;
- manually exercise ordinary, list, email, non-trigger, disabled-toggle,
  expedite, multiline, unavailable-model, CPU fallback, sleep/wake, and
  user-switch paths.
- run keyboard-only and VoiceOver passes over cleanup settings, onboarding,
  every overlay/fallback state, insertion uncertainty, and the formatted-text-
  ready recovery card;
- manually exercise Terminal, one third-party terminal, the VS Code integrated
  terminal, and one JetBrains integrated terminal, recording the accepted
  embedded-terminal limitation and, in the two classified terminals, the
  explicit Insert Anyway warning/trailing-newline behavior;
- exercise menu-bar Cancel during a deliberately long cleanup and confirm that
  it inserts nothing;
- exercise VoiceOver from the formatted-text-ready announcement through opening
  the menu-bar popover and activating Copy;
- measure expedited restart with a slow destination and confirm the first audio
  sample meets the spike-set bound while any late failed insertion remains
  recoverable under the previous session.

Do not sign for distribution, notarize, tag, upload, or publish during this
phase.

### P11 - Release execution

Only after every gate passes and the user explicitly authorizes a specific
artifact:

- Developer ID sign;
- notarize and staple;
- build DMG;
- generate checksum, SBOM, provenance, source bundle, and attestations;
- publish exact size/hash and disk-space information;
- run end-to-end release verification.

Local ad-hoc DMGs remain labelled unsigned and unnotarized.

## 14. Acceptance criteria

### Directive correctness

- Every normative parser row passes.
- Parser work is O(prefix); it never scans a large transcript to search for a
  later command.
- Parser runs once per final session and zero times per preview.
- Empty command payload never causes deletion.
- Disabled directive words remain ordinary content.
- Session IDs prevent stale parses/results from insertion.
- `DictationSessionID` remains stable from accepted start through insertion and
  is demonstrably distinct from the changing supersede epoch.
- Every runtime failure inserts effective text after a recognized directive and
  original text otherwise, exactly once.
- Whole-session Cancel inserts nothing.

### Prompt and quality

- All twelve prompt token-ID goldens pass.
- Trusted/untrusted seam fidelity passes or any tokenizer-required divergence is
  explicitly pinned and explained.
- Control-looking user text cannot escape its untrusted segment.
- Only EOG-terminated cleaned output is selected.
- A three-item fixture forms a list; non-enumerable list-mode content may remain
  prose; email fixtures preserve meaningful blank-line structure.
- Semantic preserve/must-contain/must-not-contain assertions meet the ratchet on
  CPU and Metal.
- Novel written addresses must be traceable to spoken input.

### UX and insertion

- Final-ASR and cleanup states have distinct copy and timing.
- New press during cleanup acknowledges within one frame and never loses or
  duplicates text.
- No phantom new recording occurs after a released tap.
- Bullets and blank lines survive Accessibility and clipboard insertion.
- No multiline Unicode Return synthesis exists.
- Diagnostic `unicode-first` cannot route a multiline value to Unicode.
- Clipboard-disabled or blocked-terminal multiline text enters a recoverable
  120-second state with Copy/confirmed Insert Anyway/Discard and no lost text.
- Insertion uncertainty causes no automatic second attempt; explicit retry is
  serialized and warns about possible duplication.
- Expedited restart reaches the first audio sample within the spike-set bound
  even with a slow destination; any late failure remains in the previous
  session's pending entry and cannot contaminate the new capture.
- Known terminal destinations never receive automatic multiline paste.
- Confirmed terminal Insert Anyway names command-execution risk and removes
  trailing separators from only the one-shot paste payload.
- Every setting and overlay state has accessible labelling and keyboard access.
- VoiceOver announces cleanup, fallback, uncertainty, and ready-to-copy states.
- The ready-to-copy announcement identifies the menu-bar popover containing its
  controls, and keyboard/VoiceOver can reach Copy before expiry.
- Final overlay publication on the cleanup path matches the selected insertion
  and never republishes the removed command word.
- Whole-session Cancel is visibly reachable during cleaning and inserts nothing.
- Static examples invoke the model zero times; trial invokes it at most once.

### Performance and lifecycle

- Preparation is never on the user-visible critical path.
- Zero Metal pipeline compilations occur during post-warm-up requests.
- Provisional floor targets are p50 <= 0.8 s and p95 <= 1.8 s for up to 40 words;
  the spike replaces these with measured acceptance numbers.
- Shipped deadline is derived from floor-machine p99 with bounded headroom and a
  maximum acceptable user-visible ceiling determined by the spike, proposed no
  higher than 3.0 s for one pass.
- Hotkey, audio start/stop, final Parakeet, overlay, and WindowServer metrics stay
  within recorded promotion guards.
- Expedite-press-to-first-audio-sample p95 with a slow destination is no more
  than 100 ms above the ordinary accepted-start p95 unless the spike sets a
  stricter measured bound.
- No monotonic model/context/task/thread growth; near-zero physical-footprint
  slope; stable 24-hour residency; unload counters return to the measured
  baseline envelope; thermal state does not reach serious during the soak.

### Security, privacy, packaging, and release

- Network-denied model smoke passes.
- Vendored runtime contains no environment steering, runtime shader compile,
  socket/server/RPC/downloader, or dynamic backend path.
- Source scans cover `Vendor/LlamaLocal/**`, and the linked release binary
  passes the existing fail-closed forbidden-string/symbol gate before merge.
- Metallib/model files load only from signed bundle-relative paths.
- Framework and entitlement allowlists match exactly.
- No transcript content appears in logs, defaults, files, or temporary output.
- Exact asset manifests reject corruption, symlinks, siblings, wrong revisions,
  and duplicate payloads.
- Exact app/DMG/model/metallib sizes and hashes are reported; size alone never
  fails the build.
- Attribution checker, built-app Legal resources, SBOM, provenance, source
  bundle, signing, notarization, staple, and release verification all pass.

## 15. Stop rules

Stop and return to the user before promotion if:

- P0 finds that the integrated Parakeet configuration uses the GPU;
- Metal cannot avoid user-visible post-warm-up pipeline compilation;
- Metal fails a responsiveness, WindowServer, energy, thermal, or 24-hour
  stability gate; use CPU as the next candidate and rerun all gates;
- the prefix parser produces a deletion outside the exact grammar;
- multiline output can be submitted/executed through synthesized Return events;
- semantic quality falls below the fixture ratchet;
- a valid transcript is lost or inserted twice in any failure/expedite path;
- transcript content appears in logs or persisted state;
- runtime networking or an unsealed replacement path is found;
- any required license, naming, source, or provenance deliverable is absent or
  inconsistent;
- diagnostic or fallback routing can send multiline content through Unicode;
- insertion failure/uncertainty can clear pending text or permit an automatic
  duplicate attempt;
- an existing user can have a checked but inert cleanup preference without
  being offered the required disclosure;
- expedited restart misses its first-audio promotion guard or clears/reuses a
  previous session's pending entry.

## 16. Residual risks

- With email detection enabled, an utterance deliberately beginning with the
  exact word `email` always selects email mode and removes that word. Clear
  settings copy and an independent checkbox are the mitigation.
- Metal has no public QoS equivalent for protecting WindowServer. Submission
  sizing and hardware gates reduce but do not erase that risk.
- Metallib bytes are reproducible only under the recorded toolchain; source,
  build command, compiler version, and artifact hash make this auditable.
- S1-mini is a small generative model. Semantic fixtures and structural safety
  checks reduce, but cannot eliminate, normalization mistakes.
- Destination applications control paste/newline semantics. Known terminals are
  protected from automatic multiline paste; unknown applications remain a
  documented manual-acceptance risk.
- Bundle-ID classification cannot distinguish embedded terminals from editors
  inside VS Code or JetBrains. V1 documents and manually tests this blind spot
  rather than blocking the entire host application.
- Explicit terminal `Insert Anyway` remains capable of executing pasted lines
  in destinations without reliable bracketed-paste protection. The warning,
  trailing-separator removal, and explicit confirmation reduce accidental use
  but do not make arbitrary multiline terminal paste safe.
- Exact upstream vendoring and Metal hardening create an upgrade patch burden;
  file manifests, patch records, and fail-closed scans make drift visible.

## 17. Definition of done

Implementation is complete only when P0-P10 pass, every spike value is recorded,
the M2/16 GB and development-Mac evidence is attached, all deterministic and
real-model tests pass, the 24-hour diagnostics remain stable, all release inputs
are auditable, and every deviation from this contract is documented.

That does not itself authorize publishing. P11 begins only after a separate,
explicit instruction naming the artifact to release.
