import Foundation
import SwiftUI

struct LEDSetting: Codable, Hashable {
    enum Mode: Int, Codable, CaseIterable, Identifiable {
        case off = 0, staticColor = 1, breathing = 2, flash = 3, wave = 4, rainbow = 5, colorCycle = 6, spectrum = 7, volume = 8
        var id: Int { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .off: "Spento"
            case .staticColor: "Colore dell'icona"
            case .breathing: "Colore personalizzato"
            case .flash: "Lampeggio"
            case .wave: "Arcobaleno"
            case .rainbow: "Respiro"
            case .colorCycle: "Ciclo colori"
            case .spectrum: "Onda colori"
            case .volume: "Livello volume"
            }
        }
    }
    var colorHex: String
    var mode: Mode
    var speed: Int = 6
    var peak = false
    var brightness = 100
    /// Where the color comes from (for effects that use a color).
    enum ColorSource: Int, Codable { case single = 0, perItem = 1, widget = 2 }
    var colorSource: ColorSource = .single
    /// One color per item: function keys 0…3 (TL, TR, BL, BR) or knobs 0…5 (Mic … Chat).
    var itemColors = ["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF", "#00FFFF"]
}

extension LEDSetting.Mode {
    /// Rainbow-type effects generate their own colors.
    var usesColor: Bool { ![.off, .wave, .colorCycle, .spectrum].contains(self) }
    /// Only animated effects have a speed.
    var usesSpeed: Bool { [.flash, .wave, .rainbow, .colorCycle, .spectrum].contains(self) }
}

struct BackgroundSetting: Codable, Hashable {
    enum Mode: Int, Codable { case color = 0, image = 1 }
    var mode: Mode = .color
    var colorHex = "#111111"
    var imagePath = ""
    /// Picture placement, in the reference app's order: fill, fit, stretch (scale), tile, center.
    var displayMode = 0
    /// Last pictures used (up to 5), for quick switching as in the reference app.
    var recent: [String] = []

    static let displayModes: [(Int, String)] = [(0, "Riempi lo schermo"), (1, "Adatta all'immagine"), (2, "Scala allo schermo"), (3, "Affianca"), (4, "Centrata")]

    mutating func use(_ path: String) {
        imagePath = path
        recent.removeAll { $0 == path }
        recent.insert(path, at: 0)
        if recent.count > 5 { recent.removeLast(recent.count - 5) }
    }
}

struct DeviceSettings: Codable, Hashable {
    var brightness = 80
    var powerSavingMinutes = 0 // 0 = off
    var touchEffect = true
    var systemSound = true
    var headphonesVolume = 85
    var lineOutVolume = 85
    /// 0 Creator Mix, 1 Audience Mix, 2 Chat Mic
    var lineOutSource = 1
    var chatMicWithEffects = true
    /// USB audio sample rate: 48000 or 96000 (24 bit), as in the reference app.
    var sampleRate = 48000
    var panelOpacity: Double = 1
    var autoHideGrid = false
    var interactiveLighting = true
    var streamFirst = true
    var ledButton = LEDSetting(colorHex: "#0000FF", mode: .staticColor, speed: 0, colorSource: .widget)
    var ledKnob = LEDSetting(colorHex: "#007DFF", mode: .volume, speed: 0)
    var ledAura = LEDSetting(colorHex: "#0000FF", mode: .spectrum)
    var ledStream = LEDSetting(colorHex: "#0000FF", mode: .flash)
    var ledRecord = LEDSetting(colorHex: "#FF0000", mode: .flash)
    var background = BackgroundSetting()
}

struct IntegrationSettings: Codable, Hashable {
    var obsHost = "127.0.0.1"
    var obsPort = 4455
    var obsEnabled = true
    var streamlabsPort = 59650
    var streamlabsEnabled = false
    var spotifyClientID = ""
    var twitchClientID = ""
    var youtubeClientID = ""
    var youtubeClientSecret = ""
}

/// Everything persisted by the app.
struct Library: Codable {
    var hotkeyProfiles: [HotkeyProfile] = [HotkeyProfile.makeDefault()]
    var activeHotkeyProfile: UUID?
    var mixerProfiles: [MixerProfile] = [MixerProfile(title: "Mixer predefinito")]
    var activeMixerProfile: UUID?
    var dspProfiles: [DSPProfile] = [DSPProfile(title: "Voce predefinita")]
    var activeDSPProfile: UUID?
    var knobProfiles: [KnobProfile] = [KnobProfile(title: "Manopole predefinite")]
    var activeKnobProfile: UUID?
    var device = DeviceSettings()
    var integrations = IntegrationSettings()
    var tutorialDone = false
    /// Per-app routing: bundle ID → MixerChannel raw value.
    var appRoutes: [String: String] = [:]
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published var library: Library { didSet { scheduleSave() } }

    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("NexusDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    static let iconFolder: URL = {
        let url = folder.appendingPathComponent("Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    static let backupFolder: URL = {
        let url = folder.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    private static var fileURL: URL { folder.appendingPathComponent("library.json") }

    private var saveTask: Task<Void, Never>?

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let lib = try? JSONDecoder().decode(Library.self, from: data) {
            library = lib
        } else {
            library = Library()
        }
        normalize()
    }

    private static func recolorDefaultStates(_ k: KeyAssignment) -> KeyAssignment {
        var k = k
        k.children = k.children.map(recolorDefaultStates)
        guard !k.actionID.hasPrefix("pkg:"), k.states.count > 1 else { return k }
        let base = Theme.tileHex(for: k.actionID)
        for i in k.states.indices where k.states[i].background.uppercased() == "#1E1E1E" {
            k.states[i].background = i == 0 ? base : Theme.lighten(base, 0.28)
        }
        // The old "on" color was the plain base color: make it the lighter shade.
        if k.states[0].background == base {
            for i in k.states.indices.dropFirst() where k.states[i].background.uppercased() == base.uppercased() {
                k.states[i].background = Theme.lighten(base, 0.28)
            }
        }
        return k
    }

    private func normalize() {
        if library.hotkeyProfiles.isEmpty { library.hotkeyProfiles = [HotkeyProfile.makeDefault()] }
        if library.mixerProfiles.isEmpty { library.mixerProfiles = [MixerProfile(title: "Mixer predefinito")] }
        if library.dspProfiles.isEmpty { library.dspProfiles = [DSPProfile(title: "Voce predefinita")] }
        if library.knobProfiles.isEmpty { library.knobProfiles = [KnobProfile(title: "Manopole predefinite")] }
        // Keys of the vendor Discord / Voicemod packages become the built-in integrations.
        for i in BuiltInMigration.run(&library) { UserDefaults.standard.set(true, forKey: i.defaultsKey) }
        // Older versions drew the first state of two-state keys in grey: use the action-list color.
        for p in library.hotkeyProfiles.indices {
            library.hotkeyProfiles[p].keys = library.hotkeyProfiles[p].keys.map(Self.recolorDefaultStates)
        }
        // Older versions shipped flat EQ presets 2–5: replace untouched ones with the factory curves.
        let factory = DSPProfile.defaultEQPresets
        for p in library.dspProfiles.indices {
            for e in 1..<min(5, library.dspProfiles[p].eqPresets.count)
            where library.dspProfiles[p].eqPresets[e].allSatisfy({ $0.gain == 0 }) {
                library.dspProfiles[p].eqPresets[e] = factory[e]
            }
        }
        if !library.hotkeyProfiles.contains(where: { $0.id == library.activeHotkeyProfile }) { library.activeHotkeyProfile = library.hotkeyProfiles[0].id }
        if !library.mixerProfiles.contains(where: { $0.id == library.activeMixerProfile }) { library.activeMixerProfile = library.mixerProfiles[0].id }
        if !library.dspProfiles.contains(where: { $0.id == library.activeDSPProfile }) { library.activeDSPProfile = library.dspProfiles[0].id }
        if !library.knobProfiles.contains(where: { $0.id == library.activeKnobProfile }) { library.activeKnobProfile = library.knobProfiles[0].id }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(library) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    // MARK: Active profile accessors

    private func index<T: Identifiable>(_ items: [T], _ id: T.ID?) -> Int where T.ID: Equatable {
        items.firstIndex { $0.id == id } ?? 0
    }

    var hotkey: HotkeyProfile {
        get { library.hotkeyProfiles[index(library.hotkeyProfiles, library.activeHotkeyProfile)] }
        set { library.hotkeyProfiles[index(library.hotkeyProfiles, library.activeHotkeyProfile)] = newValue }
    }
    var mixer: MixerProfile {
        get { library.mixerProfiles[index(library.mixerProfiles, library.activeMixerProfile)] }
        set { library.mixerProfiles[index(library.mixerProfiles, library.activeMixerProfile)] = newValue }
    }
    var dsp: DSPProfile {
        get { library.dspProfiles[index(library.dspProfiles, library.activeDSPProfile)] }
        set { library.dspProfiles[index(library.dspProfiles, library.activeDSPProfile)] = newValue }
    }
    var knob: KnobProfile {
        get { library.knobProfiles[index(library.knobProfiles, library.activeKnobProfile)] }
        set { library.knobProfiles[index(library.knobProfiles, library.activeKnobProfile)] = newValue }
    }

    // MARK: Import / export

    struct ExportBundle: Codable {
        var format = "nexusdeck.profile"
        var version = 1
        var hotkey: HotkeyProfile?
        var mixer: MixerProfile?
        var dsp: DSPProfile?
        var knob: KnobProfile?
        /// icon file name -> PNG data
        var icons: [String: Data] = [:]
    }

    func exportHotkeyProfile(_ p: HotkeyProfile, to url: URL) throws {
        var bundle = ExportBundle(hotkey: p)
        for key in p.keys + p.keys.flatMap(\.children) {
            for s in key.states where !s.image.isEmpty && !s.image.hasPrefix("sf:") {
                bundle.icons[s.image] = try? Data(contentsOf: Self.iconFolder.appendingPathComponent(s.image))
            }
        }
        try JSONEncoder().encode(bundle).write(to: url, options: .atomic)
    }

    func importProfile(from url: URL) throws {
        let bundle = try JSONDecoder().decode(ExportBundle.self, from: Data(contentsOf: url))
        for (name, data) in bundle.icons {
            try? data.write(to: Self.iconFolder.appendingPathComponent(name))
        }
        if var p = bundle.hotkey { p.id = UUID(); library.hotkeyProfiles.append(p) }
        if var p = bundle.mixer { p.id = UUID(); library.mixerProfiles.append(p) }
        if var p = bundle.dsp { p.id = UUID(); library.dspProfiles.append(p) }
        if var p = bundle.knob { p.id = UUID(); library.knobProfiles.append(p) }
    }

    /// Full backup of the library and icons.
    func backup() throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dir = Self.backupFolder.appendingPathComponent(stamp, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        saveNow()
        try FileManager.default.copyItem(at: Self.fileURL, to: dir.appendingPathComponent("library.json"))
        try? FileManager.default.copyItem(at: Self.iconFolder, to: dir.appendingPathComponent("Icons"))
        return dir
    }

    // MARK: Backup slots (5, like the reference app)

    private func slotURL(_ i: Int) -> URL { Self.backupFolder.appendingPathComponent("slot\(i + 1)", isDirectory: true) }

    func slotDate(_ i: Int) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: slotURL(i).appendingPathComponent("library.json").path))?[.modificationDate] as? Date
    }

    func backupSlot(_ i: Int) throws {
        let dir = slotURL(i)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        saveNow()
        try FileManager.default.copyItem(at: Self.fileURL, to: dir.appendingPathComponent("library.json"))
        try? FileManager.default.copyItem(at: Self.iconFolder, to: dir.appendingPathComponent("Icons"))
    }

    func restoreSlot(_ i: Int) throws { try restore(slotURL(i)) }

    var backups: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: Self.backupFolder, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func restore(_ dir: URL) throws {
        let data = try Data(contentsOf: dir.appendingPathComponent("library.json"))
        library = try JSONDecoder().decode(Library.self, from: data)
        let icons = dir.appendingPathComponent("Icons")
        for f in (try? FileManager.default.contentsOfDirectory(at: icons, includingPropertiesForKeys: nil)) ?? [] {
            let dst = Self.iconFolder.appendingPathComponent(f.lastPathComponent)
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: f, to: dst)
        }
        normalize()
    }
}

extension HotkeyProfile {
    /// Default layout: mixer dashboard on page 0, utility keys below; mirrors the reference behaviour.
    static func makeDefault() -> HotkeyProfile {
        var p = HotkeyProfile(title: "Tasti e widget predefiniti")
        p.keys = [
            KeyAssignment(actionID: ActionID.mixerDashboard, x: 0, y: 0, w: 5, h: 3),
            KeyAssignment(actionID: ActionID.panelOff, x: 0, y: 3, states: [KeyState(title: "Pannello off", image: "sf:display")]),
            KeyAssignment(actionID: ActionID.switchDSPProfile, x: 3, y: 3, states: [KeyState(title: "Voce", image: "sf:waveform")]),
            KeyAssignment(actionID: ActionID.pageIndicator, x: 2, y: 3),
            KeyAssignment(actionID: ActionID.volume, x: 4, y: 3, states: [KeyState(title: "Volume", image: "sf:speaker.wave.2.fill")]),
            KeyAssignment(actionID: ActionID.openURL, slot: .functionKey, x: 0, y: 0, states: [KeyState(title: "Web", image: "sf:safari")], settings: ["url": .string("https://www.apple.com")]),
        ]
        return p
    }
}
