import SwiftUI
import UniformTypeIdentifiers

private let cell: CGFloat = 92
private let gap: CGFloat = 8

extension UTType {
    static let nexusProfile = UTType(exportedAs: "com.nexusdeck.lemarlab.profile", conformingTo: .json)
}

struct WidgetOrKeyView: View {
    @EnvironmentObject var deck: DeckController
    @EnvironmentObject var store: ProfileStore
    let key: KeyAssignment

    var body: some View {
        if key.actionID.hasPrefix("pkg:") {
            PackageKeyFace(key: key)
        } else {
        switch key.actionID {
        case ActionID.mixerDashboard:
            // "Sync" (default) follows the mix the knobs control; otherwise the fixed mix chosen in the settings.
            MixerDashboardFace(mixer: store.mixer, bus: key.settings.bool("sync", true) ? store.mixer.activeMix : (MixBus(rawValue: key.settings.int("mix")) ?? .creator),
                               inputIndicator: key.settings.bool("input", true),
                               knobColors: (0..<6).map { store.library.device.ledKnob.knobColor($0) })
        case ActionID.pageIndicator:
            PageIndicatorFace(page: deck.currentPage, count: store.hotkey.pageCount, inFolder: deck.isInFolder)
        default:
            KeyFaceView(state: deck.state(for: key), style: key.style, overlayText: deck.liveText[key.id])
        }
        }
    }
}

struct PageIndicatorFace: View {
    let page: Int, count: Int, inFolder: Bool
    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            ZStack {
                Color(hex: "#18181C")
                VStack(spacing: h * 0.08) {
                    Text(inFolder ? "Cartella" : "\(page + 1)/\(count)").font(.system(size: h * 0.24, weight: .bold)).foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                    if !inFolder {
                        HStack(spacing: h * 0.05) {
                            ForEach(0..<count, id: \.self) { i in
                                Circle().fill(i == page ? Color.white : Color.gray.opacity(0.5)).frame(width: h * 0.07, height: h * 0.07)
                            }
                        }
                    }
                }
                .frame(width: g.size.width, height: h)
            }
        }
    }
}

struct MixerDashboardFace: View {
    let mixer: MixerProfile
    let bus: MixBus
    var inputIndicator = true
    /// Ring colours of the six knobs (same as the device LEDs).
    var knobColors: [Color] = Array(repeating: Color(hex: "#0A84FF"), count: 6)
    @ObservedObject private var meters = LevelMeters.shared

    var body: some View {
        GeometryReader { g in
            let u = g.size.width / 800 // panel units (the dashboard is 800 wide on the panel)
            let mix = mixer.mixes[mixer.dualMix ? bus : .creator] ?? MixState()
            HStack(spacing: 14 * u) {
                // Left: the mix the knobs drive.
                VStack(spacing: 18 * u) {
                    if mixer.dualMix {
                        busTile("CREATOR", "person.wave.2.fill", active: bus == .creator, u: u)
                        busTile("AUDIENCE", "dot.radiowaves.left.and.right", active: bus == .audience, u: u)
                    } else {
                        busTile("MASTER", "slider.vertical.3", active: true, u: u)
                    }
                }
                .frame(width: 190 * u)
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 18 * u).fill(Color(hex: "#5B8CFF").opacity(0.08)))
                // Right: six channels, drawn like the knobs of the device.
                VStack(spacing: 16 * u) {
                    HStack(spacing: 0) { ForEach(MixerChannel.allCases.prefix(3)) { ch in channel(ch, mix, u) } }
                    HStack(spacing: 0) { ForEach(MixerChannel.allCases.suffix(3)) { ch in channel(ch, mix, u) } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(14 * u)
            // Midnight blue background.
            .background(LinearGradient(colors: [Color(hex: "#1B2A4A"), Color(hex: "#0B1426")], startPoint: .top, endPoint: .bottom))
        }
    }

    private func busTile(_ title: String, _ symbol: String, active: Bool, u: CGFloat) -> some View {
        let size: CGFloat = (mixer.dualMix ? 92 : 112) * u
        return VStack(spacing: 10 * u) {
            RoundedRectangle(cornerRadius: size * 0.27)
                .fill(active ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#FFB340"), Color(hex: "#FF7A00")], startPoint: .top, endPoint: .bottom))
                             : AnyShapeStyle(Color.white.opacity(0.08)))
                .frame(width: size, height: size)
                .overlay(Image(systemName: symbol).font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(active ? .white : Color.white.opacity(0.45)))
                .shadow(color: active ? Color(hex: "#FF7A00").opacity(0.45) : .clear, radius: 10 * u, y: 4 * u)
            Text(title).font(.system(size: 17 * u, weight: .semibold)).tracking(1.5 * u)
                .foregroundStyle(active ? .white : Color.white.opacity(0.45))
        }
    }

    private func channel(_ ch: MixerChannel, _ mix: MixState, _ u: CGFloat) -> some View {
        let s = mix.channels[ch] ?? ChannelState()
        let ring: Color = s.muted ? Color(hex: "#FF453A") : knobColors[MixerChannel.allCases.firstIndex(of: ch) ?? 0]
        return VStack(spacing: 10 * u) {
            ZStack {
                // Volume: 270° arc like the device knobs (red when muted).
                Circle().trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 8 * u, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: 0.75 * CGFloat(s.level) / 100)
                    .stroke(ring, style: StrokeStyle(lineWidth: 8 * u, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .shadow(color: ring.opacity(0.6), radius: 4 * u)
                // Live input level, inside the volume arc.
                if inputIndicator {
                    let lvl = CGFloat(meters.values[mixer.dualMix ? bus : .creator]?[ch] ?? 0) / 100
                    Circle().trim(from: 0, to: 0.75 * (s.muted ? 0 : lvl))
                        .stroke(Color(hex: "#30D158"), style: StrokeStyle(lineWidth: 3 * u, lineCap: .round))
                        .rotationEffect(.degrees(135)).padding(11 * u)
                }
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "#434347"), Color(hex: "#1D1D20")], center: .top, startRadius: 1, endRadius: 40 * u))
                    .padding(17 * u)
                    .shadow(color: .black.opacity(0.6), radius: 3 * u, y: 2 * u)
                Text("\(s.level)").font(.system(size: 24 * u, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(s.muted ? Color(hex: "#FF453A") : .white)
            }
            .frame(width: 92 * u, height: 92 * u)
            Text(mixer.name(ch).uppercased()).font(.system(size: 14 * u, weight: .semibold)).tracking(1.2 * u)
                .foregroundStyle(Color.white.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

