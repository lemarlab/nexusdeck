import SwiftUI

// MARK: - Widget import

struct ImportWindow: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deck: DeckController
    @EnvironmentObject var audio: AudioService
    @ObservedObject private var pm = PackageManager.shared
    @State private var message: String?
    @State private var report: LegacyImporter.Report?
    @State private var targeted = false

    var body: some View {
        ModalFrame(title: "Importa widget", width: 720, height: 620) {
            VStack(alignment: .leading, spacing: 18) {
                SectionCard(title: "Pacchetti widget e profili") {
                    VStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 36)).foregroundStyle(Theme.accent)
                        Text("Trascina qui un pacchetto widget (.creatorCentral) o un profilo (.nexusprofile)").font(.system(size: 13)).foregroundStyle(Theme.textMid)
                        FlatButton(title: "Scegli file…", width: 130) {
                            let p = NSOpenPanel(); p.allowsMultipleSelection = true
                            if p.runModal() == .OK { importFiles(p.urls) }
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 150)
                    .background(Theme.field)
                    .overlay(Rectangle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundStyle(targeted ? Theme.accent : Theme.textDim))
                    .dropDestination(for: URL.self) { urls, _ in importFiles(urls); return true } isTargeted: { targeted = $0 }
                }
                SectionCard(title: "Importa da Creator Central") {
                    Text("Importa profili tasti (con le proprietà di ogni tasto e widget), profili mixer, effetti microfono, luci e schermo dall'app originale.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textMid)
                    HStack {
                        FlatButton(title: "Importa ora", width: 130) { runLegacy(LegacyImporter.defaultFolder) }
                        FlatButton(title: "Scegli cartella…", width: 140) {
                            let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
                            if p.runModal() == .OK, let u = p.url { runLegacy(u) }
                        }
                    }
                    if let r = report {
                        Text("Importati: \(r.hotkeyProfiles) profili tasti (\(r.keys) tasti), \(r.mixerProfiles) profili mixer, \(r.dspProfiles) profili microfono.")
                            .font(.system(size: 12.5))
                        if !r.missingPackages.isEmpty {
                            Text("Widget di pacchetti non installati: \(r.missingPackages.sorted().joined(separator: ", "))").font(.system(size: 12)).foregroundStyle(Theme.accent)
                            FlatButton(title: "Installa pacchetti mancanti", width: 220) { installMissing(r.missingPackages) }
                        }
                        if !r.unknownActions.isEmpty {
                            Text("Azioni non supportate: \(r.unknownActions.sorted().joined(separator: ", "))").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                        }
                    }
                }
                if let message { Text(message).font(.system(size: 12.5)).foregroundStyle(Theme.textMid) }
                if !pm.installing.isEmpty { ProgressView("Installazione pacchetti…").controlSize(.small) }
            }
            .padding(20)
        }
    }

    private func runLegacy(_ folder: URL) {
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("AxHotkeyProfiles.plist").path)
                || FileManager.default.fileExists(atPath: folder.appendingPathComponent("AxMixerProfiles.plist").path) else {
            message = "Nessun profilo di Creator Central trovato in \(folder.path)"
            return
        }
        report = LegacyImporter.run(folder: folder, into: store)
        deck.profileChanged()
        audio.applyAll()
    }

    private func installMissing(_ ids: Set<String>) {
        for id in ids {
            if let c = PackageManager.catalog.first(where: { id.hasPrefix($0.id) || $0.id.hasPrefix(id) }) {
                Task { await pm.install(from: c.url); deck.needsRedraw.send() }
            }
        }
    }

    private func importFiles(_ urls: [URL]) {
        var ok = 0
        for u in urls {
            if u.pathExtension.lowercased() == "creatorcentral" { Task { await pm.install(from: u) }; ok += 1 }
            else if (try? store.importProfile(from: u)) != nil { ok += 1 }
        }
        message = "Importati \(ok) di \(urls.count) file."
    }
}
