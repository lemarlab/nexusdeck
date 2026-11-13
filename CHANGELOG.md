# Changelog

## 0.6.2 — 2026-11-13

### Changed
- Audio device names: inputs now start with ● (e.g. "● Chat Mic"), outputs with ▶ (e.g. "▶ System"), replacing "[AM-IN]" / "[AM-OUT]". Only display names changed: device IDs, routing and settings are untouched, so OBS/Discord keep their selections.

### Notes
- The new names appear after the updated audio driver is installed. The driver (NexusDeckAudio.driver) is bundled inside the app (Contents/Resources); the app installs or updates it in /Library/Audio/Plug-Ins/HAL from General settings (administrator password required) and restarts coreaudiod. Ad-hoc signed, not notarized: first launch via right-click → Open.

## 0.6.1 — 2026-11-12

### Fixed
- [AM-IN] Chat Mic was silent in 0.6.0 on some mixers: with mix sync off, the Chat Mic mix kept a stale (zero) mic level. The app now writes the Chat Mic mix (mic only) explicitly.
- Mic voice no longer leaks into [AM-IN] Line In in any state: register 0x22 is always 0x00 (no mix sync). Turning the headphone monitor off previously re-enabled sync and copied the mic into the Line In bus for ~2 s.
- The mic knob controls the [AM-IN] Chat Mic level again (applied in software, smoothed, no extra writes to the mixer), including the processed-voice path.

### Improved
- Monitor off is done by muting the mic in the Creator mix only; the Line In and Chat Mic buses are never touched.
- [AM-IN] Line In: OBS compensation reduced from +7.5 dB to +2.5 dB and the soft-knee limiter threshold raised to −0.5 dBFS, so the track keeps headroom at full knob.
- The app re-checks the Line In and Chat Mic bus levels after connect, settings changes and mic knob turns, and repairs them only if needed.

### Verified
- Guided hardware test (register read-back + audio levels) on the dev Mac: voice, Line In, mic knob, Line In knob, mic mute, all knobs/mutes, monitor on/off, voice FX, Voicemod, USB reconnect.

### Notes
- Ad-hoc signed, not notarized: first launch via right-click → Open.

## 0.6.0 — 2026-11-11

### Fixed
- The mic no longer leaks into [AM-IN] Line In. Root cause: register 0x22 (mic monitor routing | mix sync) was set to 0x12 in 0.5.0, enabling mix sync — the firmware copied the Creator mic level into the Audience bus that feeds Line In. Now 0x00 (monitor via Creator, no sync); monitor off still 0x31.
- The mic knob now changes your own voice level in the headphone monitor again.
- On connect, mix sync is disabled before the Audience bus levels are written, and the app re-checks that the Audience mic is 0 (after connect and after mic knob turns), re-sending only if needed.

## 0.5.0 — 2026-11-11

### New
- Single LEDManager: desired vs sent state, diff-only, ordered queue; keeps keys/strip/ring colours.
- OBS tracks always on — use "[AM-IN] Chat Mic" to capture processed voice in OBS/Discord.
- Voicemod voice returns to the Chat mix for headphone monitoring.
- CHANGELOG.

### Fixed
- Mic preamp gain was ~2× too high (now 1 dB per step, matching Creator Central) → far less hiss.
- Mic knob ring no longer turns off/flashes (firmware owns all knob rings, no redundant HID writes on knob turns, register write cache).
- Monitor routing register 0x22 now 0x12/0x31 per verified protocol.
- Processed voice (noise reduction, de-esser, low cut) no longer leaks into headphones via the Chat mix — native monitor is used.
- [AM-IN] Line In duplicate route removed and level calibrated (+7.5 dB) with transparent soft-knee limiter.
- Per-app audio routing fix from 0.4.0 included.

### Improved
- Mute bits reflect only user mutes.
- ScreamGuard attenuates the processed voice instead of muting the mic.
- Audience mix used internally as a Line-In-only bus.
- Knob control unlinked early on connect.

### Removed
- Dual Mix, Creator/Audience switch, "Live" routing column, "Live only" ducking, "Audience Mix" Line Out source, OBS tracks toggle. Old profiles load without losing the Creator mix.

### Notes
- Re-set your mic gain (values now match real dB).
- DMG is ad-hoc signed, not notarized — first launch via right-click → Open.
