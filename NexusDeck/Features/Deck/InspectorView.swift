import SwiftUI
import UniformTypeIdentifiers

struct KnobInspector: View {
    let index: Int
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        let channel = MixerChannel.allCases[index]
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Manopola \(index + 1)", systemImage: "dial.medium").font(.headline)
                Spacer()
                if store.knob.knobs[index].actionID != nil {
                    Button("Ripristina canale mixer") { store.knob.knobs[index].actionID = nil; store.knob.knobs[index].settings = [:] }
                }
            }
            DropdownRowField(title: "Funzione", selection: Binding(get: { store.knob.knobs[index].actionID ?? "" }, set: { store.knob.knobs[index].actionID = $0.isEmpty ? nil : $0 }),
                             options: [("", "Canale mixer: \(channel.title)")] + ActionCatalog.categories.flatMap(\.actions).filter { $0.kind == .knob }.map { ($0.id, $0.title) })
            .frame(maxWidth: 420)
            if let id = store.knob.knobs[index].actionID {
                KnobSettingsView(actionID: id, settings: Binding(get: { store.knob.knobs[index].settings }, set: { store.knob.knobs[index].settings = $0 }))
            } else {
                Text("Ruota: volume del canale \(channel.title) nel mix attivo. Premi: muto.").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }
}
