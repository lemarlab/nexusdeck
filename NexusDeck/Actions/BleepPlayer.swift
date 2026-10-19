import Foundation
import AVFoundation

/// Censor bleep: a 1 kHz tone (or a custom sound) looped while the key is held, on the chosen output.
@MainActor
final class BleepPlayer {
    static let shared = BleepPlayer()
    private var player: AVAudioPlayer?

    /// 1 s of a 1 kHz sine, 48 kHz 16-bit mono WAV.
    private static let tone: Data = {
        let rate = 48000, n = rate
        var pcm = Data(capacity: n * 2)
        for i in 0..<n {
            let v = Int16(sin(2 * .pi * 1000 * Double(i) / Double(rate)) * 0.8 * 32767)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        func le32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        func le16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }
        var d = Data("RIFF".utf8) + le32(36 + pcm.count) + Data("WAVEfmt ".utf8)
        d += le32(16) + le16(1) + le16(1) + le32(rate) + le32(rate * 2) + le16(2) + le16(16)
        d += Data("data".utf8) + le32(pcm.count) + pcm
        return d
    }()

    func start(file: String, output: String, volume: Float) {
        stop()
        let p: AVAudioPlayer?
        if !file.isEmpty, FileManager.default.fileExists(atPath: file) {
            p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: file))
        } else {
            p = try? AVAudioPlayer(data: Self.tone)
        }
        guard let p else { return }
        if !output.isEmpty { p.currentDevice = output }
        p.numberOfLoops = -1
        p.volume = volume
        p.play()
        player = p
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
