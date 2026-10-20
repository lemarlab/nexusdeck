# NexusDeck

A native macOS app (Swift/SwiftUI) to control the **AX310** mixer / stream deck, with no additional software required.

> NexusDeck is an independent project and is **not affiliated with, endorsed or supported by AVerMedia**. "AX310" is mentioned only to identify the compatible hardware.

## Requirements

- Mac with **Apple Silicon** (M1 or later)
- **macOS 14** or later
- AX310 mixer connected via USB

## Features

- Keys and widgets on the touch panel, pages, folders, multi-actions
- Audio mixer: Single/Dual Mix, volumes, mutes, mic monitoring, level meters
- Microphone: gain, 48V phantom power, noise gate, compressor, equalizer, echo, reverb
- Lighting for keys, knobs and LED strip
- Integrations: OBS, Streamlabs Desktop, Twitch, YouTube, Spotify, Discord, Voicemod
- Import of profiles from an existing installation of the manufacturer's software

## New in NexusDeck (not available in the original software)

- **Per-app audio routing**: send any app (e.g. Spotify, Chrome, Discord) to a mixer channel (System, Game, Chat, Line In, Console) and control it with that channel's knob. Routing happens inside the NexusDeck audio driver: no extra latency, no screen/audio-recording permission, and changes apply instantly while audio is playing.
- **Interactive routing matrix**: choose, for every source, whether it goes to your headphones, to the stream and (for the mic) to chat, e.g. music in your headphones but not on stream.
- **Mic mute modes**: mute the mic everywhere, only on stream, or only in chat (Chat Mic), from the Mic knob or a key.
- **Cough key**: hold a key to mute the mic, release to unmute.
- **Censor bleep**: hold a key to mute the mic and play a bleep (1 kHz tone or your own sound).
- **Auto ducking**: music and game are lowered automatically while you speak, with smooth fade out / fade in (adjustable threshold, reduction, release, fade times and channels).
- **Voice effect presets**: one key toggles a combination of reverb, echo and the hardware voice changer.
- **Separate tracks for OBS**: every channel (System, Game, Chat, Line In, Console) is also available as an input device, so in OBS each source can go to its own audio track (e.g. music live but not in the VOD). The physical Line In can be captured on its own too.
- **Only the devices you use**: Creator/Audience Mix and the OBS inputs appear on the Mac only when Dual Mix / OBS tracks are on. Devices are labelled `[AM-OUT]` (outputs) and `[AM-IN]` (inputs).
- **Custom channel names and icons**: rename a channel (e.g. "Music" instead of System) and pick its icon; the Mac devices are renamed too.
- **Built-in updates**: NexusDeck checks GitHub for new versions and updates itself.
- **Noise gate calibration**: one click measures your room noise and sets the threshold.
- **Native Discord and Voicemod integrations**: built in and switched on/off, no plug-ins to download.
- **Native Apple Silicon app**, no Intel/Rosetta components.

## Installation

1. Download `NexusDeck-x.y.z.dmg` from the [Releases](../../releases) page.
2. Open the DMG and drag **NexusDeck** into **Applications**.
3. On first launch macOS may block the app because it is not signed by a registered developer:
   - **System Settings → Privacy & Security → "Open Anyway"**, or
   - from Terminal: `xattr -cr /Applications/NexusDeck.app`
4. In NexusDeck open **Settings → Audio output** ("Impostazioni → Uscita audio") and install the **NexusDeck audio driver** (administrator password required). It creates the System, Game, Chat, Line In, Console, Creator Mix, Audience Mix and Chat Mic devices.
5. Set **System** as the Mac's sound output.

> The app interface is currently in Italian.

## Building from source

Requires Xcode 16 or later.

```sh
xcodebuild -project NexusDeck.xcodeproj -scheme NexusDeck -configuration Release -derivedDataPath build build
```

The audio driver (`AudioPlugin/`) is built automatically as part of the app build.

## Credits

- Studio microphone icon by [Icons8](https://icons8.com).

## License

Copyright © 2026 lemarlab. All rights reserved.
The source code is published for reference only; no license is granted to use, modify or redistribute it without permission.
