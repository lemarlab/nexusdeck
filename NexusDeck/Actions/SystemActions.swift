import SwiftUI
import AppKit
import Carbon.HIToolbox
import ApplicationServices

/// Records a key combination (key code + modifier flags) into settings.
struct HotkeyRecorder: View {
    @Binding var settings: Settings
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text("Scorciatoia")
            Spacer()
            Button(recording ? "Premi i tasti…" : display) { recording ? stop() : start() }
                .buttonStyle(.bordered)
                .tint(recording ? .accentColor : nil)
        }
    }

    private var display: String {
        let code = settings.int("keyCode", -1)
        guard code >= 0 else { return "Registra" }
        return KeySynth.describe(keyCode: UInt16(code), flags: NSEvent.ModifierFlags(rawValue: UInt(settings.int("modifiers"))))
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            settings["keyCode"] = .number(Double(e.keyCode))
            settings["modifiers"] = .number(Double(e.modifierFlags.intersection([.command, .option, .control, .shift, .function]).rawValue))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

enum KeySynth {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func describe(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + keyName(keyCode)
    }

    /// Parses a Qt key sequence such as "Ctrl+Shift+A" or "1" (as saved by the reference app).
    static func parse(_ sequence: String) -> (keyCode: UInt16, flags: NSEvent.ModifierFlags)? {
        let parts = sequence.split(separator: ",").first.map { $0.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) } } ?? []
        guard let keyPart = parts.last, !keyPart.isEmpty else { return nil }
        var flags: NSEvent.ModifierFlags = []
        for m in parts.dropLast() {
            switch m.lowercased() {
            case "ctrl", "control", "meta": flags.insert(m.lowercased() == "meta" ? .control : .command)
            case "shift": flags.insert(.shift)
            case "alt", "option": flags.insert(.option)
            case "cmd", "command", "win": flags.insert(.command)
            default: break
            }
        }
        let named: [String: Int] = ["return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "space": kVK_Space,
            "backspace": kVK_Delete, "del": kVK_ForwardDelete, "delete": kVK_ForwardDelete, "esc": kVK_Escape, "escape": kVK_Escape,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "home": kVK_Home, "end": kVK_End, "pgup": kVK_PageUp, "pgdown": kVK_PageDown,
            "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
            "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15,
            "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18, "f19": kVK_F19, "f20": kVK_F20]
        if let c = named[keyPart.lowercased()] { return (UInt16(c), flags) }
        // Printable key: find the code that produces it in the current layout.
        for code in UInt16(0)..<128 where keyName(code) == keyPart.uppercased() { return (code, flags) }
        return nil
    }

    static func keyName(_ code: UInt16) -> String {
        let special: [Int: String] = [kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Spazio", kVK_Delete: "⌫", kVK_Escape: "⎋",
                                      kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
                                      kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
                                      kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"]
        if let n = special[Int(code)] { return n }
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var len = 0
        data.withUnsafeBytes { raw in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
        }
        return String(utf16CodeUnits: chars, count: len).uppercased()
    }

    static func press(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        var cg: CGEventFlags = []
        if flags.contains(.command) { cg.insert(.maskCommand) }
        if flags.contains(.option) { cg.insert(.maskAlternate) }
        if flags.contains(.control) { cg.insert(.maskControl) }
        if flags.contains(.shift) { cg.insert(.maskShift) }
        if flags.contains(.function) { cg.insert(.maskSecondaryFn) }
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = cg
        up?.flags = cg
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func type(_ text: String, pressEnter: Bool) {
        let src = CGEventSource(stateID: .hidSystemState)
        for chunk in text.utf16.chunked(20) {
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            chunk.withUnsafeBufferPointer {
                down?.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
                up?.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
            }
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
        if pressEnter { press(keyCode: UInt16(kVK_Return), flags: []) }
    }

    /// Media keys are delivered as NX system-defined events.
    static func media(_ key: MultimediaKey) {
        let nx: Int32
        switch key {
        case .playPause: nx = 16 // NX_KEYTYPE_PLAY
        case .next: nx = 17 // NX_KEYTYPE_NEXT
        case .previous: nx = 18 // NX_KEYTYPE_PREVIOUS
        case .volumeUp: nx = 0 // NX_KEYTYPE_SOUND_UP
        case .volumeDown: nx = 1 // NX_KEYTYPE_SOUND_DOWN
        case .mute: nx = 7 // NX_KEYTYPE_MUTE
        }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((nx << 16) | ((down ? 0xA : 0xB) << 8))
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Window operations on the frontmost app via the Accessibility API.
    static func window(_ op: WindowOperation) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        if op == .hideApp { app.hide(); return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success, let win = value else {
            return
        }
        let w = win as! AXUIElement
        switch op {
        case .minimize: AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        case .close: press(w, kAXCloseButtonAttribute)
        case .zoom: press(w, kAXZoomButtonAttribute)
        case .fullScreen:
            var fs: CFTypeRef?
            AXUIElementCopyAttributeValue(w, "AXFullScreen" as CFString, &fs)
            let isFS = (fs as? Bool) ?? false
            AXUIElementSetAttributeValue(w, "AXFullScreen" as CFString, (!isFS) as CFBoolean)
        case .nextWindow: press(keyCode: UInt16(kVK_ANSI_Grave), flags: .command)
        case .leftHalf, .rightHalf, .center:
            guard let screen = NSScreen.main?.visibleFrame, let full = NSScreen.screens.first?.frame else { return }
            var origin = CGPoint(x: screen.minX, y: full.height - screen.maxY)
            var size = CGSize(width: screen.width / 2, height: screen.height)
            if op == .rightHalf { origin.x += screen.width / 2 }
            if op == .center {
                size = CGSize(width: screen.width * 0.6, height: screen.height * 0.7)
                origin = CGPoint(x: screen.midX - size.width / 2, y: full.height - screen.midY - size.height / 2)
            }
            if let p = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, p) }
            if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s) }
        case .hideApp: break
        }
    }

    private static func press(_ w: AXUIElement, _ attr: String) {
        var btn: CFTypeRef?
        if AXUIElementCopyAttributeValue(w, attr as CFString, &btn) == .success, let b = btn {
            AXUIElementPerformAction(b as! AXUIElement, kAXPressAction as CFString)
        }
    }
}

private extension Collection {
    func chunked(_ n: Int) -> [[Element]] {
        var out: [[Element]] = []
        var cur: [Element] = []
        for e in self { cur.append(e); if cur.count == n { out.append(cur); cur = [] } }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}
