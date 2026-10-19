import SwiftUI

struct ActionLibraryView: View {
    @State private var search = ""
    @State private var expanded: Set<String> = Set(ActionCatalog.categories.map(\.id))

    var body: some View {
        VStack(spacing: 0) {
            TextField("Cerca azioni", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            List {
                ForEach(ActionCatalog.categories) { cat in
                    let items = cat.actions.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
                    if !items.isEmpty {
                        DisclosureGroup(isExpanded: Binding(get: { expanded.contains(cat.id) || !search.isEmpty }, set: { if $0 { expanded.insert(cat.id) } else { expanded.remove(cat.id) } })) {
                            ForEach(items) { a in
                                HStack {
                                    Image(systemName: a.symbol).frame(width: 22)
                                    Text(a.title)
                                    Spacer()
                                    if a.kind == .widget { Text("\(a.width)×\(a.height)").font(.caption2).foregroundStyle(.secondary) }
                                    if a.kind == .knob { Image(systemName: "dial.low").font(.caption).foregroundStyle(.secondary) }
                                }
                                .contentShape(Rectangle())
                                .draggable(a.id) {
                                    Label(a.title, systemImage: a.symbol).padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        } label: {
                            Label(cat.title, systemImage: cat.symbol).font(.headline)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

struct KnobRowView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var editor: DeckEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Manopole").font(.headline)
                Picker("", selection: Binding(get: { store.knob.id }, set: { store.library.activeKnobProfile = $0 })) {
                    ForEach(store.library.knobProfiles) { Text($0.title).tag($0.id) }
                }
                .frame(maxWidth: 220)
                Button { var p = KnobProfile(title: "Profilo manopole \(store.library.knobProfiles.count + 1)"); p.id = UUID(); store.library.knobProfiles.append(p); store.library.activeKnobProfile = p.id } label: { Image(systemName: "plus") }
                Spacer()
                Text("Clicca una manopola per configurarne l'azione.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                ForEach(0..<6, id: \.self) { i in
                    let a = store.knob.knobs[i]
                    let channel = MixerChannel.allCases[i]
                    let level = store.mixer.mixes[store.mixer.activeMix]?.channels[channel]?.level ?? 0
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(Color(white: 0.12))
                            Circle().trim(from: 0, to: CGFloat(level) / 100 * 0.75)
                                .rotation(.degrees(135))
                                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .padding(4)
                            Image(systemName: a.actionID.map { ActionCatalog.descriptor($0).symbol } ?? channel.symbol)
                                .foregroundStyle(.white)
                        }
                        .frame(width: 58, height: 58)
                        .overlay(Circle().strokeBorder(editor.selectedKnob == i ? Color.accentColor : .clear, lineWidth: 3))
                        .onTapGesture { editor.selectedKnob = i; editor.selectedKey = nil }
                        .dropDestination(for: String.self) { items, _ in
                            guard let id = items.first, ActionCatalog.descriptor(id).kind == .knob else { return false }
                            store.knob.knobs[i].actionID = id
                            editor.selectedKnob = i
                            return true
                        }
                        Text(a.actionID.map { ActionCatalog.descriptor($0).title } ?? channel.title)
                            .font(.caption2).lineLimit(1).frame(width: 90)
                    }
                }
            }
        }
    }
}
