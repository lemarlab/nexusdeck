import Foundation

/// Imports profiles saved by the vendor app (QSettings plists in ~/Library/Preferences/AVerMedia NEXUS).
@MainActor
enum LegacyImporter {
    static let defaultFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/AVerMedia NEXUS")

    struct Report {
        var hotkeyProfiles = 0
        var keys = 0
        var mixerProfiles = 0
        var dspProfiles = 0
        var missingPackages: Set<String> = []
        var unknownActions: Set<String> = []
    }

    // MARK: Entry point

    static func run(folder: URL, into store: ProfileStore) -> Report {
        var r = Report()
        importCommon(folder.appendingPathComponent("CommonSetting.plist"), store)
        var profileMap: [String: UUID] = [:]
        let hk = readHotkeys(folder.appendingPathComponent("AxHotkeyProfiles.plist"), folder: folder, report: &r, profileMap: &profileMap)
        if !hk.isEmpty {
            // Re-map profile switch targets to the new ids.
            let fixed = hk.map { p -> HotkeyProfile in
                var p = p
                p.keys = p.keys.map { remapProfiles($0, profileMap) }
                return p
            }
            store.library.hotkeyProfiles.append(contentsOf: fixed)
            store.library.activeHotkeyProfile = fixed[0].id
        }
        let mixers = readMixers(folder.appendingPathComponent("AxMixerProfiles.plist"))
        if !mixers.isEmpty { store.library.mixerProfiles.append(contentsOf: mixers); store.library.activeMixerProfile = mixers[0].id }
        let dsps = readDSP(folder.appendingPathComponent("AxDspProfiles.plist"))
        if !dsps.isEmpty { store.library.dspProfiles.append(contentsOf: dsps); store.library.activeDSPProfile = dsps[0].id }
        for i in BuiltInMigration.run(&store.library) { UserDefaults.standard.set(true, forKey: i.defaultsKey) }
        r.missingPackages = r.missingPackages.filter { !PackageManager.builtIn.contains($0) }
        r.hotkeyProfiles = hk.count
        r.keys = hk.reduce(0) { $0 + $1.keys.count }
        r.mixerProfiles = mixers.count
        r.dspProfiles = dsps.count
        return r
    }

    private static func remapProfiles(_ k: KeyAssignment, _ map: [String: UUID]) -> KeyAssignment {
        var k = k
        if k.actionID == ActionID.switchHotkeyProfile, let old = k.settings["profile"]?.string, let new = map[old] {
            k.settings["profile"] = .string(new.uuidString)
        }
        k.children = k.children.map { remapProfiles($0, map) }
        return k
    }

    // MARK: Helpers

    private static func plist(_ url: URL) -> [String: Any]? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any]
    }

    /// QVariant blobs and plain strings both may hold JSON.
    private static func json(_ v: Any?) -> [String: Any] {
        var data: Data?
        if let s = v as? String { data = s.data(using: .utf8) }
        if let d = v as? Data {
            if let start = d.firstIndex(of: UInt8(ascii: "{")), let end = d.lastIndex(of: UInt8(ascii: "}")), start < end { data = d[start...end] } else { data = d }
        }
        guard let data else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func jv(_ any: Any) -> JSONValue {
        if let d = try? JSONSerialization.data(withJSONObject: ["v": any]), let o = try? JSONDecoder().decode([String: JSONValue].self, from: d), let v = o["v"] { return v }
        return .null
    }

    /// Groups "Prefix.N.field" keys into [N: [field: value]].
    private static func arrays(_ p: [String: Any], prefix: String) -> [Int: [String: Any]] {
        var out: [Int: [String: Any]] = [:]
        for (k, v) in p where k.hasPrefix(prefix) {
            let rest = k.dropFirst(prefix.count)
            guard let dot = rest.firstIndex(of: "."), let n = Int(rest[..<dot]) else { continue }
            out[n, default: [:]][String(rest[rest.index(after: dot)...])] = v
        }
        return out
    }

    // MARK: Common settings (LED, screen, outputs)

    private static func importCommon(_ url: URL, _ store: ProfileStore) {
        guard let p = plist(url) else { return }
        func led(_ key: String) -> LEDSetting? {
            let j = json(p[key])
            guard !j.isEmpty else { return nil }
            var l = LEDSetting(colorHex: (j["color"] as? String ?? "#0000FF").uppercased(), mode: LEDSetting.Mode(rawValue: j["mode"] as? Int ?? 1) ?? .staticColor)
            l.speed = j["speed"] as? Int ?? 0
            l.peak = j["peakEnable"] as? Bool ?? false
            return l
        }
        if var l = led("LED.button") {
            if l.mode == .breathing {
                l.colorSource = .perItem
                l.itemColors[0] = l.colorHex
                for (i, k) in ["FnKeyRTColor", "FnKeyLBColor", "FnKeyRBColor"].enumerated() {
                    if let c = p[k] as? String { l.itemColors[i + 1] = c.uppercased() }
                }
            } else if l.mode != .off { l.colorSource = .widget }
            if l.mode != .off { l.mode = .staticColor }
            store.library.device.ledButton = l
        }
        if let l = led("LED.knob") { store.library.device.ledKnob = l }
        if let l = led("LED.aura") { store.library.device.ledAura = l }
        if let l = led("LED.stream") { store.library.device.ledStream = l }
        if let l = led("LED.record") { store.library.device.ledRecord = l }
        let bg = json(p["SCREEN.bgSetting"])
        if !bg.isEmpty {
            store.library.device.background.colorHex = (bg["color"] as? String ?? "#111111").uppercased()
            let path = bg["imagePath"] as? String ?? ""
            store.library.device.background.mode = path.isEmpty ? .color : .image
            if !path.isEmpty { store.library.device.background.imagePath = copyIcon(path, folder: url.deletingLastPathComponent()) .map { ProfileStore.iconFolder.appendingPathComponent($0).path } ?? "" }
        }
        store.library.device.background.displayMode = min(4, max(0, bg["displayMode"] as? Int ?? 0))
        // Recent pictures ("themes").
        let themes = (json(p["SCREEN.bgThemes"])["themes"] as? [String] ?? []).compactMap { copyIcon($0, folder: url.deletingLastPathComponent()) }
        store.library.device.background.recent = themes.map { ProfileStore.iconFolder.appendingPathComponent($0).path }
        if let v = p["SCREEN.touchEffect"] as? Bool { store.library.device.touchEffect = v }
        if let v = p["SCREEN.powerSaving"] as? Int { store.library.device.powerSavingMinutes = v }
        if let v = p["AUDIO.headphonesVolume"] as? Int { store.library.device.headphonesVolume = v }
        if let v = p["AUDIO.lineoutVolume"] as? Int { store.library.device.lineOutVolume = v }
        if let v = p["AUDIO.lineoutSource"] as? Int { store.library.device.lineOutSource = v }
    }

    /// Copies a user image referenced by an absolute path (or relative to the vendor folder) into our icon folder.
    private static func copyIcon(_ path: String, folder: URL) -> String? {
        guard !path.hasPrefix(":/") else { return nil }
        var src = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: src.path) {
            src = folder.appendingPathComponent("icon").appendingPathComponent(src.lastPathComponent)
        }
        guard FileManager.default.fileExists(atPath: src.path) else { return nil }
        let name = "imp-" + src.lastPathComponent
        let dst = ProfileStore.iconFolder.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: dst.path) { try? FileManager.default.copyItem(at: src, to: dst) }
        return name
    }

    // MARK: Hotkey profiles

    private static let categoryMap: [String: String] = [
        "com.avermedia.system.openurl": ActionID.openURL, "com.avermedia.system.openapp": ActionID.openApp,
        "com.avermedia.system.hotkey": ActionID.hotkey, "com.avermedia.system.multimedia": ActionID.multimedia,
        "com.avermedia.system.text": ActionID.text, "com.avermedia.system.windowscontrol": ActionID.window,
        "com.avermedia.system.delay": ActionID.delay, "com.avermedia.system.multiaction": ActionID.multiAction,
        "com.avermedia.system.panel.off": ActionID.panelOff, "com.avermedia.system.page.indicator": ActionID.pageIndicator,
        "com.avermedia.system.group": ActionID.group, "com.avermedia.system.group.back": ActionID.groupBack,
        "com.avermedia.system.webview": ActionID.webView,
        "com.avermedia.system.input": ActionID.knobInputDevice, "com.avermedia.system.output": ActionID.knobOutputDevice,
        "com.avermedia.avermediaMixer.EQ": ActionID.micEffect, "com.avermedia.obsStudio.source.mute": ActionID.obsMute,
        "com.avermedia.mixer.pageswitch": ActionID.pageSwitch, "com.avermedia.mixer.mixer.volumes": ActionID.mixerDashboard,
        "com.avermedia.mixer.volume": ActionID.volume, "com.avermedia.mixer.effect": ActionID.micEffect,
        "com.avermedia.mixer.soundboard.player": ActionID.soundboardPlay, "com.avermedia.mixer.soundboard.stop": ActionID.soundboardStop,
        "com.avermedia.avermediaMixer.monitor": ActionID.monitor, "com.avermedia.avermediaMixer.mixSwitch": ActionID.mixSwitch,
        "com.avermedia.avermediaMixer.muteAudioChannel": ActionID.muteChannel,
        "com.avermedia.avermediaMixer.switchHotkeyProfile": ActionID.switchHotkeyProfile,
        "com.avermedia.avermediaMixer.switchKnobProfile": ActionID.switchKnobProfile,
        "com.avermedia.avermediaMixer.switchMixerProfile": ActionID.switchMixerProfile,
        "com.avermedia.avermediaMixer.switchDspProfile": ActionID.switchDSPProfile,
        "com.avermedia.obsStudio.scene": ActionID.obsScene, "com.avermedia.obsStudio.mixerAudio": ActionID.obsMute,
        "com.avermedia.obsStudio.record": ActionID.obsRecord, "com.avermedia.obsStudio.record.pauseresume": ActionID.obsPauseRecord,
        "com.avermedia.obsStudio.stream": ActionID.obsStream, "com.avermedia.obsStudio.source": ActionID.obsSource,
        "com.avermedia.obsStudio.cpuusage": ActionID.obsCPU, "com.avermedia.obsStudio.source.volumeup": ActionID.obsVolUp,
        "com.avermedia.obsStudio.source.volumedown": ActionID.obsVolDown, "com.avermedia.obsStudio.source.volumeset": ActionID.obsVolSet,
        "com.avermedia.obsStudio.source.monitorset": ActionID.obsMonitorSet, "com.avermedia.obsStudio.filter": ActionID.obsFilter,
        "com.avermedia.obsStudio.profile": ActionID.obsProfile, "com.avermedia.obsStudio.scenecollection": ActionID.obsCollection,
        "com.avermedia.obsStudio.transition": ActionID.obsTransition, "com.avermedia.obsStudio.scene.preview": ActionID.obsScenePreview,
        "com.avermedia.obsStudio.studio.scene.preview": ActionID.obsStudioPreview, "com.avermedia.obsStudio.dropped.frames.alarm": ActionID.obsDroppedFrames,
        "com.avermedia.obsStudio.hotkey.trigger": ActionID.obsHotkey, "com.avermedia.obsStudio.previous.scene": ActionID.obsPrevScene,
        "com.avermedia.obsStudio.studio.mode.toggle": ActionID.obsStudioMode, "com.avermedia.obsStudio.preview.to.program": ActionID.obsPreviewToProgram,
        "com.avermedia.obsStudio.virtual.camera": ActionID.obsVirtualCam,
        "com.avermedia.slobs.webapp.mute": ActionID.slMute, "com.avermedia.slobs.webapp.record": ActionID.slRecord,
        "com.avermedia.slobs.webapp.scene": ActionID.slScene, "com.avermedia.slobs.webapp.source": ActionID.slSource,
        "com.avermedia.slobs.webapp.stream": ActionID.slStream,
        "com.avermedia.youtube.follower": ActionID.ytWatching, "com.avermedia.youtube.subscribe": ActionID.ytSubscribers,
        "com.avermedia.youtube.chatbox": ActionID.ytChat,
        "com.avermedia.twitch.viewer": ActionID.twViewers, "com.avermedia.twitch.follower": ActionID.twFollowers,
        "com.avermedia.twitch.chatbox": ActionID.twChat, "com.avermedia.twitch.chat.message": ActionID.twMessage,
        "com.avermedia.twitch.chat.clear": ActionID.twClearChat, "com.avermedia.twitch.chat.emote": ActionID.twEmoteChat,
        "com.avermedia.twitch.chat.followers": ActionID.twFollowersChat, "com.avermedia.twitch.chat.slow": ActionID.twSlowChat,
        "com.avermedia.twitch.chat.sub": ActionID.twSubChat, "com.avermedia.twitch.stream.title": ActionID.twTitle,
        "com.avermedia.twitch.stream.marker": ActionID.twMarker, "com.avermedia.twitch.stream.clip": ActionID.twClip,
        "com.avermedia.twitch.open.last.clip": ActionID.twLastClip,
        "com.avermedia.spotify.play": ActionID.spPlay, "com.avermedia.spotify.previous": ActionID.spPrev,
        "com.avermedia.spotify.next": ActionID.spNext, "com.avermedia.spotify.volume.up": ActionID.spVolUp,
        "com.avermedia.spotify.volume.down": ActionID.spVolDown, "com.avermedia.spotify.shuffle": ActionID.spShuffle,
        "com.avermedia.spotify.repeat": ActionID.spRepeat, "com.avermedia.spotify.info": ActionID.spNowPlaying,
    ]

    private static let builtinPackages: Set<String> = ["com.avermedia.avermediaMixer", "com.avermedia.system", "com.avermedia.obsStudio",
                                                       "com.avermedia.spotify", "com.avermedia.twitch", "com.avermedia.youtube", "com.avermedia.slobs"]

    private static let channelNames: [String: MixerChannel] = ["Mic": .mic, "LineIn": .lineIn, "Console": .console, "System": .system, "Game": .game, "Chat": .chat]

    private static func readHotkeys(_ url: URL, folder: URL, report r: inout Report, profileMap: inout [String: UUID]) -> [HotkeyProfile] {
        guard let p = plist(url) else { return [] }
        var result: [HotkeyProfile] = []
        for (_, prof) in arrays(p, prefix: "ProfileGroup.ProfileArray.").sorted(by: { $0.key < $1.key }) {
            var profile = HotkeyProfile(title: prof["title"] as? String ?? "Profilo importato")
            profile.pageCount = 5
            if let old = prof["profile_id"] as? String { profileMap[old] = profile.id }
            // plugins.N.field
            var plugins: [Int: [String: Any]] = [:]
            for (k, v) in prof where k.hasPrefix("plugins.") {
                let rest = k.dropFirst("plugins.".count)
                guard let dot = rest.firstIndex(of: "."), let n = Int(rest[..<dot]) else { continue }
                plugins[n, default: [:]][String(rest[rest.index(after: dot)...])] = v
            }
            let ordered = plugins.sorted { $0.key < $1.key }.map(\.value)
            var children: [String: KeyAssignment] = [:]
            var currentGroupPage: Int?
            var keys: [KeyAssignment] = []
            for item in ordered {
                guard var key = convert(item, folder: folder, report: &r) else { continue }
                let page = item["page"] as? Int ?? 0
                if page == -99 {
                    children[item["id"] as? String ?? UUID().uuidString] = key
                    continue
                }
                if page == -1 {
                    // Contents of the most recent folder.
                    guard let gp = currentGroupPage else { continue }
                    key.page = gp
                } else {
                    key.page = page
                }
                if key.actionID == ActionID.group {
                    profile.groupCounter += 1
                    let gp = PageID.groupBase + profile.groupCounter
                    key.settings["groupPage"] = .number(Double(gp))
                    currentGroupPage = gp
                }
                keys.append(key)
            }
            // Attach multi-action children.
            for i in keys.indices where keys[i].actionID == ActionID.multiAction {
                let list = (keys[i].settings["actionlist"]?.array ?? [])
                keys[i].children = list.compactMap { entry -> KeyAssignment? in
                    let o = entry.object ?? [:]
                    if o["category"]?.string == "com.avermedia.system.delay" {
                        var d = KeyAssignment(actionID: ActionID.delay)
                        d.settings["ms"] = .number(Double((o["delay"]?.int ?? 0) * (o["unit"]?.int == 1 ? 1000 : 1)))
                        return d
                    }
                    return o["id"]?.string.flatMap { children[$0] }
                }
                keys[i].settings["actionlist"] = nil
            }
            profile.keys = keys
            result.append(profile)
        }
        return result
    }

    private static func convert(_ item: [String: Any], folder: URL, report r: inout Report) -> KeyAssignment? {
        let category = item["category"] as? String ?? ""
        let packageID = item["packageId"] as? String ?? ""
        let payload = json(item["payload"])
        var key: KeyAssignment
        if let ours = categoryMap[category] {
            key = KeyAssignment(actionID: ours)
        } else if !builtinPackages.contains(packageID), !packageID.isEmpty {
            key = KeyAssignment(actionID: PackageManager.actionID(packageID, category))
            if PackageManager.shared.package(packageID) == nil { r.missingPackages.insert(packageID) }
            if let s = payload["settings"] { key.settings["sdk"] = jv(s) }
        } else {
            r.unknownActions.insert(category)
            return nil
        }
        key.slot = (item["slot"] as? String) == "function_key" ? .functionKey : .touch
        key.x = item["x"] as? Int ?? 0
        key.y = item["y"] as? Int ?? 0
        key.w = max(1, item["w"] as? Int ?? 1)
        key.h = max(1, item["h"] as? Int ?? 1)

        // States: titles and images.
        let d = ActionCatalog.descriptor(key.actionID)
        var states = ActionCatalog.defaultStates(for: d)
        let titles = payload["titlelist"] as? [String] ?? []
        let icons = payload["iconlist"] as? [String] ?? []
        let sdkStates = payload["states"] as? [[String: Any]] ?? []
        let count = max(states.count, titles.count, icons.count, sdkStates.count)
        while states.count < count { states.append(states.last ?? KeyState()) }
        for i in 0..<count {
            if i < titles.count { states[i].title = titles[i] }
            if i < sdkStates.count, let t = sdkStates[i]["title"] as? String { states[i].title = t }
            let path = i < icons.count ? icons[i] : (i < sdkStates.count ? sdkStates[i]["image"] as? String ?? "" : "")
            if let name = copyIcon(path, folder: folder) { states[i].image = name }
        }
        if !states.isEmpty { key.states = states }

        // Title style.
        if let dv = (payload["displayView"] ?? payload["font attribute"]) as? [String: Any] {
            key.style.colorHex = (dv["color"] as? String ?? "#FFFFFF").uppercased()
            key.style.size = Double(dv["size"] as? Int ?? 13)
            key.style.bold = dv["bold"] as? Bool ?? false
            key.style.italic = dv["italic"] as? Bool ?? false
            key.style.underline = dv["underLine"] as? Bool ?? false
            key.style.fontFamily = dv["family"] as? String ?? ""
            let h = dv["horAlignment"] as? Int ?? 132
            key.style.textAlignment = h & 0x1 != 0 ? .leading : (h & 0x2 != 0 ? .trailing : .center)
            key.style.alignment = h & 0x20 != 0 ? .top : (h & 0x80 != 0 ? .middle : .bottom)
        }

        // Action-specific properties.
        func s(_ k: String) -> String? { payload[k] as? String }
        switch key.actionID {
        case ActionID.openURL: key.settings["url"] = .string(s("Url") ?? s("url") ?? "")
        case ActionID.hotkey:
            if let seq = s("SendHotkey") ?? s("hotkey"), let (code, flags) = KeySynth.parse(seq) {
                key.settings["keyCode"] = .number(Double(code))
                key.settings["modifiers"] = .number(Double(flags.rawValue))
            }
        case ActionID.openApp: key.settings["path"] = .string(s("Path") ?? s("path") ?? s("AppPath") ?? s("FilePath") ?? "")
        case ActionID.text: key.settings["text"] = .string(s("Text") ?? s("text") ?? "")
        case ActionID.webView:
            key.settings["url"] = .string(s("Url") ?? s("url") ?? "")
            if let css = s("customCss") { key.settings["customCss"] = .string(css) }
        case ActionID.volume:
            let order: [MixerChannel] = [.mic, .lineIn, .console, .system, .game, .chat]
            let ch = payload["channel"] as? Int ?? 0
            key.settings["channel"] = .string(order[max(0, min(5, ch))].rawValue)
            key.settings["mix"] = .number(Double(payload["deck"] as? Int ?? 0))
            key.settings["value"] = .number(Double(payload["volume"] as? Int ?? 50))
            key.settings["mode"] = .string("set")
        case ActionID.pageSwitch: key.settings["page"] = .number(Double(payload["page"] as? Int ?? 0))
        case ActionID.mixerDashboard: key.settings["mix"] = .number(Double(payload["mix"] as? Int ?? 0)); key.settings["sync"] = .bool(payload["sync"] as? Bool ?? true); key.settings["input"] = .bool((payload["input"] as? Int ?? 1) != 0)
        case ActionID.switchHotkeyProfile, ActionID.switchMixerProfile, ActionID.switchDSPProfile, ActionID.switchKnobProfile:
            key.settings["profile"] = .string(s("profileId") ?? "")
        case ActionID.muteChannel:
            for (k, v) in payload {
                guard let on = v as? Bool else { continue }
                let bus = k.hasPrefix("creators") ? 0 : (k.hasPrefix("audience") ? 1 : -1)
                let name = k.replacingOccurrences(of: "creators", with: "").replacingOccurrences(of: "audience", with: "")
                if bus >= 0, let ch = channelNames[name] { key.settings["\(bus).\(ch.rawValue)"] = .bool(on) }
            }
        case ActionID.multiAction:
            if let list = payload["actionlist"] { key.settings["actionlist"] = jv(list) }
        case ActionID.obsScene, ActionID.obsScenePreview, ActionID.slScene:
            key.settings["scene"] = .string(s("sceneName") ?? "")
        case ActionID.obsSource, ActionID.slSource:
            key.settings["scene"] = .string(s("sceneName") ?? "")
            key.settings["source"] = .string(s("sourceName") ?? s("groupName") ?? "")
            key.settings["autoHide"] = .bool(payload["activeAutoHide"] as? Bool ?? false)
            key.settings["autoHideTime"] = .number(Double(payload["autoHideTime"] as? Int ?? 20))
        case ActionID.obsFilter:
            key.settings["source"] = .string(s("sourceName") ?? "")
            key.settings["filter"] = .string(s("filterName") ?? "")
        case ActionID.obsMute, ActionID.obsVolUp, ActionID.obsVolDown, ActionID.obsVolSet, ActionID.obsMonitorSet, ActionID.slMute:
            key.settings["input"] = .string(s("sourceName") ?? s("inputName") ?? "")
        case ActionID.obsProfile: key.settings["profile"] = .string(s("profileName") ?? "")
        case ActionID.obsCollection: key.settings["collection"] = .string(s("sceneCollectionName") ?? s("collectionName") ?? "")
        case ActionID.obsTransition: key.settings["transition"] = .string(s("transitionName") ?? "")
        case ActionID.micEffect:
            if category.hasSuffix(".EQ") { key.settings["effect"] = .string("eq") }
        case ActionID.twMessage: key.settings["message"] = .string(s("message") ?? "")
        default: break
        }
        return key
    }

    // MARK: Mixer profiles

    private static func readMixers(_ url: URL) -> [MixerProfile] {
        guard let p = plist(url) else { return [] }
        let order: [MixerChannel] = [.mic, .lineIn, .console, .system, .game, .chat]
        return arrays(p, prefix: "ProfileInfo.ArrayProfile.").sorted { $0.key < $1.key }.map { _, prof in
            var m = MixerProfile(title: prof["profile·title"] as? String ?? "Mixer importato")
            m.gainXLR = prof["profile·mic_xlr_gain"] as? Int ?? m.gainXLR
            m.gain48V = prof["profile·mic_48v_gain"] as? Int ?? m.gain48V
            m.gain63 = prof["profile·mic_63mm_gain"] as? Int ?? m.gain63
            m.phantom48V = prof["profile·on48V"] as? Bool ?? false
            m.micInput = (prof["profile·mic_type"] as? Int ?? 0) == 2 ? .jack63 : .xlr
            m.dualMix = (prof["profile·mixer_mode"] as? Int ?? 0) != 0
            // ArrayDeck.D.ArrayKnob.K.knob·field
            for d in 1...2 {
                let bus: MixBus = d == 1 ? .creator : .audience
                var mix = MixState()
                mix.level = prof["ArrayDeck.\(d).deck·level"] as? Int ?? 100
                mix.muted = prof["ArrayDeck.\(d).deck·muted"] as? Bool ?? false
                for k in 1...6 {
                    let pre = "ArrayDeck.\(d).ArrayKnob.\(k).knob·"
                    let cat = prof[pre + "category"] as? Int ?? (k - 1)
                    let ch = cat < order.count ? order[cat] : order[k - 1]
                    var cs = ChannelState()
                    cs.level = prof[pre + "level"] as? Int ?? 50
                    cs.muted = prof[pre + "muted"] as? Bool ?? false
                    cs.monitor = prof[pre + "monitor"] as? Bool ?? false
                    mix.channels[ch] = cs
                }
                m.mixes[bus] = mix
            }
            m.micMonitor = m.mixes[.creator]?.channels[.mic]?.monitor ?? true
            return m
        }
    }

    // MARK: Mic DSP profiles

    private static func readDSP(_ url: URL) -> [DSPProfile] {
        guard let p = plist(url) else { return [] }
        return arrays(p, prefix: "ProfileInfo.ArrayProfile.").sorted { $0.key < $1.key }.map { _, prof in
            var d = DSPProfile(title: prof["ProfileTitle"] as? String ?? "Voce importata")
            d.eqEnabled = prof["EqEnabled"] as? Bool ?? d.eqEnabled
            d.eqPresetIndex = min(4, prof["EqIndex"] as? Int ?? 0)
            for e in 1...5 {
                var bands: [EQBand] = []
                for b in 1...8 {
                    let j = json(prof["ArrayEq.\(e).ArrayEqBds.\(b).EqJson"])
                    guard !j.isEmpty else { continue }
                    bands.append(EQBand(frequency: (j["frequency"] as? NSNumber)?.doubleValue ?? 1000, gain: (j["gain"] as? NSNumber)?.doubleValue ?? 0,
                                        q: (j["q"] as? NSNumber)?.doubleValue ?? 0.7, type: EQFilterType(rawValue: j["type"] as? Int ?? 6) ?? .peaking))
                }
                if bands.count == 8 { d.eqPresets[e - 1] = bands }
            }
            d.compressorEnabled = prof["DrcEnabled"] as? Bool ?? d.compressorEnabled
            d.compressorPresetIndex = min(1, prof["DrcIndex"] as? Int ?? 1)
            d.makeupGain = (prof["DrcGain"] as? NSNumber)?.doubleValue ?? d.makeupGain
            for i in 1...2 {
                let j = json(prof["ArrayDrc.\(i).DrcJson"])
                guard !j.isEmpty else { continue }
                d.compressorPresets[i - 1] = Compressor(threshold: (j["threshold"] as? NSNumber)?.doubleValue ?? -18, ratio: (j["ratio"] as? NSNumber)?.doubleValue ?? 0.75,
                                                        attack: (j["attackTime"] as? NSNumber)?.doubleValue ?? 5, release: (j["releaseTime"] as? NSNumber)?.doubleValue ?? 150)
            }
            d.reverbEnabled = prof["ReverbEnabled"] as? Bool ?? d.reverbEnabled
            d.reverbPresetIndex = min(3, prof["ReverbIndex"] as? Int ?? 1)
            for i in 1...4 {
                let j = json(prof["ArrayReverb.\(i).ReverbJson"])
                guard !j.isEmpty else { continue }
                func n(_ k: String, _ def: Double) -> Double { (j[k] as? NSNumber)?.doubleValue ?? def }
                d.reverbPresets[i - 1] = Reverb(roomSize: n("roomSize", 20), damp: n("damp", 1), density: n("density", 1), diffusion: n("diffusion", 0.5),
                                                gain: n("gain", -8), wetGain: n("wetGain", 0), time: n("time", 1))
            }
            d.echoEnabled = prof["EchoEnabled"] as? Bool ?? false
            let e = json(prof["EchoJson"])
            if !e.isEmpty {
                d.echo = Echo(delay: (e["delay"] as? NSNumber)?.doubleValue ?? 150, dryGain: (e["dryGain"] as? NSNumber)?.doubleValue ?? -6,
                              gain: (e["gain"] as? NSNumber)?.doubleValue ?? -12, time: (e["time"] as? NSNumber)?.doubleValue ?? 5)
            }
            d.noiseGateEnabled = prof["NoiseGateEnabled"] as? Bool ?? true
            let g = json(prof["NoiseGateJson"])
            if !g.isEmpty {
                func n(_ k: String, _ def: Double) -> Double { (g[k] as? NSNumber)?.doubleValue ?? def }
                d.noiseGate = NoiseGate(openThreshold: n("openThreshold", -40), closeThreshold: n("closeThreshold", -46), attack: n("attackTime", 1), attackDebounce: n("attackDebonce", 0),
                                        hold: n("holdTime", 10), release: n("releaseTime", 700), wetRatio: n("wetRatio", 1))
            }
            return d
        }
    }
}
