import Foundation
import Combine

/// Drives an opened controller: serialized command transactions and panel frame streaming.
final class AXController {
    let hid: HIDDevice
    private let commandQueue = DispatchQueue(label: "nexusdeck.commands", qos: .userInitiated)
    private let renderQueue = DispatchQueue(label: "nexusdeck.render", qos: .userInitiated)
    private var lastCommandEnd = Date.distantPast
    /// Frames waiting to be sent, in order (a page animation queues several; a normal redraw replaces them).
    private var pendingFrames: [Data] = []
    private var rendering = false
    private let ack = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var inputState = AXProtocol.InputState()

    /// Device events, delivered on the main thread.
    let events = PassthroughSubject<AXProtocol.Event, Never>()

    init(hid: HIDDevice) {
        self.hid = hid
    }

    // MARK: Input

    func handleInput(_ data: Data) {
        for e in AXProtocol.decode(data, state: &inputState) {
            if e == .renderAck { ack.signal(); continue }
            events.send(e)
        }
    }

    // MARK: Commands

    /// Sends a command (SET feature then GET feature) and returns the 64-byte reply.
    @discardableResult
    func transact(_ cmd: AXProtocol.Command) async -> [UInt8]? {
        await withCheckedContinuation { c in
            commandQueue.async { c.resume(returning: self.perform(cmd)) }
        }
    }

    /// Mixer register writes waiting in the queue, by register: only the latest value is sent.
    private var pendingWrites: [UInt32: AXProtocol.Command] = [:]

    /// Sends commands in this exact order, never merged with pending writes (for sequences the firmware
    /// reacts to, like the monitor: a mic volume written to the Creator mix is copied to the Audience mix).
    func sendInOrder(_ cmds: [AXProtocol.Command]) {
        commandQueue.async { for c in cmds { _ = self.perform(c) } }
    }

    func send(_ cmd: AXProtocol.Command) {
        let b = cmd.bytes
        if b.count > 5, b[0] == 0x01, b[1] == 0x10 {
            // LED registers address several targets (knob ring / key LED id in data bytes 0-1).
            var reg = UInt32(b[2])
            if b[2] == 0xC0 || b[2] == 0xE0 { reg |= UInt32(b[4]) << 8 | UInt32(b[5]) << 16 }
            lock.lock()
            let queued = pendingWrites[reg] != nil
            pendingWrites[reg] = cmd
            lock.unlock()
            if queued { return }
            commandQueue.async {
                self.lock.lock()
                let latest = self.pendingWrites.removeValue(forKey: reg)
                self.lock.unlock()
                if let latest { _ = self.perform(latest) }
            }
            return
        }
        commandQueue.async { _ = self.perform(cmd) }
    }

    func send(_ cmds: [AXProtocol.Command]) { cmds.forEach(send) }

    /// Waits until the queued commands and `cmd` have been written (used when quitting).
    /// Sends and waits (at most `timeout` seconds: used when quitting, it must never block the app).
    func sendAndWait(_ cmd: AXProtocol.Command, timeout: TimeInterval = 1) {
        let done = DispatchSemaphore(value: 0)
        commandQueue.async { _ = self.perform(cmd); done.signal() }
        _ = done.wait(timeout: .now() + timeout)
    }

    /// Last mute masks written: a volume write unmutes the channel on the device, so they are re-sent after it.
    private var lastMutes: AXProtocol.Command?

    private func perform(_ cmd: AXProtocol.Command) -> [UInt8]? {
        let reply = performRaw(cmd)
        let b = cmd.bytes
        if b.count > 2, b[0] == 0x01, b[1] == 0x10 {
            if b[2] == 0x11 { lastMutes = cmd }
            else if (0x27...0x3A).contains(b[2]), let m = lastMutes { _ = performRaw(m) }
        }
        return reply
    }

    private func performRaw(_ cmd: AXProtocol.Command) -> [UInt8]? {
        if cmd.preDelayMs > 0 {
            let wait = Double(cmd.preDelayMs) / 1000 - Date().timeIntervalSince(lastCommandEnd)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }
        defer { lastCommandEnd = Date() }
        guard hid.setFeature(cmd.bytes) == kIOReturnSuccess else { return nil }
        if cmd.interDelayMs > 0 { Thread.sleep(forTimeInterval: Double(cmd.interDelayMs) / 1000) }
        return hid.getFeature(length: AXProtocol.featureSize)
    }

    // MARK: Frames

    /// Queues the newest panel frame (older pending frames are dropped).
    func push(jpeg: Data) {
        guard jpeg.count <= AXProtocol.maxFrameBytes else { return }
        enqueue { $0 = [jpeg] }
    }

    /// Adds a frame after the ones already waiting (animation frames).
    func append(jpeg: Data) {
        guard jpeg.count <= AXProtocol.maxFrameBytes else { return }
        // Fast page changes: older animation frames are dropped (at most one animation waits).
        enqueue { q in q.append(jpeg); if q.count > 6 { q.removeFirst(q.count - 6) } }
    }

    private func enqueue(_ change: (inout [Data]) -> Void) {
        lock.lock()
        change(&pendingFrames)
        let start = !rendering
        rendering = true
        lock.unlock()
        if start { renderQueue.async { self.renderLoop() } }
    }

    /// Sends frames right away on the calling thread (used when quitting, when no run loop is left).
    func pushNow(_ frames: [Data], interval: TimeInterval = 0.07) {
        lock.lock(); pendingFrames.removeAll(); lock.unlock()
        renderQueue.sync {
            for f in frames {
                let start = Date()
                for chunk in AXProtocol.frameChunks(f) where hid.setOutput(chunk) != kIOReturnSuccess { break }
                _ = ack.wait(timeout: .now() + .milliseconds(60))
                let left = interval - Date().timeIntervalSince(start)
                if left > 0 { Thread.sleep(forTimeInterval: left) }
            }
        }
    }

    private func renderLoop() {
        while true {
            lock.lock()
            guard !pendingFrames.isEmpty else { rendering = false; lock.unlock(); return }
            let frame = pendingFrames.removeFirst()
            lock.unlock()

            let start = Date()
            for chunk in AXProtocol.frameChunks(frame) {
                if hid.setOutput(chunk) != kIOReturnSuccess { break }
            }
            let elapsed = Date().timeIntervalSince(start)
            if elapsed < 0.04 { Thread.sleep(forTimeInterval: 0.04 - elapsed) }
            _ = ack.wait(timeout: .now() + .milliseconds(50))
        }
    }

    // MARK: Queries

    func firmwareVersion() async -> String? {
        guard let r = await transact(AXProtocol.firmwareVersion()), r.count >= 10 else { return nil }
        return r[2...5].map(String.init).joined(separator: ".")
    }

    func readMixer() async -> (volumes: [[Int]], mutes: [UInt8])? {
        var vols: [[Int]] = []
        var mutes: [UInt8] = []
        for m in 0..<2 {
            guard let v = await transact(AXProtocol.readMixerVolumes(mixer: m)), v.count >= 10 else { return nil }
            vols.append(v[4..<10].map(Int.init))
            guard let mu = await transact(AXProtocol.readMixerMute(mixer: m)), mu.count >= 5 else { return nil }
            mutes.append(mu[4])
        }
        return (vols, mutes)
    }
}
