# Model lock

VoxHearth release builds bundle two selectable speech-recognition models and
never fetch either at runtime. The committed manifests lock the multilingual
model to `aed02740059203c4a87495924f685de3722ae9ce` and the compact English model
to `9bc92ead6e8f17eca92a869fd578ae76842b82ba`.

The multilingual model permits these upstream payloads:

- `Preprocessor.mlmodelc`
- `Encoder.mlmodelc`
- `Decoder.mlmodelc`
- `JointDecisionv3.mlmodelc`
- `parakeet_vocab.json`

The manifest records the size and SHA-256 of every file below those paths. For
Git LFS files, the published object ID is the content SHA-256; the remaining
files were downloaded from the pinned revision and hashed directly. The
expected payload is 483,105,645 bytes before app/DMG compression.

The compact English model permits `Preprocessor.mlmodelc`, `Decoder.mlmodelc`,
`JointDecision.mlmodelc`, and `parakeet_vocab.json`; its 16 manifest entries
total 227,466,209 bytes.

Model binaries are build inputs, not source. They belong under `.build/models`
and must never be committed. Fetch and verify them with:

```sh
./scripts/fetch-models.sh
./scripts/verify-model.py .build/models/parakeet-tdt-0.6b-v3-coreml
./scripts/verify-model.py \
  --manifest Models/parakeet-tdt-ctc-110m-coreml.json \
  .build/models/parakeet-tdt-ctc-110m-coreml
```

See [MODEL_PROVENANCE.md](../Documentation/MODEL_PROVENANCE.md) for attribution
and licensing information.
