import SwiftUI

/// "Instradamento app": choose the mixer channel each app plays on (like Loopback / SoundSource).
struct AppRoutingPage: View {
    @EnvironmentObject var router: AppAudioRouter
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Instradamento app").font(.system(size: 14, weight: .bold))
                Spacer()
                Button { router.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13)).foregroundStyle(Theme.textDim)
                }
                .buttonStyle(.plain).help("Aggiorna elenco")
            }
            .padding(.horizontal, 24).frame(height: 38)
            Rectangle().fill(Theme.separator.opacity(0.5)).frame(height: 1)
            Text("Scegli su quale canale del mixer suona ogni app. Il volume lo regola la manopola di quel canale. \"Predefinito\" lascia l'app sulla sua uscita normale.")
                .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                .padding(.horizontal, 24).padding(.vertical, 12)
            if let e = router.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(e).font(.system(size: 12))
                    Button("Apri Privacy") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 10)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { app in
                        row(app)
                        Rectangle().fill(Theme.separator.opacity(0.35)).frame(height: 1)
                    }
                    if rows.isEmpty {
                        Text("Nessuna app sta usando l'audio. Avvia la riproduzione in un'app e comparirà qui.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textDim).padding(30)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Running audio apps plus routed apps that are closed (their route is kept).
    private var rows: [AppAudioRouter.AudioApp] {
        var list = router.apps
        let known = Set(list.map(\.bundleID))
        for bid in store.library.appRoutes.keys.sorted() where !known.contains(bid) {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
            let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bid
            list.append(.init(bundleID: bid, name: name, icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) }, playing: false))
        }
        return list
    }

    private func row(_ app: AppAudioRouter.AudioApp) -> some View {
        let running = router.apps.contains { $0.bundleID == app.bundleID }
        let options: [(String, String)] = [("", "Predefinito")] + AppAudioRouter.channels.map { ($0.0.rawValue, store.mixer.name($0.0)) }
        return HStack(spacing: 14) {
            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 30, height: 30) }
            else { Image(systemName: "app").font(.system(size: 22)).frame(width: 30, height: 30) }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.system(size: 13, weight: .bold))
                Text(!running ? "Non in esecuzione" : app.playing ? "In riproduzione" : "In silenzio")
                    .font(.system(size: 11)).foregroundStyle(app.playing ? Theme.accent : Theme.textDim)
            }
            Spacer()
            DarkPicker(selection: Binding(get: { store.library.appRoutes[app.bundleID] ?? "" },
                                          set: { router.setRoute(app.bundleID, $0.isEmpty ? nil : $0) }),
                       options: options, height: 28)
                .frame(width: 200)
        }
        .frame(height: 56)
    }
}
