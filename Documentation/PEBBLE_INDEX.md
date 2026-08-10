# Pebble Index 01 direct-local integration

Status: the safe VoxHearth audio-ingress path is implemented. Discovery,
pairing, and collection transfer are not shipped yet because the public Pebble
code does not currently include the transfer protocol or a macOS library.

## Intended experience

```text
hold Index button -> ring records -> release -> BLE collection transfer
    -> bounded PCM in memory -> bundled Parakeet -> Accessibility insertion
```

The ring should pair directly with the Mac. VoxHearth must not use a phone,
webhook, MCP server, loopback server, cloud account, or network relay. Ring
audio must enter `DictationController.submitExternalAudio(_:)`, which uses the
existing local model and insertion path without opening the Mac microphone.

This is collection transfer, not a generic keyboard shortcut. Index 01 records
with its own microphone and stores the recording until a companion retrieves
it. A normal capture therefore completes after button release and BLE transfer;
it is not a live Bluetooth microphone stream.

Pebble documents a roughly two-minute limit per recording and about five
minutes of storage on the ring. Queued audio is therefore durable on the ring
even though VoxHearth will keep its Mac-side copy in memory only. The device can
overwrite its oldest queued message when full, so deletion/acknowledgement
behavior is part of the privacy and reliability boundary.

## Confirmed public interface

The official Pebble mobile app currently:

- scans for BLE service `607B5C9B-3700-4E94-F44A-2DF900BCB0C3`;
- initiates iOS bonding by writing byte `00`, with response, to characteristic
  `DAAD3D52-237C-90A7-B54B-8854A134D801`;
- receives completed collections as signed 16-bit PCM plus sample rate, button
  sequence, collection indexes, release timestamp, and contiguity metadata;
- represents gesture components as `short` and `long`; and
- treats the ring as already paired elsewhere when a new bond is rejected.

Sources:

- <https://github.com/coredevices/mobileapp>
- `libindex/.../RealScanning.kt`
- `libindex/.../IndexPairing.ios.kt`
- `experimental/.../RingSync.kt`
- <https://help.repebble.com/en/articles/15434751-index-01-getting-started-guide>

## Current upstream gap

The public mobile application delegates framing, collection retrieval,
acknowledgement, retransmission, and PCM assembly to the separately published
`io.github.coredevices.haversine:haversine` artifact. At the revision used by
the app (`f801265`):

- its advertised source repository is unavailable;
- its source archives contain only an empty manifest;
- published native targets are iOS arm64 and iOS Simulator arm64, not macOS;
- the common artifact pulls in Ktor networking dependencies; and
- the compiled library also contains firmware-update behavior that VoxHearth
  must not import.

Consequently, importing that artifact would neither build a native macOS app
nor meet VoxHearth's auditable, zero-runtime-network dependency policy.
Guessing packet commands risks erasing queued recordings, corrupting collection
state, or producing a driver that works only accidentally.

The clean unblock is for Core Devices to publish either the Haversine source,
a protocol specification, or a network-free macOS transport target. A focused
request should ask for the GATT characteristic roles, Telesto framing and
commands, collection acknowledgement/deletion semantics, retry rules, sample
format, advertisement layout, and bonding/security properties.

## Driver design once unblocked

The implementation should be a small Swift `CoreBluetooth` actor owned by the
app, with no executable plug-in or helper process:

1. Scan only for the confirmed Index service.
2. Show discovered identifier, advertised name, and signal strength; require an
   explicit user selection before pairing.
3. Save only the selected CoreBluetooth peripheral identifier and a display
   label in preferences. Never trust a device name as identity.
4. On every connection, require the exact service and characteristic allowlist
   and trigger macOS-managed bonding with a write-with-response.
5. Accept collections only from the selected peripheral. Reject malformed,
   missing, duplicate, out-of-order, oversized, or non-contiguous transfers.
6. Cap an Index capture at its published two-minute limit, 16-bit mono PCM, and
   a small fixed protocol overhead before allocating buffers. The generic core
   ingress independently rejects audio longer than ten minutes.
7. Convert the completed PCM to `CapturedAudio` in memory and call
   `submitExternalAudio(_:)`. Do not create an audio file, database row, log
   payload, or transcript history.
8. Acknowledge or delete a ring collection only after its integrity is
   established and VoxHearth has accepted it. Exact device-side deletion
   semantics must be confirmed first.
9. Release transport and audio buffers after acceptance, failure, cancellation,
   disconnect, or quit.
10. Keep firmware updating entirely out of VoxHearth.

The settings UI should have an off-by-default **Pebble Index 01** section with
Pair, Forget, connection state, battery/firmware information only if locally
available, and a clear warning when the ring is bonded to another host.
Enabling it will require `NSBluetoothAlwaysUsageDescription` in the final app
bundle. Microphone permission should not be required for ring-sourced audio;
Accessibility remains required for insertion.

## Security and hardware acceptance

Before calling this supported, test on a physical retail ring and a clean Mac:

- initial pair, user-cancelled pair, wrong device, and already-bonded behavior;
- reconnect after app restart, Mac restart, Bluetooth toggle, sleep, and range
  loss;
- single-click-hold and double-click-hold recordings;
- empty, sub-second, maximum-length, interrupted, duplicate, missing, corrupt,
  rollover, and out-of-order collections;
- two rings nearby and an attempted peripheral-identifier substitution;
- no DNS/TCP/UDP during scanning, pairing, transfer, transcription, idle, or
  reconnect;
- no audio/transcript artifacts in app containers, logs, temporary paths, or
  crash recovery; and
- the ring's behavior after successful transfer, failed transfer, forgetting,
  and re-pairing, including whether acknowledged audio remains on the ring.

Bluetooth LE link encryption and the exact pairing association model must be
verified on hardware. The current public iOS code triggers operating-system
bonding but does not by itself prove authenticated pairing or resistance to an
active nearby attacker.
