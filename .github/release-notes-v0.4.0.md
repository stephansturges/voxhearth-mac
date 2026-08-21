# VoxHearth 0.4.0

VoxHearth 0.4.0 adds optional, fully local transcript cleanup with S1-mini by
Superwhisper. It is disclosed and checked during setup, defaults to semi-formal
style, includes raw-versus-cleaned examples, and remains independently
switchable.

Session-leading `list` and `email` commands can select the model's trained list
and email formats. The command is recognized only as the first complete word
of that session and is removed from cleanup and fallback output. Cleanup has a
bounded deadline, typed session isolation, safe fallback/recovery, and visible
overlay progress.

The S1-mini GGUF and sealed llama.cpp Metal library are bundled and
hash-verified. The installed app has no account, telemetry, updater, runtime
networking, model download, dynamic backend discovery, or runtime shader
compilation. The release contains the complete S1-mini naming license,
Qwen3-0.6B and llama.cpp attribution, source, SBOM, and provenance.

Cleanup is English-only and uses additional local memory and compute. Users can
disable it at any time; dictation then follows the existing direct insertion
path.

Download `VoxHearth-v0.4.0.dmg`, verify `SHA256SUMS`, open the disk image, and
drag VoxHearth to Applications. This official artifact is Developer ID signed,
notarized, and stapled by Apple.

Apple Team ID: `{{APPLE_TEAM_ID}}`

Source revision: `{{SOURCE_REVISION}}`
