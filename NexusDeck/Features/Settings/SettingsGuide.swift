import SwiftUI
import ServiceManagement

// MARK: Guide / Feedback

struct GuidePage: View {
    @EnvironmentObject var store: ProfileStore
    private let items = ["Organizza il pannello di controllo", "Personalizza i widget", "Controlli a due stati", "Impostazioni microfono", "Effetti microfono",
                         "Prova il Dual Mix", "Barra laterale", "Tabella di routing audio", "Dimensioni della finestra", "Modifica del testo",
                         "Installazione dei widget", "Profilo tasti consigliato"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlatButton(title: "Riproduci tutto", width: 130) { store.library.tutorialDone = false }
            HStack {
                Text("Elenco guide").font(.system(size: 14)).foregroundStyle(Theme.textDim)
                Spacer()
                Text("Riproduci").font(.system(size: 14)).foregroundStyle(Theme.textDim).frame(width: 120)
            }
            .padding(.top, 30).padding(.bottom, 20)
            ForEach(items, id: \.self) { t in
                HStack {
                    Text(t).font(.system(size: 13.5)).foregroundStyle(Theme.textMid)
                    Spacer()
                    Button { store.library.tutorialDone = false } label: { Image(systemName: "play.circle").font(.system(size: 16)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.textDim).frame(width: 120)
                }
                .frame(height: 40)
            }
        }
        .padding(20)
        .background(Theme.card)
    }
}

struct FeedbackPage: View {
    @EnvironmentObject var devices: DeviceManager
    @State private var text = ""
    @State private var copied = false

    var body: some View {
        SectionCard(title: "Aiuto e suggerimenti") {
            Text("Descrivi il problema o il suggerimento. Le informazioni di sistema vengono aggiunte al testo copiato.")
                .font(.system(size: 13)).foregroundStyle(Theme.textMid)
            TextEditor(text: $text).font(.system(size: 13)).scrollContentBackground(.hidden).background(Theme.field).frame(height: 180)
            HStack {
                FlatButton(title: "Copia negli appunti", width: 170) {
                    var info = "NexusDeck \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
                    if case .connected(let d) = devices.state { info += "\(d.productName) firmware \(d.firmwareVersion)\n" }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(info + "\n" + text, forType: .string)
                    copied = true
                }
                if copied { Text("Copiato").font(.system(size: 12)).foregroundStyle(.green) }
            }
        }
    }
}
