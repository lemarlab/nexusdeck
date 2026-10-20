import SwiftUI
import ServiceManagement

// MARK: General

struct GeneralPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var devices: DeviceManager
    @EnvironmentObject var bridge: AudioBridge
    @AppStorage("closeMinimizes") private var closeMinimizes = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        SectionCard(title: "Dispositivo") {
            info("Mixer", deviceName)
            info("Account", "Nessun account richiesto")
        }
        SectionCard(title: "Versione software") {
            info("Applicazione", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            info("Firmware", firmware)
            #if DEBUG
            // Test only: simulates an update to the next version (shows the panel animation, the mixer is not touched).
            if firmware != "—" && !DeviceSession.firmwareTestDone {
                HStack {
                    Text("Aggiornamento firmware (test)").font(.system(size: 13))
                    Spacer()
                    Text("Disponibile \(Self.nextVersion(firmware))").font(.system(size: 13)).foregroundStyle(Theme.accent)
                    FlatButton(title: "Aggiorna", prominent: true, width: 100) {
                        DistributedNotificationCenter.default().postNotificationName(Notification.Name("NexusDeck.firmwareDemo"), object: Self.nextVersion(firmware), userInfo: nil, deliverImmediately: true)
                    }
                }
            }
            #endif
            HStack {
                Text("Driver audio").font(.system(size: 13))
                Spacer()
                Text(!bridge.isPlugInInstalled ? "non installato" : bridge.isPlugInOutdated ? "da aggiornare" : "aggiornato")
                    .font(.system(size: 13)).foregroundStyle(bridge.isPlugInOutdated || !bridge.isPlugInInstalled ? Color.orange : Theme.textDim)
                FlatButton(title: !bridge.isPlugInInstalled ? "Installa driver" : bridge.isPlugInOutdated ? "Aggiorna driver" : "Reinstalla driver", width: 140) { _ = bridge.installPlugIn() }
            }
            Text("© 2026 NexusDeck. Non affiliato ad AVerMedia.").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
        }
        SectionCard(title: "Aggiornamenti") {
            UpdateRow()
        }
        SectionCard(title: "Lingua") {
            HStack {
                DarkPicker(selection: .constant("it"), options: [("it", "Italiano"), ("en", "English (United States)")], height: 28).frame(width: 280)
                Spacer()
                FlatButton(title: "Applica", width: 130) {}
            }
        }
        SectionCard(title: "Display del mixer") {
            HStack {
                Text("Animazione cambio pagina sul mixer").font(.system(size: 13))
                InfoIcon(text: "Sperimentale: quando cambi pagina, il display del mixer mostra alcune immagini intermedie della pagina che scorre. Il display aggiorna circa 8 immagini al secondo, quindi l'effetto è a scatti.")
                Spacer()
                PillToggle(isOn: $store.library.device.pageAnimation)
            }
        }
        SectionCard(title: "Impostazioni della finestra") {
            Text("Il pulsante di chiusura (X):").font(.system(size: 13)).foregroundStyle(Theme.textMid)
            HStack(spacing: 60) {
                radio("Riduci a icona", closeMinimizes) { closeMinimizes = true }
                radio("Chiudi applicazione", !closeMinimizes) { closeMinimizes = false }
            }
            HStack(spacing: 10) {
                PillToggle(isOn: Binding(get: { launchAtLogin }, set: { on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; launchAtLogin = on } catch {}
                }))
                Text("Avvia al login").font(.system(size: 13)).foregroundStyle(Theme.textMid)
                Spacer().frame(width: 40)
                if KeySynth.hasAccessibility {
                    Text("Accessibilità concessa").font(.system(size: 12)).foregroundStyle(.green)
                } else {
                    FlatButton(title: "Concedi Accessibilità", width: 170) { KeySynth.requestAccessibility() }
                }
            }
            .padding(.top, 6)
        }
    }

    private var deviceName: String {
        if case .connected(let i) = devices.state { return i.productName }
        return "Nessun dispositivo collegato"
    }

    static func nextVersion(_ v: String) -> String {
        var p = v.split(separator: ".").map { Int($0) ?? 0 }
        if !p.isEmpty { p[p.count - 1] += 1 }
        return p.map(String.init).joined(separator: ".")
    }

    private var firmware: String {
        if case .connected(let i) = devices.state, !i.firmwareVersion.isEmpty { return i.firmwareVersion }
        return "—"
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack(spacing: 20) {
            Text(k).font(.system(size: 13))
            Spacer()
            Text(v).font(.system(size: 13)).foregroundStyle(Theme.textDim)
        }
    }
}

struct UpdateRow: View {
    @ObservedObject var updater = Updater.shared
    @State private var showNotes = false

    var body: some View {
        HStack(spacing: 12) {
            switch updater.state {
            case .idle: Text("Controlla se è disponibile una nuova versione su GitHub.").foregroundStyle(Theme.textMid)
            case .checking: ProgressView().controlSize(.small); Text("Controllo in corso…").foregroundStyle(Theme.textMid)
            case .upToDate: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("NexusDeck è aggiornato.").foregroundStyle(Theme.textMid)
            case .available(let v): Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent); Text("Disponibile la versione \(v)").bold()
            case .downloading: ProgressView().controlSize(.small); Text("Download in corso…").foregroundStyle(Theme.textMid)
            case .installing: ProgressView().controlSize(.small); Text("Installazione… NexusDeck si riavvierà.").foregroundStyle(Theme.textMid)
            case .failed(let e): Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(e).foregroundStyle(Theme.textMid).lineLimit(2)
            }
            Spacer()
            if case .available = updater.state {
                FlatButton(title: "Novità e aggiorna…", width: 170) { showNotes = true }
            } else {
                FlatButton(title: "Controlla aggiornamenti", width: 190) { Task { await updater.check(); if updater.latestVersion != nil { showNotes = true } } }
                    .disabled(updater.state == .checking || updater.state == .downloading || updater.state == .installing)
            }
        }
        .font(.system(size: 13))
        HStack(spacing: 12) {
            Text("Controllo automatico:").font(.system(size: 13)).foregroundStyle(Theme.textMid)
            DarkPicker(selection: $updater.frequency, options: Updater.Frequency.allCases.map { ($0, $0.title) }, height: 26).frame(width: 200)
            Spacer()
        }
        .sheet(isPresented: $showNotes) { UpdateSheet() }
    }
}

func radio(_ title: LocalizedStringKey, _ on: Bool, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 14) {
            Circle().fill(Theme.field).overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: 1)).frame(width: 16, height: 16)
                .overlay(Circle().fill(Theme.accent).frame(width: 6, height: 6).opacity(on ? 1 : 0))
            Text(title).font(.system(size: 13)).foregroundStyle(Theme.textMid)
        }
    }
    .buttonStyle(.plain)
}
