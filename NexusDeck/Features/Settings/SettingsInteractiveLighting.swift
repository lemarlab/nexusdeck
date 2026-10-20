import SwiftUI
import ServiceManagement

// MARK: Interactive lighting

struct InteractiveLightingPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var engine: ActionEngine

    private func dev<T>(_ kp: WritableKeyPath<DeviceSettings, T>) -> Binding<T> {
        Binding(get: { store.library.device[keyPath: kp] }, set: { store.library.device[keyPath: kp] = $0; engine.syncStates() })
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#2E2E2E")).frame(width: 420, height: 40)
            Rectangle().fill(Color(hex: store.library.device.streamFirst ? store.library.device.ledStream.colorHex : store.library.device.ledRecord.colorHex))
                .frame(width: 420, height: 3).offset(y: 2)
        }
        .overlay(HStack { Rectangle().fill(Theme.accent).frame(width: 2, height: 46); Spacer(); Rectangle().fill(Theme.accent).frame(width: 2, height: 46) }.frame(width: 446))
        .frame(maxWidth: .infinity).padding(.vertical, 30)
        HStack(spacing: 10) {
            PillToggle(isOn: dev(\.interactiveLighting))
            Text("Effetto interattivo").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textMid)
            InfoIcon(text: "Durante una diretta o una registrazione (OBS / Streamlabs) la luce ambiente cambia per segnalarlo.")
        }
        .padding(.leading, 22)
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 60) {
                radio("Diretta", store.library.device.streamFirst) { store.library.device.streamFirst = true }
                radio("Registrazione", !store.library.device.streamFirst) { store.library.device.streamFirst = false }
            }
            .padding(.leading, 22)
            lightCard("Luce diretta", "dot.radiowaves.left.and.right", dev(\.ledStream), selected: store.library.device.streamFirst)
            lightCard("Luce registrazione", "record.circle", dev(\.ledRecord), selected: !store.library.device.streamFirst)
        }
        .padding(.vertical, 20)
        .background(Theme.card)
        .opacity(store.library.device.interactiveLighting ? 1 : 0.5)
        .allowsHitTesting(store.library.device.interactiveLighting)
    }

    private func lightCard(_ t: LocalizedStringKey, _ symbol: String, _ led: Binding<LEDSetting>, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(Theme.textMid)
                Text(t).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textMid)
                Spacer()
                Button { led.wrappedValue = t == "Luce diretta" ? DeviceSettings().ledStream : DeviceSettings().ledRecord } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.plain).foregroundStyle(Theme.textDim)
            }
            LEDControls(led: led, zone: .status)
        }
        .padding(.horizontal, 40).padding(.vertical, 22)
        .background(Theme.card)
        .overlay(alignment: .leading) { if selected { Rectangle().fill(Theme.accent).frame(width: 3) } }
        .padding(.horizontal, 20)
    }
}
