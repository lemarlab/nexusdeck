# NexusDeck

App nativa per macOS (Swift/SwiftUI) per controllare il mixer/stream deck **AX310**, senza bisogno di software aggiuntivo.

> NexusDeck è un progetto indipendente e **non è affiliato, approvato o supportato da AVerMedia**. "AX310" è citato solo per indicare l'hardware compatibile.

## Requisiti

- Mac con **Apple Silicon** (M1 o successivi)
- **macOS 14** o successivo
- Mixer AX310 collegato via USB

## Funzioni principali

- Tasti e widget sul pannello touch, pagine, cartelle, multi-azione
- Mixer audio: Single/Dual Mix, volumi, muti, monitor del microfono, misuratori
- Microfono: guadagno, 48V, noise gate, compressore, equalizzatore, eco, riverbero, voice changer
- Strumenti mixer: matrice di instradamento, modalità di muto, tasto tosse, bip di censura, ducking, nomi dei canali
- **Instradamento app**: manda l'audio di ogni app (es. Spotify) su un canale del mixer (System, Game, Chat…)
- Illuminazione di tasti, manopole e striscia LED
- Integrazioni: OBS, Streamlabs Desktop, Twitch, YouTube, Spotify, Discord, Voicemod
- Importazione dei profili da un'installazione esistente del software del produttore

## Installazione

1. Scarica `NexusDeck-x.y.z.dmg` dalla pagina [Releases](../../releases).
2. Apri il DMG e trascina **NexusDeck** in **Applicazioni**.
3. Al primo avvio macOS potrebbe bloccare l'app perché non è firmata da uno sviluppatore registrato:
   - **Impostazioni di Sistema → Privacy e sicurezza → "Apri comunque"**, oppure
   - da Terminale: `xattr -cr /Applications/NexusDeck.app`
4. In NexusDeck apri **Impostazioni → Uscita audio** e installa il **driver audio NexusDeck** (richiede la password di amministratore). Crea i dispositivi System, Game, Chat, Line In, Console, Creator Mix, Audience Mix e Chat Mic.
5. Imposta **System** come uscita audio del Mac.

## Compilare dal codice sorgente

Serve Xcode 16 o successivo.

```sh
xcodebuild -project NexusDeck.xcodeproj -scheme NexusDeck -configuration Release -derivedDataPath build build
```

Il driver audio (`AudioPlugin/`) viene compilato automaticamente durante la build dell'app.

Per creare il DMG:

```sh
./scripts/make-dmg.sh
```

## Licenza

Copyright © 2026 lemarlab. Tutti i diritti riservati.
Il codice è pubblicato per consultazione; non è concessa alcuna licenza di riutilizzo, modifica o ridistribuzione senza autorizzazione.
