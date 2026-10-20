import SwiftUI
import ServiceManagement

// MARK: Interactive lighting

/// Live / recording lights on the ambient strip (OBS / Streamlabs).
struct InteractiveLightingPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var engine: ActionEngine

    private func dev<T>(_ kp: WritableKeyPath<DeviceSettings, T>) -> Binding<T> {
        Binding(get: { store.library.device[keyPath: kp] }, set: { store.library.device[keyPath: kp] = $0; engine.syncStates() })
    }

    var body: some View {
        let d = store.library.device
        VStack(alignment: .leading, spacing: 6) {
            SectionCard(title: "Effetto interattivo") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Segnala diretta e registrazione").font(.system(size: 13))
                        Text("Durante una diretta o una registrazione (OBS / Streamlabs) la striscia LED cambia colore.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    PillToggle(isOn: dev(\.interactiveLighting))
                }
                HStack {
                    Text("Se sono attive entrambe, mostra").font(.system(size: 13))
                    Spacer()
                    DarkPicker(selection: dev(\.streamFirst), options: [(true, "La diretta"), (false, "La registrazione")]).frame(width: 180)
                }
            }
            VStack(alignment: .leading, spacing: 18) {
                lightCard("In diretta", "dot.radiowaves.left.and.right", "#FF3B30", dev(\.ledStream), reset: DeviceSettings().ledStream)
                lightCard("In registrazione", "record.circle", "#0A84FF", dev(\.ledRecord), reset: DeviceSettings().ledRecord)
            }
            .padding(.top, 12)
            .opacity(d.interactiveLighting ? 1 : 0.45)
            .allowsHitTesting(d.interactiveLighting)
        }
    }

    private func lightCard(_ t: LocalizedStringKey, _ symbol: String, _ tint: String, _ led: Binding<LEDSetting>, reset: LEDSetting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SidebarIcon(symbol: symbol, tint: Color(hex: tint))
                Text(t).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { led.wrappedValue = reset } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.plain).foregroundStyle(Theme.textDim).help("Ripristina")
            }
            .padding(.horizontal, 28)
            Capsule().fill(Color(hex: led.wrappedValue.colorHex)).frame(height: 5)
                .shadow(color: Color(hex: led.wrappedValue.colorHex).opacity(0.7), radius: 5)
                .padding(.horizontal, 28).padding(.vertical, 4)
            SectionCard(title: "Effetto e colore") { LEDControls(led: led, zone: .status) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
