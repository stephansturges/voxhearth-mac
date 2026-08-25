# S1-mini deterministic number canonicalization

Status: approved, implemented, and verified for `v0.4.0-dev.9` against the
2026-08-25 contract.

## Intent

Successful English S1-mini cleanup receives one deterministic finalization
pass. Safe spoken cardinal integers greater than ten become ungrouped digits;
supported currency words become suffix symbols. The pass also normalizes
canonical grouped integers and explicit supported numeric currency forms so
model-produced formatting and residual spoken forms converge on the same style.

Examples:

- `seven thousand and twelve dollars` -> `7012$`
- `one hundred and five euros` -> `105€`
- `$7,012` -> `7012$`
- `1,200 euros` -> `1200€`
- `seven thousand pounds` -> `7000 pounds`

## Frozen behavior

- Eligible values are exact integers from 11 through 1,000,000,000,000.
- Output uses ungrouped ASCII digits.
- `dollar`/`dollars`, `euro`/`euros`, and `yen` map to suffix `$`, `€`, and
  `¥`. `pounds` remains a word.
- Plain ungrouped non-currency digits are unchanged. Canonically grouped
  integers and supported numeric currency forms are restyled.
- Zero through ten, decimals, cents, fractions, dates, years, ordinals,
  negatives, phone numbers, addresses, identifiers, malformed grouping,
  URLs, email addresses, inline code, and fenced code are unchanged. The sole
  malformed-grouping exception is source-anchored repair of one model-produced
  numeric slot described below.
- At most four spoken-number parses may run. More eligible windows makes the
  complete pass an identity operation; it never partially normalizes a long
  numeric list.
- The feature is automatic whenever English cleanup succeeds. There is no
  preference or additional disclosure because it introduces no model,
  dependency, network, storage, or background execution.

## Runtime contract

`SpokenNumberCanonicalizer` owns one Foundation `NumberFormatter` fixed to
`en_US_POSIX`, `.spellOut`, and non-lenient parsing. It is deliberately
non-Sendable and lives only inside the existing serial S1 queue. Construction
and four compatibility probes occur during existing model preparation.
Unexpected Foundation behavior permanently disables that instance and leaves
all text unchanged.

Candidate discovery is a bounded scalar/token scan, not a general natural-
language parser. A candidate must:

1. begin and end on complete number-word boundaries;
2. contain only the fixed English number lexicon, safe internal hyphens, and
   properly surrounded `and` connectors;
3. avoid protected ranges and semantic neighbors such as `point`, ordinals,
   percent, cents, fractions, and negative markers;
4. be consumed completely by Foundation without prefix retry or backtracking;
5. reverse-spell to the same normalized word sequence;
6. produce an exact in-range integer.

Canonicalization runs exactly once after accepted single-pass validation or
after joined chunk output passes aggregate validation. Changed output is run
through the same allowed-scalar, prompt-leak, growth, repetition, and protected-
content checks used by model validation. Failure selects the already-validated
model text; it never creates a recovery outcome or returns raw dictation.

Real-model observation found that S1-mini can turn a correct spoken integer
into incorrect digits while still passing the general cleanup validator (for
example, `seven thousand and twelve dollars` became `$7,12`). Therefore, when
the accepted output contains exactly one unprotected, non-decimal numeric slot
and the original effective transcript contains exactly one supported spoken-
integer candidate with the same currency kind, the spoken source is the numeric
authority. The finalizer replaces that one slot with the Foundation-parsed
source value. The output slot must also be non-year, non-identifier, non-address,
non-time, non-percent, non-zero-padded, and within two digit edits of the source
value. It does not reconcile multiple numeric slots or spoken windows,
mismatched currency, protected text, decimals, or any shape that exceeds the
same four-parse cap.
This remains part of the single accepted-output pass and does not modify model
input, prompts, fallbacks, or raw dictation.

Accepted residual: if the cleanup model deletes the intended number entirely
and leaves one different bare numeric slot within two digit edits, the narrow
one-slot rule cannot prove semantic correspondence. V1 accepts that bounded
risk rather than adding a general alignment parser; multiple slots and all
guarded contexts still remain unchanged.

## Acceptance

- Adversarial unit coverage includes partial prefixes, digit sequences, years,
  dates, ordinals, decimals, fractions, cents, negatives, malformed grouping,
  identifiers, protected ranges, overflow, repeated execution, and the work
  cap.
- Integration coverage proves one finalizer call for both single and chunked
  output, source-anchored repair of observed S1 digit drift, and zero calls for
  disabled or invalid cleanup.
- The opt-in microbenchmark requires p99 canonicalization latency at or below
  25 ms and exposes only content-free timing.
- The real S1 CPU and Metal evaluator requires all 16 fixtures, deterministic
  repeats, network-denied and hostile-environment parity, and the existing
  latency/RSS/thread/model-load ratchets without relaxation.
- VoxHearthCore source changes require regeneration of the lifecycle evaluator
  lock and the complete local policy/build gate.

M2/16 GB performance-floor acceptance remains distinct from development-host
verification and must never be inferred from a faster machine.
