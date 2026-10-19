import SwiftUI

extension MixerChannel {
    var columnSymbol: String {
        switch self {
        case .mic: "mic.circle.fill"
        case .lineIn: "smallcircle.filled.circle"
        case .console: "gamecontroller.fill"
        case .system, .game, .chat: "display"
        }
    }
}

struct MixerColumn: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var ui: UIState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Mixer audio").font(.system(size: 14, weight: .bold))
                Spacer()
                Button { ui.showMixerTools = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .semibold))
                        Text("Strumenti").font(.system(size: 11.5, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9).frame(height: 22)
                    .background(Theme.accent).clipShape(Capsule())
                }
                .buttonStyle(.plain).help("Strumenti mixer: instradamento, ducking, nomi canali e icone")
                .padding(.trailing, 10)
                Button { ui.showRouting = true } label: {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted").font(.system(size: 13)).foregroundStyle(Theme.textDim)
                }
                .buttonStyle(.plain).help("Tabella di routing audio")
            }
            .padding(.leading, 12).padding(.trailing, 18).frame(height: 38)
            Rectangle().fill(Theme.separator.opacity(0.5)).frame(height: 1)
            HStack(spacing: 10) {
                PillToggle(isOn: Binding(get: { store.mixer.dualMix }, set: { audio.setDualMix($0) }))
                Text("Abilita Dual Mix").font(.system(size: 12.5)).foregroundStyle(Theme.textMid)
            }
            .padding(.leading, 15).frame(height: 36)
            Rectangle().fill(Theme.separator.opacity(0.5)).frame(height: 1)
            HStack(spacing: 10) {
                PillToggle(isOn: Binding(get: { store.mixer.obsTracks }, set: { audio.setOBSTracks($0) }))
                Text("Tracce separate per OBS").font(.system(size: 12.5)).foregroundStyle(Theme.textMid)
                InfoIcon(text: "In OBS aggiungi come \"Acquisizione ingresso audio\" i dispositivi [AM-IN]: Chat Mic (microfono), System, Game, Chat, Line In, Console. Con questa opzione il Line In fisico arriva su \"[AM-IN] Line In\" (usa il mix Audience). Ogni copia segue la manopola e il muto del suo canale.")
            }
            .padding(.leading, 15).frame(height: 36)
            Rectangle().fill(Theme.separator.opacity(0.5)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.mixer.dualMix {
                        MixSection(bus: .creator, title: "Creator Mix", symbol: "person.wave.2.fill")
                        Rectangle().fill(Theme.separator).frame(height: 1)
                        MixSection(bus: .audience, title: "Audience Mix", symbol: "speaker.wave.2.circle")
                    } else {
                        MixSection(bus: .creator, title: "Master Mix", symbol: "person.wave.2.fill")
                    }
                }
            }
        }
    }
}

struct MixSection: View {
    let bus: MixBus
    let title: LocalizedStringKey
    let symbol: String
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var engine: ActionEngine

    var active: Bool { !store.mixer.dualMix || store.mixer.activeMix == bus }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if store.mixer.dualMix, store.mixer.activeMix != bus { audio.switchActiveMix(); engine.syncStates() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol).font(.system(size: 15))
                    Text(title).font(.system(size: 12.5, weight: .bold))
                    Spacer()
                }
                .foregroundStyle(active ? Theme.accent : Theme.textMid)
                .padding(.leading, 15).frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ForEach(MixerChannel.allCases) { ch in ChannelRow(channel: ch, bus: bus, active: active) }
                .padding(.bottom, 2)
        }
    }
}

struct ChannelRow: View {
    let channel: MixerChannel
    let bus: MixBus
    let active: Bool
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var engine: ActionEngine

    var body: some View {
        let s = store.mixer.mixes[bus]?.channels[channel] ?? ChannelState()
        HStack(spacing: 0) {
            Image(systemName: store.mixer.symbol(channel)).font(.system(size: 12))
                .foregroundStyle(active ? Theme.accent : Theme.text).frame(width: 18)
                .padding(.leading, 26)
            Text(store.mixer.name(channel)).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.textMid).lineLimit(1)
                .frame(width: 74, alignment: .leading).padding(.leading, 13)
            VStack(spacing: 5) {
                ThinSlider(value: Binding(get: { Double(s.level) }, set: { audio.setLevel(channel, bus: bus, Int($0)); engine.syncStates() }))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.black)
                        Rectangle().fill(Color(hex: "#18C93A")).frame(width: g.size.width * CGFloat(audio.meters[bus]?[channel] ?? 0) / 100)
                    }
                }
                .frame(height: 2)
            }
            .frame(width: 80)
            .padding(.top, 6)
            HStack(spacing: 14) {
                Button { audio.toggleMute(channel, bus: bus); engine.syncStates() } label: {
                    Image(systemName: channel == .mic ? (s.muted ? "mic.slash.fill" : "mic.fill") : (s.muted ? "speaker.slash.fill" : "speaker.wave.2.fill"))
                        .font(.system(size: 11)).foregroundStyle(s.muted ? Color.red : Theme.textDim).frame(width: 16)
                }
                .buttonStyle(.plain)
                if channel == .mic && bus == .creator {
                    Button { audio.setMonitor(.mic, bus: .creator, !store.mixer.micMonitor); engine.syncStates() } label: {
                        Image(systemName: store.mixer.micMonitor ? "headphones" : "headphones.slash")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim).frame(width: 16)
                    }
                    .buttonStyle(.plain).help("Ascolto del microfono in cuffia")
                }
            }
            .padding(.leading, 12)
            Spacer()
        }
        .frame(height: 58)
    }
}
