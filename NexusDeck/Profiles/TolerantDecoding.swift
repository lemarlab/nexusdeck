import Foundation

// Tolerant decoding: every stored property falls back to its default when missing or invalid,
// so libraries saved by older versions keep loading after new settings are added.

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension KeyedDecodingContainer where Key == AnyKey {
    func v<T: Decodable>(_ key: String, _ fallback: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(T.self, forKey: AnyKey(key))) ?? fallback()
    }
}

extension Library {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        let def = Library()
        self.init()
        hotkeyProfiles = c.v("hotkeyProfiles", def.hotkeyProfiles)
        activeHotkeyProfile = c.v("activeHotkeyProfile", nil)
        mixerProfiles = c.v("mixerProfiles", def.mixerProfiles)
        activeMixerProfile = c.v("activeMixerProfile", nil)
        dspProfiles = c.v("dspProfiles", def.dspProfiles)
        activeDSPProfile = c.v("activeDSPProfile", nil)
        knobProfiles = c.v("knobProfiles", def.knobProfiles)
        activeKnobProfile = c.v("activeKnobProfile", nil)
        device = c.v("device", def.device)
        integrations = c.v("integrations", def.integrations)
        tutorialDone = c.v("tutorialDone", def.tutorialDone)
        appRoutes = c.v("appRoutes", [:])
    }
}

extension DeviceSettings {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        let def = DeviceSettings()
        self.init()
        brightness = c.v("brightness", def.brightness)
        powerSavingMinutes = c.v("powerSavingMinutes", def.powerSavingMinutes)
        touchEffect = c.v("touchEffect", def.touchEffect)
        systemSound = c.v("systemSound", def.systemSound)
        headphonesVolume = c.v("headphonesVolume", def.headphonesVolume)
        lineOutVolume = c.v("lineOutVolume", def.lineOutVolume)
        lineOutSource = c.v("lineOutSource", def.lineOutSource)
        chatMicWithEffects = c.v("chatMicWithEffects", def.chatMicWithEffects)
        sampleRate = c.v("sampleRate", def.sampleRate)
        panelOpacity = c.v("panelOpacity", def.panelOpacity)
        autoHideGrid = c.v("autoHideGrid", def.autoHideGrid)
        interactiveLighting = c.v("interactiveLighting", def.interactiveLighting)
        streamFirst = c.v("streamFirst", def.streamFirst)
        var button: LEDSetting = c.v("ledButton", def.ledButton)
        // Before color sources existed: "static" meant widget color, "custom" meant one chosen color.
        let stored = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("ledButton"))
        if let stored, !stored.contains(AnyKey("colorSource")) {
            if button.mode == .staticColor { button.colorSource = .widget }
            if button.mode == .breathing { button.mode = .staticColor; button.colorSource = .single }
        }
        ledButton = button
        ledKnob = c.v("ledKnob", def.ledKnob)
        ledAura = c.v("ledAura", def.ledAura)
        ledStream = c.v("ledStream", def.ledStream)
        ledRecord = c.v("ledRecord", def.ledRecord)
        background = c.v("background", def.background)
    }
}

extension IntegrationSettings {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        let def = IntegrationSettings()
        self.init()
        obsHost = c.v("obsHost", def.obsHost)
        obsPort = c.v("obsPort", def.obsPort)
        obsEnabled = c.v("obsEnabled", def.obsEnabled)
        streamlabsPort = c.v("streamlabsPort", def.streamlabsPort)
        streamlabsEnabled = c.v("streamlabsEnabled", def.streamlabsEnabled)
        spotifyClientID = c.v("spotifyClientID", def.spotifyClientID)
        twitchClientID = c.v("twitchClientID", def.twitchClientID)
        youtubeClientID = c.v("youtubeClientID", def.youtubeClientID)
        youtubeClientSecret = c.v("youtubeClientSecret", def.youtubeClientSecret)
    }
}

extension MixerProfile {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        self.init(title: c.v("title", "Mixer"))
        let def = MixerProfile(title: "")
        id = c.v("id", UUID())
        mixes = c.v("mixes", def.mixes)
        micInput = c.v("micInput", def.micInput)
        phantom48V = c.v("phantom48V", def.phantom48V)
        gainXLR = c.v("gainXLR", def.gainXLR)
        gain48V = c.v("gain48V", def.gain48V)
        gain63 = c.v("gain63", def.gain63)
        activeMix = c.v("activeMix", def.activeMix)
        linkMixes = c.v("linkMixes", def.linkMixes)
        dualMix = c.v("dualMix", def.dualMix)
        micMonitor = c.v("micMonitor", def.micMonitor)
        micName = c.v("micName", def.micName)
        micImage = c.v("micImage", def.micImage)
        routes = c.v("routes", [:])
        chatMicMuted = c.v("chatMicMuted", false)
        micMuteMode = c.v("micMuteMode", .all)
        channelNames = c.v("channelNames", [:])
        ducking = c.v("ducking", Ducking())
    }
}

extension Ducking {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        self.init()
        enabled = c.v("enabled", false)
        thresholdDB = c.v("thresholdDB", -38)
        reductionDB = c.v("reductionDB", 12)
        releaseMs = c.v("releaseMs", 800)
        channels = c.v("channels", channels)
        streamOnly = c.v("streamOnly", false)
    }
}

extension DSPProfile {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        self.init(title: c.v("title", "Voce"))
        let def = DSPProfile(title: "")
        id = c.v("id", UUID())
        eqEnabled = c.v("eqEnabled", def.eqEnabled)
        eqPresetIndex = c.v("eqPresetIndex", def.eqPresetIndex)
        eqPresets = c.v("eqPresets", def.eqPresets)
        compressorEnabled = c.v("compressorEnabled", def.compressorEnabled)
        compressorPresetIndex = c.v("compressorPresetIndex", def.compressorPresetIndex)
        compressorPresets = c.v("compressorPresets", def.compressorPresets)
        makeupGain = c.v("makeupGain", def.makeupGain)
        reverbEnabled = c.v("reverbEnabled", def.reverbEnabled)
        reverbPresetIndex = c.v("reverbPresetIndex", def.reverbPresetIndex)
        reverbPresets = c.v("reverbPresets", def.reverbPresets)
        echoEnabled = c.v("echoEnabled", def.echoEnabled)
        echo = c.v("echo", def.echo)
        noiseGateEnabled = c.v("noiseGateEnabled", def.noiseGateEnabled)
        noiseGate = c.v("noiseGate", def.noiseGate)
        voiceChanger = c.v("voiceChanger", def.voiceChanger)
    }
}

extension HotkeyProfile {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        self.init(title: c.v("title", "Profilo"))
        id = c.v("id", UUID())
        pageCount = c.v("pageCount", 5)
        keys = c.v("keys", [])
        groupCounter = c.v("groupCounter", 0)
    }
}

extension KeyAssignment {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        self.init(actionID: c.v("actionID", ""))
        id = c.v("id", UUID())
        slot = c.v("slot", .touch)
        page = c.v("page", 0)
        x = c.v("x", 0); y = c.v("y", 0); w = c.v("w", 1); h = c.v("h", 1)
        states = c.v("states", [KeyState()])
        style = c.v("style", KeyTitleStyle())
        settings = c.v("settings", [:])
        children = c.v("children", [])
    }
}

extension KeyTitleStyle {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        self.init()
        colorHex = c.v("colorHex", colorHex)
        size = c.v("size", size)
        bold = c.v("bold", bold)
        italic = c.v("italic", italic)
        underline = c.v("underline", underline)
        alignment = c.v("alignment", alignment)
        fontFamily = c.v("fontFamily", fontFamily)
        textAlignment = c.v("textAlignment", textAlignment)
    }
}

extension LEDSetting {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        self.init(colorHex: c.v("colorHex", "#0000FF"), mode: c.v("mode", .staticColor))
        speed = c.v("speed", 6)
        peak = c.v("peak", false)
        brightness = c.v("brightness", 100)
        colorSource = c.v("colorSource", c.v("perKnob", false) ? .perItem : .single)
        let kc: [String] = c.v("itemColors", c.v("knobColors", itemColors))
        if kc.count == 6 { itemColors = kc }
    }
}

extension BackgroundSetting {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        self.init()
        mode = c.v("mode", .color)
        colorHex = c.v("colorHex", "#111111")
        imagePath = c.v("imagePath", "")
        displayMode = c.v("displayMode", 0)
        recent = c.v("recent", [])
    }
}

extension NoiseGate {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        self.init()
        openThreshold = c.v("openThreshold", -40)
        closeThreshold = c.v("closeThreshold", -46)
        attack = c.v("attack", 1)
        attackDebounce = c.v("attackDebounce", 0)
        hold = c.v("hold", 10)
        release = c.v("release", 700)
        wetRatio = c.v("wetRatio", 1)
    }
}
