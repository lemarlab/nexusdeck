import SwiftUI
import ServiceManagement

struct SettingsWindow: View {
    @EnvironmentObject var ui: UIState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Impostazioni").font(.system(size: 15, weight: .bold))
                        .padding(.leading, 16).frame(height: 56, alignment: .center)
                    ForEach(SettingsPage.allCases) { p in
                        let on = ui.settingsPage == p
                        Button { ui.settingsPage = p } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 6).fill(p.tint)
                                    .frame(width: 24, height: 24)
                                    .overlay(Image(systemName: p.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white))
                                Text(p.title).font(.system(size: 13, weight: on ? .medium : .regular)).foregroundStyle(on ? Color.white : Theme.text)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).frame(height: 34)
                            .background(on ? Theme.accent : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(width: 244)
                .background(VisualEffect(material: .sidebar))
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        let p = ui.settingsPage ?? .general
                        RoundedRectangle(cornerRadius: 7).fill(p.tint).frame(width: 28, height: 28)
                            .overlay(Image(systemName: p.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))
                        Text(p.title).font(.system(size: 17, weight: .bold))
                        Spacer()
                    }
                    .padding(.horizontal, 28).frame(height: 60)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) { page }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack { Spacer(); FlatButton(title: "Fine", prominent: true, width: 90) { dismiss() } }
                        .padding(.horizontal, 20).frame(height: 56)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
                }
                .background(Theme.canvas)
            }
        }
        .frame(width: 900, height: 680)
        .background(Theme.settingsBg)
        .foregroundStyle(Theme.text)
        
    }

    @ViewBuilder private var page: some View {
        switch ui.settingsPage ?? .general {
        case .general: GeneralPage()
        case .audioOutput: OutputPage()
        case .obs: OBSPage()
        case .streamlabs: StreamlabsPage()
        case .linkApps: LinkAppsPage()
        case .customLighting: CustomLightingPage()
        case .interactiveLighting: InteractiveLightingPage()
        case .backup: BackupPage()
        case .guide: GuidePage()
        case .feedback: FeedbackPage()
        }
    }
}

/// "Label  [control]  (i)" row used in settings cards.
struct SettingRow<C: View>: View {
    let title: LocalizedStringKey
    var info: String? = nil
    var labelWidth: CGFloat = 92
    @ViewBuilder var content: C
    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13))
            if let info { InfoIcon(text: info) }
            Spacer(minLength: 12)
            content
        }
    }
}

struct InfoIcon: View {
    let text: String
    @State private var show = false
    var body: some View {
        Button { show.toggle() } label: { Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Theme.textFaint) }
            .buttonStyle(.plain)
            .popover(isPresented: $show) { Text(text).font(.system(size: 12)).padding(12).frame(width: 260) }
    }
}

/// Ten fixed color swatches used by lighting and background settings.
struct SwatchRow: View {
    @Binding var hex: String
    var first: String = "#FF0000"
    static let colors = ["#FF0000", "#FF8C00", "#00FF00", "#00FF8C", "#00FFFF", "#008CFF", "#0000FF", "#8C00FF", "#FF00FF", "#FF6EFF"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach([first] + Self.colors.dropFirst(first == Self.colors[0] ? 1 : 1).map { $0 }, id: \.self) { c in
                Circle().fill(Color(hex: c)).frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                    .padding(3)
                    .overlay(Circle().strokeBorder(hex.uppercased() == c.uppercased() ? Theme.accent : .clear, lineWidth: 2))
                    .onTapGesture { hex = c }
            }
        }
    }
}
