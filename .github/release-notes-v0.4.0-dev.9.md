# VoxHearth 0.4.0 Development Preview 9

This unsigned preview adds deterministic local number canonicalization to the
optional English S1-mini cleanup path. It retains the setup-window crash fix,
stable menu height, and long-running lifecycle improvements from Preview 8.

## What changed

- Safe spoken cardinal integers greater than ten are rendered as ungrouped
  digits after successful cleanup. For example, `seven thousand and twelve`
  becomes `7012`.
- Dollars, euros, and yen use compact suffix symbols, so `seven thousand and
  twelve dollars` becomes `7012$`. Pounds remain written as a word.
- Canonically grouped model output such as `$7,012` is normalized to the same
  `7012$` style.
- A narrow source-anchored safeguard repairs one compatible numeric slot when
  S1-mini changes the speaker's number. Multiple or ambiguous numeric slots,
  dates, years, decimals, identifiers, addresses, percentages, code, and other
  protected forms remain unchanged.
- The pass runs exactly once after accepted English cleanup. Disabled cleanup,
  unsupported languages, cancellation, deadlines, validation failures, and all
  existing fallback paths retain their previous behavior.
- The implementation uses Foundation inside the existing serial cleanup queue.
  It adds no model, dependency, setting, network access, storage, background
  worker, prompt change, or telemetry.

The feature remains English-only. An M2 with 16 GB RAM is the documented
performance floor, but this specific change was verified on an M5 Max with
128 GB RAM; that host evidence does not replace floor-hardware acceptance.

## Verification performed

- 188 Swift tests, including adversarial parsing, protected-content,
  source-alignment, work-cap, and exactly-once integration regressions
- a 500-sample opt-in microbenchmark: 0.131 ms p50 and 0.291 ms p99 on the
  development host, below the fixed 25 ms p99 limit
- debug and release builds plus release-binary and offline-policy checks
- real local Parakeet model smoke coverage
- real S1-mini CPU and Metal evaluation across 16 fixtures with deterministic
  repeats, network denial, hostile-environment parity, and unchanged latency,
  memory, thread, and model-load ratchets
- strict ad-hoc bundle signature, DMG, checksum, provenance, SBOM, and
  attestation verification in the release workflow

## Install this unsigned development preview

1. Quit the currently running VoxHearth before replacing it.
2. Download `VoxHearth-v0.4.0-dev.9-unsigned.dmg` and `SHA256SUMS` from this
   release and verify the checksum.
3. Open the DMG and drag VoxHearth to Applications, replacing the older build.
4. This preview is ad-hoc signed and not notarized. Follow the per-app **Open
   Anyway** procedure in `Documentation/VERIFY_RELEASE.md`; never disable
   Gatekeeper globally.
5. Enable transcript cleanup and try phrases containing an unambiguous spoken
   whole number, with and without a supported currency.

Source revision: `{{SOURCE_REVISION}}`

The workflow publishes the complete three-model DMG, sealed Metal library,
source archive, SPDX SBOM, provenance record, checksums, and GitHub attestations.
