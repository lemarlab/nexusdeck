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

// MARK: - Audio routing table

struct RoutingTableWindow: View {
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        ModalFrame(title: store.mixer.dualMix ? "Tabella di routing audio - Dual Mix" : "Tabella di routing audio - Single Mix", width: 940, height: 560) {
            RoutingGraph(dual: store.mixer.dualMix).padding(20)
        }
    }
}

private struct RoutingGraph: View {
    let dual: Bool
    @EnvironmentObject var store: ProfileStore

    private let rowY: [CGFloat] = [40, 110, 170, 230, 290, 350]
    private let orange = Color(hex: "#F39A1E")

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                func curve(_ a: CGPoint, _ b: CGPoint, _ c: Color) {
                    var p = Path()
                    p.move(to: a)
                    p.addCurve(to: b, control1: CGPoint(x: (a.x + b.x) / 2, y: a.y), control2: CGPoint(x: (a.x + b.x) / 2, y: b.y))
                    ctx.stroke(p, with: .color(c), lineWidth: 1.5)
                }
                let creator = CGPoint(x: 470, y: dual ? 150 : 200)
                let audience = CGPoint(x: 470, y: 290)
                for y in rowY {
                    curve(CGPoint(x: 330, y: y + 14), CGPoint(x: 440, y: creator.y), orange)
                    if dual { curve(CGPoint(x: 330, y: y + 14), CGPoint(x: 440, y: audience.y), Color.white.opacity(0.6)) }
                }
                curve(CGPoint(x: 330, y: rowY[0] + 14), CGPoint(x: 700, y: 40 + 14), Color(hex: "#2F8CFF"))
                let mixOut = CGPoint(x: 520, y: creator.y)
                curve(mixOut, CGPoint(x: 560, y: 210), orange)
                curve(CGPoint(x: 610, y: 210), CGPoint(x: 700, y: 180 + 14), orange)
                curve(CGPoint(x: 610, y: 210), CGPoint(x: 700, y: 250 + 14), orange)
                let lineOutSrc = dual ? CGPoint(x: 520, y: audience.y) : mixOut
                curve(lineOutSrc, CGPoint(x: 700, y: 110 + 14), .white)
                curve(dual ? CGPoint(x: 520, y: audience.y) : mixOut, CGPoint(x: 700, y: 320 + 14), .white)
            }
            // Inputs
            ForEach(Array(MixerChannel.allCases.enumerated()), id: \.offset) { i, ch in
                node(store.mixer.name(ch), symbol: store.mixer.channelIcons[ch.rawValue] != nil ? store.mixer.symbol(ch) : (ch == .mic ? "mic.fill" : ch.columnSymbol)).offset(x: 0, y: rowY[i])
                fader(store.mixer.mixes[.creator]?.channels[ch]?.level ?? 0).offset(x: 230, y: rowY[i])
            }
            node("Guadagno", text: "\(store.mixer.currentGainDB) dB").offset(x: 75, y: rowY[0])
            node("Effetti", symbol: "waveform").offset(x: 150, y: rowY[0])
            label("Mic con effetti").offset(x: 560, y: rowY[0])
            node(dual ? "Creator Mix" : "Master Mix", symbol: "person.crop.circle", highlight: true).offset(x: 440, y: (dual ? 150 : 200) - 20)
            if dual { node("Audience Mix", symbol: "speaker.wave.2.circle").offset(x: 440, y: 270) }
            node("Monitor", symbol: "headphones").offset(x: 560, y: 190)
            // Outputs
            output("Chat Mic", y: 40)
            output("Line Out", y: 110, level: store.library.device.lineOutVolume)
            output("Cuffie", y: 180, level: store.library.device.headphonesVolume)
            output("Dispositivo Creator Mix", y: 250)
            output("Dispositivo Audience Mix", y: 320)
        }
        .frame(width: 900, height: 420, alignment: .topLeading)
    }

    private func node(_ t: String, symbol: String? = nil, text: String? = nil, highlight: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(t).font(.system(size: 9, weight: .semibold)).foregroundStyle(highlight ? orange : Theme.textDim)
                .frame(maxWidth: .infinity).padding(.vertical, 2).background(Color(hex: "#3A3A3A"))
            if let symbol { Image(systemName: symbol).font(.system(size: 14)) }
            if let text { Text(text).font(.system(size: 10, weight: .bold)).foregroundStyle(orange) }
        }
        .frame(width: 66, height: 44)
        .background(Color(hex: "#2B2B2B"))
        .overlay(Rectangle().strokeBorder(Color.white.opacity(0.1)))
    }

    private func fader(_ level: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 9))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black).frame(width: 50, height: 3)
                Capsule().fill(orange).frame(width: 50 * CGFloat(level) / 100, height: 3)
            }
            Circle().fill(orange).frame(width: 6, height: 6)
        }
        .padding(6).frame(width: 100, height: 28).background(Color(hex: "#2B2B2B"))
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 10)).foregroundStyle(orange).padding(6).background(Color(hex: "#2B2B2B"))
    }

    private func output(_ t: String, y: CGFloat, level: Int? = nil) -> some View {
        VStack(spacing: 4) {
            Text(t).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.vertical, 2).background(Color(hex: "#3A3A3A"))
            if let level {
                HStack {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 9))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black).frame(width: 90, height: 3)
                        Capsule().fill(orange).frame(width: 90 * CGFloat(level) / 100, height: 3)
                    }
                }
            } else {
                Image(systemName: "desktopcomputer").font(.system(size: 13))
            }
        }
        .frame(width: 180, height: 44)
        .background(Color(hex: "#2B2B2B"))
        .offset(x: 700, y: y)
    }
}
