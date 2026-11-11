# Changelog

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
