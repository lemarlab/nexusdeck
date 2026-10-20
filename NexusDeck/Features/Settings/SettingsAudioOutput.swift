import SwiftUI
import ServiceManagement

// MARK: Audio output

struct OutputPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var bridge: AudioBridge

    var body: some View {
        SectionCard(title: "Mixer audio") {
            SettingRow(title: "Frequenza", labelWidth: 110) {
                DarkPicker(selection: Binding(get: { store.library.device.sampleRate }, set: { rate in
                    store.library.device.sampleRate = rate
                    bridge.setSampleRate(Double(rate))
                }), options: [(48000, "24 bit, 48000 Hz"), (96000, "24 bit, 96000 Hz")], height: 24).frame(width: 280)
            }
        }
        SectionCard(title: "Line Out") {
            SettingRow(title: "Sorgente", labelWidth: 110) {
                DarkPicker(selection: Binding(get: { store.library.device.lineOutSource }, set: { store.library.device.lineOutSource = $0; audio.applyDevice() }),
                           options: [(0, "Creator Mix"), (1, "Audience Mix"), (2, "Chat Mic")]).frame(width: 280)
            }
        }
        SectionCard(title: "Chat Mic") {
            SettingRow(title: "Sorgente", labelWidth: 110) {
                DarkPicker(selection: Binding(get: { store.library.device.chatMicWithEffects }, set: { store.library.device.chatMicWithEffects = $0; audio.applyDSP() }),
                           options: [(true, "Mic con effetti"), (false, "Mic senza effetti")]).frame(width: 280)
            }
        }
        SectionCard(title: "Volume cuffie / Line Out") {
            volume("Cuffie", \.headphonesVolume)
            volume("Line Out", \.lineOutVolume)
        }
    }

    private func volume(_ t: LocalizedStringKey, _ kp: WritableKeyPath<DeviceSettings, Int>) -> some View {
        SettingRow(title: t, labelWidth: 110) {
            ThinSlider(value: Binding(get: { Double(store.library.device[keyPath: kp]) }, set: { store.library.device[keyPath: kp] = Int($0) })) { audio.applyDevice() }
                .frame(width: 220)
            Text("\(store.library.device[keyPath: kp])%").font(.system(size: 13)).foregroundStyle(Theme.textMid).padding(.leading, 20)
        }
    }
}
