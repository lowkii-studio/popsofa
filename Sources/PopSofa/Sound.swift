import AVFoundation

/// Leise Bedientöne, synthetisch erzeugt (keine Audiodateien), passend zum Stil:
/// Apple = feines Ticken, Pop-Art = weiche „Plopp“-Blasen, Webmuster = Holzklang & Kalimba.
@MainActor
final class UISound {
    static let shared = UISound()

    enum Kind: CaseIterable { case move, select, back, start }

    var enabled = UserDefaults.standard.object(forKey: "uiSounds") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "uiSounds") }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var lastMove = Date.distantPast
    private var started = false

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.5      // ponytail: feste Lautstärke; Regler erst, wenn gewünscht
    }

    func play(_ kind: Kind, theme: Theme) {
        guard enabled else { return }
        // Gedrückt gehaltener Stick feuert schnell hintereinander – nicht jedes Mal klicken.
        if kind == .move {
            guard Date().timeIntervalSince(lastMove) > 0.045 else { return }
            lastMove = Date()
        }
        if !started {
            do { try engine.start(); started = true } catch { return }
        }
        // Pop: leicht schwankende Tonhöhe, damit es lebendig statt mechanisch klingt.
        let variant = theme == .pop && kind == .move ? Int.random(in: 0..<3) : 0
        let key = "\(theme.rawValue)-\(kind)-\(variant)"
        let buf = cache[key] ?? {
            let b = Self.buffer(Self.samples(kind, theme: theme, variant: variant), format: format)
            cache[key] = b
            return b
        }()
        player.scheduleBuffer(buf, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    // MARK: Synthese

    nonisolated static let rate: Double = 44_100

    /// Ein Ton: Grundfrequenz gleitet von f0 nach f1, Obertöne (Vielfaches, Lautstärke), exponentielles Abklingen.
    nonisolated static func tone(_ f0: Double, _ f1: Double? = nil, dur: Double, decay: Double, amp: Double,
                     partials: [(Double, Double)] = [(1, 1)], delay: Double = 0, attack: Double = 0.003) -> [Float] {
        let n = Int((delay + dur) * rate)
        let start = Int(delay * rate)
        var out = [Float](repeating: 0, count: n)
        var phase = [Double](repeating: 0, count: partials.count)
        for i in start..<n {
            let t = Double(i - start) / rate
            let k = min(t / dur, 1)
            let f = f0 * pow((f1 ?? f0) / f0, k)               // exponentielles Gleiten klingt natürlicher
            let env = min(t / attack, 1) * exp(-t / decay)
            var v = 0.0
            for (j, p) in partials.enumerated() {
                phase[j] += 2 * .pi * f * p.0 / rate
                v += sin(phase[j]) * p.1
            }
            out[i] = Float(v * env * amp)
        }
        return out
    }

    nonisolated static func mix(_ parts: [Float]...) -> [Float] {
        var out = [Float](repeating: 0, count: parts.map(\.count).max() ?? 0)
        for p in parts { for (i, v) in p.enumerated() { out[i] += v } }
        return out
    }

    nonisolated static func samples(_ kind: Kind, theme: Theme, variant: Int = 0) -> [Float] {
        let theme = theme == .popLight ? Theme.pop : theme.isClear ? Theme.apple : theme   // Klar wie Apple, Pop hell wie Pop
        switch (theme, kind) {
        // Start-Klang: kurze Melodie zum App-Start
        case (.apple, .start):  return mix(tone(440, dur: 0.6, decay: 0.22, amp: 0.07, attack: 0.06),
                                           tone(554, dur: 0.6, decay: 0.22, amp: 0.06, delay: 0.05, attack: 0.06),
                                           tone(659, dur: 0.6, decay: 0.22, amp: 0.06, delay: 0.1, attack: 0.06))
        case (.pop, .start):    return mix(tone(523, 700, dur: 0.07, decay: 0.03, amp: 0.12),
                                           tone(659, 880, dur: 0.07, decay: 0.03, amp: 0.12, delay: 0.1),
                                           tone(784, 1050, dur: 0.07, decay: 0.03, amp: 0.12, delay: 0.2),
                                           tone(1568, 2093, dur: 0.12, decay: 0.04, amp: 0.07, delay: 0.32))
        case (.woven, .start):   return mix(tone(587, dur: 0.5, decay: 0.13, amp: 0.09, partials: kalimba),
                                           tone(659, dur: 0.5, decay: 0.13, amp: 0.09, partials: kalimba, delay: 0.12),
                                           tone(880, dur: 0.5, decay: 0.13, amp: 0.09, partials: kalimba, delay: 0.24),
                                           tone(1175, dur: 0.55, decay: 0.15, amp: 0.07, partials: kalimba, delay: 0.36))

        // Apple: kurz, hell, zurückhaltend – wie ein feines Ticken
        case (.apple, .move):   return tone(2400, dur: 0.03, decay: 0.006, amp: 0.10)
        case (.apple, .select): return mix(tone(880, dur: 0.12, decay: 0.035, amp: 0.10),
                                           tone(1320, dur: 0.12, decay: 0.03, amp: 0.07, delay: 0.035))
        case (.apple, .back):   return tone(990, 660, dur: 0.09, decay: 0.03, amp: 0.09)

        // Pop-Art: runde „Plopp“-Blasen mit Tonhöhen-Sprung
        case (.pop, .move):
            let f = [880.0, 940, 820][variant]
            return tone(f, f * 0.5, dur: 0.05, decay: 0.018, amp: 0.13)
        case (.pop, .select):   return mix(tone(520, 1040, dur: 0.07, decay: 0.03, amp: 0.13),
                                           tone(1040, 1560, dur: 0.07, decay: 0.03, amp: 0.10, delay: 0.06))
        case (.pop, .back):     return tone(760, 260, dur: 0.11, decay: 0.04, amp: 0.12)

        // Webmuster: Holzblock beim Bewegen, Kalimba-Töne (Pentatonik) beim Auswählen
        case (.woven, .move):    return tone(1150, dur: 0.05, decay: 0.012, amp: 0.12, partials: [(1, 1), (2.76, 0.35)])
        case (.woven, .select):  return mix(tone(587, dur: 0.45, decay: 0.12, amp: 0.10, partials: kalimba),
                                           tone(880, dur: 0.45, decay: 0.12, amp: 0.08, partials: kalimba, delay: 0.08))
        case (.woven, .back):    return tone(392, dur: 0.35, decay: 0.1, amp: 0.10, partials: kalimba)
        case (.clear, _), (.clearLight, _), (.popLight, _): return []   // oben auf Apple umgelegt
        }
    }

    /// Obertöne einer Kalimba-Zunge (leicht unharmonisch).
    nonisolated static let kalimba: [(Double, Double)] = [(1, 1), (2.01, 0.25), (5.4, 0.08)]

    nonisolated static func buffer(_ s: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(s.count))!
        b.frameLength = AVAudioFrameCount(s.count)
        s.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: s.count) }
        return b
    }

    /// Prüft: jeder Ton ist kurz, leise (kein Übersteuern) und klingt am Ende aus (kein Knacken).
    nonisolated static func selfTest() {
        for theme in Theme.allCases {
            for kind in Kind.allCases {
                let s = samples(kind, theme: theme)
                precondition(!s.isEmpty && Double(s.count) / rate < (kind == .start ? 1.0 : 0.6), "Ton zu lang")
                precondition(s.map(abs).max()! < 0.3, "Ton zu laut")
                precondition(abs(s.last!) < 0.01, "Ton endet hart")
            }
        }
    }
}
