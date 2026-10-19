import SwiftUI

/// Colored tile used for actions in the list and as default key art.
struct ActionTile: View {
    let descriptor: ActionDescriptor
    var width: CGFloat = 50
    var height: CGFloat = 36

    var body: some View {
        if let f = descriptor.iconFile, let img = NSImage(contentsOfFile: f) {
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
    @ObservedObject private var packages = PackageManager.shared
    // Re-render when built-in integrations are switched on or off.
    @AppStorage(BuiltInIntegration.discord.defaultsKey) private var discordOn = false
    @AppStorage(BuiltInIntegration.voicemod.defaultsKey) private var voicemodOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tasti e widget").font(.system(size: 14, weight: .bold))
                .padding(.leading, 12).frame(height: 38, alignment: .leading)
            Rectangle().fill(Theme.separator.opacity(0.5)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ActionCatalog.allCategories) { cat in
                        Button {
                            if collapsed.contains(cat.id) { collapsed.remove(cat.id) } else { collapsed.insert(cat.id) }
                        } label: {
                            HStack(spacing: 16) {
                                Text(collapsed.contains(cat.id) ? "+" : "—").font(.system(size: 12, weight: .bold)).frame(width: 12)
                                Text(cat.title).font(.system(size: 12, weight: .bold))
                                Spacer()
                            }
                            .foregroundStyle(Theme.textMid)
                            .padding(.horizontal, 10).frame(height: 34)
                            .background(Theme.columnHeader)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 4)
                        if !collapsed.contains(cat.id) {
                            ForEach(cat.actions) { ActionRow(descriptor: $0) }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.visible)
        }
    }
}

struct ActionRow: View {
    let descriptor: ActionDescriptor
    @EnvironmentObject var editor: DeckEditorModel
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ActionTile(descriptor: descriptor)
            VStack(alignment: .leading, spacing: 4) {
                Text(descriptor.title).font(.system(size: 12.5)).foregroundStyle(Theme.textMid)
                Text(descriptor.kind == .knob ? "manopola" : "\(descriptor.width) x \(descriptor.height)")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textMid)
            }
            .padding(.top, 2)
            Spacer()
        }
        .padding(.leading, 28).frame(height: 52)
        .background(hover ? Color.white.opacity(0.04) : .clear)
        .onHover { hover = $0 }
        .onDrag {
            let d = descriptor
            editor.dragInfo = .init(w: d.kind == .knob ? 1 : d.width, h: d.kind == .knob ? 1 : d.height, ignoring: nil)
            return NSItemProvider(object: d.id as NSString)
        } preview: {
            ActionTile(descriptor: descriptor, width: 75 * CGFloat(descriptor.width), height: 54 * CGFloat(descriptor.height))
                .overlay(Rectangle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        }
    }
}
