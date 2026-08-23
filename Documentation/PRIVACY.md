# Privacy

VoxHearth 0.4 turns microphone audio into text on the same Mac and can
optionally clean the final English transcript with S1-mini by Superwhisper.
There is no online mode.

## Runtime data flow

```text
microphone
   │
   ▼
memory-only Float32 audio (maximum 10 minutes)
   │
   ▼
selected bundled Parakeet Core ML model through a network-free FluidAudio subset
   │
   ▼
memory-only transcript
   │
   ├── cleanup disabled or unavailable ───────────────────────────────┐
   │                                                                 │
   ▼                                                                 │
S1-mini by Superwhisper through sealed local llama.cpp/Metal          │
   │                                                                 │
   └──────────────── memory-only selected text ◀─────────────────────┘
   │
   ▼
focused application through Accessibility or Unicode events
```

VoxHearth does not send audio, transcripts, settings, diagnostics, or usage
events to a VoxHearth service. It has no account, analytics SDK, advertising,
crash uploader, cloud transcription endpoint, model downloader, automatic
updater, appcast, or remote configuration.

Build and release machines do use the network to obtain source dependencies and
the pinned model, interact with GitHub, and request Apple notarization. Those
operations are not present in the installed runtime application.

## What is processed or stored

| Data | Processing and lifetime |
| --- | --- |
| Microphone audio | Captured into process memory only, capped at ten minutes per dictation, then released after transcription, cancellation, failure, or process exit. If live preview is enabled, a bounded copy of the most recent audio is periodically passed to the same local model. VoxHearth does not create an audio file. |
| Transcript | Exists in process memory while it is previewed, cleaned, recovered, or inserted. S1-mini receives text only after final English transcription and never receives audio or preview snapshots. The optional preview panel is not a Notification Center notification and creates no notification history. If cleanup or insertion fails, VoxHearth may retain the original/fallback text in memory for a recovery prompt for at most two minutes, then discards it automatically. Quitting or choosing Discard clears it sooner. VoxHearth does not save a transcript history. |
| Preferences | Shortcut, selected microphone identifier, selected speech model, language, launch-at-login choice, live-preview choice, clipboard-fallback choice, cleanup choice/style, list/email prefix choices, and onboarding/disclosure completion. These preferences are stored in macOS UserDefaults for bundle ID `com.stephansturges.voxhearth`. Transcript content is never stored in preferences. |
| Logs | Apple Unified Logging receives fixed operation identifiers and error type names. Log calls cannot accept audio, transcript text, clipboard contents, arbitrary paths, or free-form user text. |
| Models | Three immutable model payloads and one sealed Metal library are read only from the signed application bundle. Only the selected speech model is loaded for ASR. S1-mini may remain resident while enabled to avoid per-session startup cost and is released when cleanup is disabled, after 15 minutes without an active or recoverable session, under memory pressure, or during bounded application termination. Memory-pressure re-preparation is cooled down for five minutes to avoid unload/reload churn. There is no runtime model download, model cache, backend discovery, or runtime shader compilation. |

## Optional transcript cleanup

Cleanup is checked by default only after its setup disclosure is shown. It is
English-only, uses semi-formal style by default, and can be disabled at any
time. Independent default-on settings recognize `list` or `email` only as the
first complete word of a new dictation session. A recognized command is
removed before cleanup and from automatic fallback text. Mentioning either
word later in a dictation does not select a format.

Cleanup adds local model work, memory use, and a short delay after final ASR.
The top overlay reports that work. A new hotkey press can start capture without
waiting for an older cleanup request; results remain session-isolated. Failure,
timeout, cancellation, invalid output, missing assets, or memory pressure falls
back locally and never causes a network request.

The application into which VoxHearth inserts text receives the transcript and
may store, sync, or transmit it under that application's own policy. macOS and
software with sufficient local privileges can inspect process memory or audio;
VoxHearth cannot protect data on a compromised operating system.

## Permissions

VoxHearth requests only:

- **Microphone:** required to capture the dictation you initiate.
- **Accessibility:** required to set selected text or post Unicode keyboard
  events into the focused application.

The global keyboard shortcut uses the macOS Carbon hotkey API. It receives only
the registered shortcut's press/release events; it does not install a general
keyboard event tap or record other keystrokes. If you explicitly bind a middle
or extra mouse/accessory button, VoxHearth additionally monitors only macOS
`otherMouseDown` and `otherMouseUp` events and discards every button number
except the one you selected. It does not observe pointer movement, scrolling,
or primary/secondary clicks.

Launch at login is optional and off by default. It uses macOS
`SMAppService.mainApp`; it does not install a privileged helper.

## Live transcript overlay

Live preview is optional and off by default. When enabled, VoxHearth
periodically re-transcribes at most the latest eight seconds of the active
in-memory recording and presents the newest ten recognized words in a passive,
single-line top-right panel. Older words drop from the left. The panel does not
take keyboard focus, write a notification, or become
the source used for insertion. After recording stops, VoxHearth separately
transcribes the complete recording and inserts only that final result. Preview
text clears on cancellation and shortly after completion.

The overlay makes dictated text visible on screen. People nearby, screen-sharing
software, screenshots, or other software able to capture the display may see
it. It requests another preview after a 600 ms pause, although model inference
time determines the actual cadence. This can increase energy use and may slow
final transcription on a smaller Mac. Leave it disabled when display privacy
or minimum resource use is more important than immediate feedback.

## Clipboard compatibility

Clipboard fallback is off by default. When enabled, VoxHearth uses it only if
the Accessibility and Unicode-event insertion methods fail. It snapshots every
pasteboard item, writes the transcript, posts Command-V, and restores the prior
clipboard after a short delay if nothing else has changed it.

Clipboard managers, Universal Clipboard, the destination app, or another local
process can observe the temporary transcript before restoration. Leave this
setting disabled if that is unacceptable. If another process changes the
clipboard during insertion, VoxHearth preserves the newer value rather than
overwriting it with the snapshot.

## Removing local state

Quit VoxHearth to release in-memory audio, text, and loaded model state. To
remove preferences:

```sh
defaults delete com.stephansturges.voxhearth
```

Disable “Launch VoxHearth at login” before deleting the app. Microphone and
Accessibility grants can be reviewed or revoked in System Settings → Privacy &
Security → Accessibility. VoxHearth Settings includes a direct button to this
pane. After replacing VoxHearth with a new build, macOS may retain the previous
build's record; remove the old VoxHearth entry with −, add the current
`/Applications/VoxHearth.app` with +, enable it, then quit and reopen VoxHearth.
Quit the old VoxHearth process before replacing the app so the new build can
actually launch. VoxHearth invokes only Apple's permission prompt, Finder, and
System Settings. macOS does not expose an API that lets an app add or approve
itself in Accessibility, and VoxHearth never edits the TCC database directly.

## Verification and changes

The source-level offline contract and signed release checks are described in
[THREAT_MODEL.md](THREAT_MODEL.md) and [VERIFY_RELEASE.md](VERIFY_RELEASE.md).
Changes that add any runtime networking, content logging, history, or remote
update behavior require an explicit privacy review and a prominent update to
this document before release.

Report a suspected privacy or security defect privately as described in
[SECURITY.md](../SECURITY.md).
