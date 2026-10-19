import CoreAudio
import Foundation

struct AudioDeviceInfo: Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// Volume control of macOS audio devices (used by the input/output device knob actions).
enum SystemAudio {
    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func allDevices() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids
    }

    private static func string(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> String {
        var addr = address(sel)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return "" }
        return v.takeRetainedValue() as String
    }

    private static func hasStreams(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
        return size > 0
    }

    static func inputDevices() -> [AudioDeviceInfo] {
        allDevices().filter { hasStreams($0, kAudioObjectPropertyScopeInput) }.map { AudioDeviceInfo(id: $0, uid: string($0, kAudioDevicePropertyDeviceUID), name: string($0, kAudioObjectPropertyName)) }
    }

    static func outputDevices() -> [AudioDeviceInfo] {
        allDevices().filter { hasStreams($0, kAudioObjectPropertyScopeOutput) }.map { AudioDeviceInfo(id: $0, uid: string($0, kAudioDevicePropertyDeviceUID), name: string($0, kAudioObjectPropertyName)) }
    }

    static func defaultDevice(input: Bool) -> AudioDeviceID {
        var addr = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func device(uid: String, input: Bool) -> AudioDeviceID {
        if uid.isEmpty { return defaultDevice(input: input) }
        return (input ? inputDevices() : outputDevices()).first { $0.uid == uid }?.id ?? defaultDevice(input: input)
    }

    private static func scope(_ input: Bool) -> AudioObjectPropertyScope { input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput }

    static func volume(_ id: AudioDeviceID, input: Bool) -> Float {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var addr = address(kAudioDevicePropertyVolumeScalar, scope(input), element)
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(id, &addr), AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr { return v }
        }
        return 0
    }

    static func setVolume(_ id: AudioDeviceID, input: Bool, _ value: Float) {
        let v = max(0, min(1, value))
        var any = false
        var main = address(kAudioDevicePropertyVolumeScalar, scope(input), kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(id, &main) {
            var x = v
            any = AudioObjectSetPropertyData(id, &main, 0, nil, UInt32(MemoryLayout<Float32>.size), &x) == noErr
        }
        if !any {
            for ch in [UInt32(1), 2] {
                var addr = address(kAudioDevicePropertyVolumeScalar, scope(input), ch)
                var x = v
                if AudioObjectHasProperty(id, &addr) { AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &x) }
            }
        }
    }

    static func isMuted(_ id: AudioDeviceID, input: Bool) -> Bool {
        var addr = address(kAudioDevicePropertyMute, scope(input))
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(id, &addr) else { return false }
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v)
        return v != 0
    }

    static func setMuted(_ id: AudioDeviceID, input: Bool, _ muted: Bool) {
        var addr = address(kAudioDevicePropertyMute, scope(input))
        var v: UInt32 = muted ? 1 : 0
        guard AudioObjectHasProperty(id, &addr) else { return }
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    }
}
