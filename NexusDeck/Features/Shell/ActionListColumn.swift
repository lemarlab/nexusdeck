import SwiftUI

/// Colored tile used for actions in the list and as default key art.
struct ActionTile: View {
    let descriptor: ActionDescriptor
    var width: CGFloat = 50
    var height: CGFloat = 36

    var body: some View {
        if let f = descriptor.iconFile, let img = ImageCache.image(atPath: f) {
            Image(nsImage: img).resizable().scaledToFit().frame(width: width, height: height).background(Color.black)
        } else {
            VStack(spacing: 1) {
                Image(systemName: descriptor.symbol).font(.system(size: height * 0.36, weight: .medium))
                Text(descriptor.tileLabel).font(.system(size: max(7, height * 0.235), weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(.white)
            .frame(width: width, height: height)
            .background(Theme.tileColor(for: descriptor.id))
        }
    }
}

extension ActionDescriptor {
    /// Short label printed inside the tile (like "Monitor", "Switch", "Page").
    var tileLabel: String {
        let words = title.split(separator: " ")
        if title.count <= 10 { return title }
        return String(words.last ?? Substring(title)).prefix(10).description
    }
}

struct ActionListColumn: View {
    @State private var collapsed: Set<String> = []
    @State private var search = ""
    @ObservedObject private var packages = PackageManager.shared
    // Re-render when built-in integrations are switched on or off.
    @AppStorage(BuiltInIntegration.discord.defaultsKey) private var discordOn = false

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                TextField("Cerca azioni e widget", text: $search).textFieldStyle(.plain).font(.system(size: 12.5))
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textFaint) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(Theme.field).clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ActionCatalog.allCategories) { cat in
                        let items = cat.actions.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || cat.title.localizedCaseInsensitiveContains(search) }
                        if !items.isEmpty {
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    if collapsed.contains(cat.id) { collapsed.remove(cat.id) } else { collapsed.insert(cat.id) }
                                }
                            } label: {
                                HStack {
                                    Text(cat.title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.5)
                                    Spacer()
                                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                                        .rotationEffect(.degrees(collapsed.contains(cat.id) && search.isEmpty ? -90 : 0))
                                }
                                .foregroundStyle(Theme.textFaint)
                                .padding(.horizontal, 4).frame(height: 26)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
                            if !collapsed.contains(cat.id) || !search.isEmpty {
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(items) { ActionRow(descriptor: $0) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 16)
            }
            .scrollIndicators(.automatic)
        }
    }
}

/// Library card: rounded icon and name; drag it onto the panel, a function key or a knob.
struct ActionRow: View {
    let descriptor: ActionDescriptor
    @EnvironmentObject var editor: DeckEditorModel
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ActionIcon(descriptor: descriptor, size: 28)
            Text(descriptor.title).font(.system(size: 11.5)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if descriptor.kind == .knob || descriptor.width > 1 || descriptor.height > 1 {
                Text(descriptor.kind == .knob ? "Manopola" : "\(descriptor.width) × \(descriptor.height)")
                    .font(.system(size: 10)).foregroundStyle(Theme.textFaint)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
        .help(descriptor.title)
        .onDrag {
            let d = descriptor
            editor.dragInfo = .init(w: d.kind == .knob ? 1 : d.width, h: d.kind == .knob ? 1 : d.height, ignoring: nil)
            return NSItemProvider(object: d.id as NSString)
        } preview: {
            // Exactly the key that will land on the panel.
            KeyDragPreview(key: KeyAssignment(actionID: descriptor.id, w: descriptor.kind == .knob ? 1 : descriptor.width,
                                              h: descriptor.kind == .knob ? 1 : descriptor.height,
                                              states: ActionCatalog.defaultStates(for: descriptor)))
        }
    }
}

/// Rounded square icon of an action, in its family colour.
struct ActionIcon: View {
    let descriptor: ActionDescriptor
    var size: CGFloat = 28
    var body: some View {
        Group {
            if let f = descriptor.iconFile, let img = ImageCache.image(atPath: f) {
                Image(nsImage: img).resizable().scaledToFit().background(Color.black)
            } else {
                let hex = Theme.tileHex(for: descriptor.id)
                LinearGradient(colors: [Color(hex: Theme.lighten(hex, 0.15)), Color(hex: hex)], startPoint: .top, endPoint: .bottom)
                    .overlay(Image(systemName: descriptor.symbol).font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}
