# Model lock

VoxHearth release builds bundle one speech-recognition model and never fetch a
model at runtime. The committed manifest
[`parakeet-tdt-0.6b-v3-coreml.json`](parakeet-tdt-0.6b-v3-coreml.json) locks the
model to the immutable Hugging Face revision
`aed02740059203c4a87495924f685de3722ae9ce`.

Only these upstream payloads are permitted in the app:

- `Preprocessor.mlmodelc`
- `Encoder.mlmodelc`
- `Decoder.mlmodelc`
- `JointDecisionv3.mlmodelc`
- `parakeet_vocab.json`

The manifest records the size and SHA-256 of every file below those paths. For
Git LFS files, the published object ID is the content SHA-256; the remaining
files were downloaded from the pinned revision and hashed directly. The
expected payload is 483,105,645 bytes before app/DMG compression.

Model binaries are build inputs, not source. They belong under `.build/models`
and must never be committed. Fetch and verify them with:

```sh
./scripts/fetch-model.sh
./scripts/verify-model.py .build/models/parakeet-tdt-0.6b-v3-coreml
```

See [MODEL_PROVENANCE.md](../Documentation/MODEL_PROVENANCE.md) for attribution
and licensing information.
