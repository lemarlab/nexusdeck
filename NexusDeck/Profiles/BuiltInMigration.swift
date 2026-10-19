import Foundation

/// Converts keys made with the vendor Discord / Voicemod packages into the integrations built into NexusDeck,
/// keeping the chosen server/channel, voice and sound.
@MainActor
enum BuiltInMigration {
    private static let discordWidgets: [String: String] = [
        "mute": ActionID.dcMute, "deafen": ActionID.dcDeafen, "pushToTalk": ActionID.dcPushToTalk,
        "pushToMute": ActionID.dcPushToMute, "voiceChannel": ActionID.dcVoiceChannel, "textChannel": ActionID.dcTextChannel,
    ]
    private static let voicemodWidgets: [String: String] = [
        "Voicebox": ActionID.vmVoice, "ToggleVoiceChanger": ActionID.vmToggleChanger, "ActivateVoiceChanger": ActionID.vmActivateChanger,
        "BackgroundEffects": ActionID.vmBackground, "HearMyself": ActionID.vmHearMyself, "Mute": ActionID.vmMute,
        "MuteForMe": ActionID.vmMuteForMe, "StopAllSoundboard": ActionID.vmStopSounds, "PlaySoundboard": ActionID.vmPlaySound,
        "BleepOut": ActionID.vmBleep,
    ]

    /// Returns the integrations that were used by converted keys.
    static func run(_ library: inout Library) -> Set<BuiltInIntegration> {
        var used: Set<BuiltInIntegration> = []
        for p in library.hotkeyProfiles.indices {
            library.hotkeyProfiles[p].keys = library.hotkeyProfiles[p].keys.map { convert($0, &used) }
        }
        return used
    }

    private static func convert(_ key: KeyAssignment, _ used: inout Set<BuiltInIntegration>) -> KeyAssignment {
        var k = key
        k.children = k.children.map { convert($0, &used) }
        guard let (pkg, widget) = PackageManager.split(k.actionID) else { return k }
        let name = String(widget.split(separator: ".").last ?? "")
        let newID: String?
        let integration: BuiltInIntegration
        if pkg.contains("discord") { newID = discordWidgets[name]; integration = .discord }
        else if pkg.contains("voicemod") { newID = voicemodWidgets[name]; integration = .voicemod }
        else { return k }
        guard let newID else { return k }

        let old = SDKHost.settings(of: k)
        func str(_ key: String) -> String { old[key] as? String ?? "" }
        var settings: Settings = [:]
        switch newID {
        case ActionID.dcVoiceChannel, ActionID.dcTextChannel:
            settings["server"] = .string(str("target_server"))
            settings["channel"] = .string(str("target_channel"))
        case ActionID.vmVoice:
            settings["voice"] = .string(str("target_changer"))
            settings["voiceName"] = .string(str("target_changer_name"))
        case ActionID.vmPlaySound:
            settings["board"] = .string(str("target_profile"))
            settings["sound"] = .string(str("target_sound"))
            settings["soundName"] = .string(str("target_sound_name"))
        default: break
        }
        k.actionID = newID
        k.settings = settings
        // New states with NexusDeck's own icons; custom titles are kept.
        let titles = k.states.map(\.title)
        var states = ActionCatalog.defaultStates(for: ActionCatalog.descriptor(newID))
        for i in states.indices where i < titles.count && !titles[i].isEmpty { states[i].title = titles[i] }
        k.states = states
        used.insert(integration)
        return k
    }
}
