import AVFoundation
import UIKit

/// Haptics and sound for each moment of a game: firm, like a piece set on wood. One call per event.
@MainActor
final class Feel {
    static let shared = Feel()

    var soundOn: Bool { UserDefaults.standard.object(forKey: "sound") as? Bool ?? true }
    var hapticsOn: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }

    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let note = UINotificationFeedbackGenerator()
    private let sound = Knock()

    func prepare() { if hapticsOn { rigid.prepare(); medium.prepare() } }

    /// Picking up a piece, changing an option.
    func select() { if hapticsOn { rigid.impactOccurred(intensity: 0.7) } }

    /// Your piece set down.
    func move(capture: Bool) {
        if hapticsOn {
            if capture {
                heavy.impactOccurred(intensity: 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in self?.rigid.impactOccurred(intensity: 0.7) }
            } else { rigid.impactOccurred(intensity: 1) }
        }
        if soundOn { sound.play(capture ? .take : .set) }
    }

    /// The engine's piece set down: softer and farther away.
    func reply(capture: Bool) {
        if hapticsOn { medium.impactOccurred(intensity: capture ? 1 : 0.8) }
        if soundOn { sound.play(capture ? .takeFar : .setFar) }
    }

    /// A move against the rules.
    func refuse() { if hapticsOn { note.notificationOccurred(.warning) } }

    /// Your clock is low: one soft double tap, no sound.
    func lowTime() {
        guard hapticsOn else { return }
        medium.impactOccurred(intensity: 0.55)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.medium.impactOccurred(intensity: 0.55) }
    }

    func check() { if hapticsOn { heavy.impactOccurred(intensity: 0.6) } }

    func won() {
        if hapticsOn { note.notificationOccurred(.success) }
        if soundOn { sound.play(.chord) }
    }

    func ended() {
        if hapticsOn { heavy.impactOccurred(intensity: 0.9) }
        if soundOn { sound.play(.low) }
    }
}

/// Sounds made once at launch from a few lines of synthesis: wood knocks and a soft chord.
/// Ambient, so the silent switch and other audio are respected.
@MainActor
private final class Knock {
    enum Cue: CaseIterable { case set, setFar, take, takeFar, chord, low }

    private let engine = AVAudioEngine()
    private var voices: [AVAudioPlayerNode] = []
    private var turn = 0
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var built = false

    private func build() {
        guard !built else { return }
        built = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for _ in 0..<4 {
            let v = AVAudioPlayerNode()
            engine.attach(v)
            engine.connect(v, to: engine.mainMixerNode, format: format)
            voices.append(v)
        }
        buffers[.set] = render(0.1) { t in Self.knock(t, f: 500, decay: 36) * 0.4 }
        buffers[.setFar] = render(0.1) { t in Self.knock(t, f: 410, decay: 42) * 0.24 }
        buffers[.take] = render(0.17) { t in Self.knock(t, f: 350, decay: 30) * 0.4 + Self.knock(t - 0.05, f: 540, decay: 46) * 0.28 }
        buffers[.takeFar] = render(0.17) { t in Self.knock(t, f: 300, decay: 34) * 0.26 + Self.knock(t - 0.05, f: 470, decay: 50) * 0.18 }
        buffers[.chord] = render(2.0) { t in Self.chord(t, [293.66, 440, 554.37], decay: 1.8) * 0.15 }
        buffers[.low] = render(1.5) { t in Self.chord(t, [146.83, 220], decay: 2.4) * 0.16 }
    }

    func play(_ cue: Cue) {
        build()
        if !engine.isRunning {
            do { try AVAudioSession.sharedInstance().setActive(true); try engine.start() } catch { return }
        }
        guard let b = buffers[cue] else { return }
        let v = voices[turn]
        turn = (turn + 1) % voices.count
        v.stop()
        v.scheduleBuffer(b, at: nil)
        v.play()
    }

    private func render(_ seconds: Double, _ f: (Double) -> Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(seconds * format.sampleRate)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        b.frameLength = n
        let out = b.floatChannelData![0]
        for i in 0..<Int(n) {
            var v = f(Double(i) / format.sampleRate)
            let tail = Int(n) - i
            if tail < 200 { v *= Double(tail) / 200 }
            out[i] = Float(max(-1, min(1, v)))
        }
        return b
    }

    /// A damped tone that drops slightly in pitch, with a short breath of noise at the strike.
    private static func knock(_ t: Double, f: Double, decay: Double) -> Double {
        guard t >= 0 else { return 0 }
        let pitch = f * (1 + 0.22 * exp(-t * 80))
        let body = sin(2 * .pi * pitch * t) * exp(-t * decay) + 0.3 * sin(2 * .pi * pitch * 2.6 * t) * exp(-t * decay * 2.4)
        let x = sin(t * 91_733.7 + 12.9) * 43_758.55
        let noise = ((x - floor(x)) * 2 - 1) * exp(-t * 1000) * 0.45
        return body + noise
    }

    private static func chord(_ t: Double, _ notes: [Double], decay: Double) -> Double {
        guard t >= 0 else { return 0 }
        var v = 0.0
        for (i, f) in notes.enumerated() {
            let u = t - Double(i) * 0.04
            guard u >= 0 else { continue }
            v += sin(2 * .pi * f * u) * exp(-u * decay)
        }
        return min(1, t / 0.015) * v / Double(notes.count) * 2
    }
}
