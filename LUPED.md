# Luped Pebble transport

The optional Luped transport sends Loop's stored glucose history to the Luped
watchface. It uses the watchface app UUID
`bf32924c-4839-449e-9e56-ee190249acb2` and its AppMessage `DATA` schema.

## How it reaches the watch

Loop publishes its own PebbleOS PPoGATT ("Pebble Protocol over GATT") service
with CoreBluetooth (`LupedPebbleTransport.swift`). The watch stays paired with
and connected to the Pebble app, which keeps its own session for
notifications, PebbleKit JS and other watchfaces. PebbleOS discovers Loop's
service on the same Bluetooth connection, reads the app UUID from its meta
characteristic, and opens a second session that carries only Luped
AppMessages.

The legacy PebbleKit iOS SDK is not used: its watch discovery does not
recognize Core Devices watches (Pebble Time 2, Pebble Round 2, Pebble 2 Duo),
so it never reports a connected watch.

## Enable

This is an opt-in proof of concept. Without the step below, Loop builds are
unchanged: the transport source compiles to nothing and no background mode is
added.

1. Add `LUPED_PEBBLE` to the Features line in `LoopConfigOverride.xcconfig`:

   ```
   SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) ... LUPED_PEBBLE
   ```
2. Pair the watch with the Pebble app and select the Luped watchface.

The "Luped Background Mode" build phase (`Scripts/luped-background-mode.sh`) adds the
`bluetooth-peripheral` background mode the GATT service needs, only when
`LUPED_PEBBLE` is set.

## Settings

Pebble is a device in Settings → Devices (shown only when `LUPED_PEBBLE` is
set), like the pump and CGM. It is not set up by default: **Add Smartwatch**
starts the transport, and **Delete Pebble** (with confirmation) stops it,
which ends the watch session, releases the Bluetooth peripheral manager, stops
building payloads, resets the Pebble settings and clears the log.

Settings → Devices → Pebble:

- **Status**: link state (Bluetooth unavailable, waiting for the watch,
  connecting, connected, paused), the last delivered reading with its round
  trip, and the next retry. **Send Now** pushes the current reading
  immediately.
- **Display → Full-Screen Ring** (off by default): `DATA` index 13; a large
  glucose ring with the reading time inside it instead of the ring and trend
  graph.
- **Alarms → Watch Alarms** (on by default): watch vibration using Loop's
  active glucose alert profile; **Glucose Alert Settings** opens Loop's alert
  screen. Off sends the alarm mask as `0`, which also silences Luped's
  stale-data buzz; Loop's own alerts are unaffected.
- **Diagnostics**: battery and counters from Luped's diagnostics snapshot
  (`COMMAND: "diagnostics"`), fetched only when **Refresh Watch Info** is
  tapped, and the **Communication Log**: every event between Loop and the
  watch since Loop started (session setup, handshakes, pushes with a decode of
  every field, the watch's ACK/NACK with round trip, refresh requests,
  retries, settings changes), newest first. The last 500 entries are kept in
  memory; Share exports them as text. Alloy disables a watchface's outbox
  whenever Loop's session opens or closes, so if Luped has not messaged Loop
  since the session opened, Loop first restarts it over the app run-state
  endpoint (0x34: STOP, then RUN 1.5 s later); the fresh Luped's ready
  handshake re-enables its outbox, and the request follows. This switches the
  watch to Luped if another face was active.
- **Advanced → Watchface UUID** (default Luped CGM,
  `bf32924c-4839-449e-9e56-ee190249acb2`): the app UUID Loop's service and
  AppMessages use. Changing it republishes the service, and the watch opens a
  session for the new UUID. The watchface must use Luped's AppMessage keys and
  must not use PebbleKit JS.

The settings are stored in standard user defaults (`lupedPebbleEnabled`,
`lupedPebbleAlarmsEnabled`, `lupedPebbleFullScreen`, `lupedPebbleWatchfaceUUID`)
and apply within half a second.

## Delivery behavior

After Loop successfully persists CGM samples, it sends the latest 12 CGM
readings from the last two hours (user-entered and display-only samples are
excluded), current value, delta, trend direction, display unit, and sample
timestamp. The trend uses the CGM's reported trend when available, otherwise it
is computed from the last two readings. Delta and computed trend are zero/flat
when those readings are more than 15 minutes apart.

The latest payload is always retained. A new watch session and Luped's startup
`refresh` command re-send it. A failed or rejected send (for example while
another watchface is active) is retried after 30 s, 1, 2, 4 and 5 minutes.
If none is accepted, Loop pauses sending, including new readings, until
Luped starts (its startup handshake), a new session opens, or Send Now is
tapped; a newer
reading that arrives while a send is in flight is sent as soon as that send
completes. Values are rounded to the watchface's display precision (one
decimal for mmol/L) and sent in Loop's display unit, re-sent when it changes.

When Luped starts, Alloy sends a ready handshake (AppMessage key 15025) and
keeps the watchface's outbox closed until the phone replies with any message.
Loop answers it, and Luped's following `refresh` command, with the latest
reading.

On each session Loop answers PebbleOS's phone-version request with the 8 KiB
AppMessage capability. Without it, PebbleOS gives Luped a 144-byte inbox; the
watch caches the capability per app and applies it the next time Luped starts.

Only watchfaces without PebbleKit JS can use this session. PebbleOS routes
messages from JavaScript-enabled apps, such as CrimsonBear, to the Pebble app
instead.

Luped vibration alarms are currently disabled. The threshold values in the
protocol are display-only defaults (55/80/200 mg/dL, converted for mmol/L);
they are not Loop therapy settings.
