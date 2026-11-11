# Changelog

## 0.5.0 — 2026-11-11

### Novità
- Nuovo LEDManager unico: stato desiderato/inviato, invio solo delle differenze, coda ordinata; reassert dopo reset firmware e keep-alive.
- Anello del microfono gestito dal firmware come gli altri LED (niente più spegnimenti/lampeggi).
- Tracce OBS sempre attive: selezionare "[AM-IN] Chat Mic" per catturare la voce con effetti in OBS/Discord.
- [AM-IN] Line In: percorso duplicato rimosso, livello calibrato (+7.5 dB) con limitatore trasparente.
- Voicemod rientra nel mix Chat per ascoltarsi in cuffia.
- Mix Audience usato solo internamente per il Line In.
- Include il fix 0.4.0: routing audio per applicazione nel driver.

### Correzioni
- Gain microfono corretto: prima ~2× troppo alto, ora 1 dB = 1 passo come Creator Central → molto meno fruscio.
- Registro monitor 0x22 = 0x12/0x31 secondo il protocollo verificato.
- La voce con effetti (riduzione rumore, de-esser, taglio bassi) non rientra più in cuffia tramite il mix Chat: si usa il monitor nativo.
- ScreamGuard non usa più il mute del microfono ma abbassa la voce elaborata.
- Nessuna scrittura HID ridondante sulla manopola del microfono (cache dei registri).
- Mute = solo mute dell'utente.

### Miglioramenti
- LED: invio solo delle differenze, coda ordinata, nessun lampeggio dell'anello mic.
- Audio: tracce OBS sempre attive senza opzione; Line In calibrato con limitatore trasparente.

### Rimosso
- Dual Mix; selettore Creator/Audience; colonna "Diretta"; "Solo in diretta"; uscita Line Out "Audience Mix"; opzione tracce OBS (ora sempre attive).
- Profili vecchi caricati senza perdita del mix Creator.

### Note
- Per gli effetti in OBS/Discord selezionare "[AM-IN] Chat Mic".
- Il gain del microfono va reimpostato: i valori ora corrispondono ai dB reali.
