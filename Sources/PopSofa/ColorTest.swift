import SwiftUI

// MARK: - Farbsehtest nach dem Prinzip des Cambridge Colour Test (Regan, Reffin & Mollon 1994)
//
// Ein Ring mit Lücke (Landolt-C) aus Punkten in einem Punktfeld. Alle Punkte haben zufällige Helligkeit –
// erkennbar ist der Ring nur über den Farbton. Seine Farbe liegt auf einer Verwechslungslinie
// (Rot-, Grün- oder Blau-Schwäche); je Achse sucht ein Treppenverfahren die kleinste erkennbare Abweichung.
// ponytail: unkalibrierter Bildschirm, nur Orientierung – keine Diagnose (die stellt der Augenarzt, z. B. mit Anomaloskop).

enum ColorAxis: Int, CaseIterable {
    case protan, deutan, tritan
    /// Kopunktale Punkte in CIE 1976 u′v′ – alle Verwechslungslinien laufen hier zusammen.
    var copunctal: (u: Double, v: Double) {
        switch self {
        case .protan: return (0.678, 0.501)
        case .deutan: return (-1.217, 0.782)
        case .tritan: return (0.257, 0.0)
        }
    }
    var vision: ColorVision { [.protan, .deutan, .tritan][rawValue] }
}

enum ColorMath {
    /// Neutralgrau D65 in u′v′.
    static let white = (u: 0.1978, v: 0.4683)
    /// Helligkeitsstufen (relatives Y) – Rauschen, damit Helligkeit nichts verrät.
    static let levels: [Double] = [0.10, 0.13, 0.16, 0.19, 0.22]

    /// Punkt auf der Verwechslungslinie: `d` (u′v′-Einheiten) vom Grau weg Richtung kopunktaler Punkt bzw. davon weg.
    static func uv(_ axis: ColorAxis, _ d: Double) -> (u: Double, v: Double) {
        let c = axis.copunctal
        let du = white.u - c.u, dv = white.v - c.v, len = (du * du + dv * dv).squareRoot()
        return (white.u + du / len * d, white.v + dv / len * d)
    }

    /// u′v′ + Y → lineares sRGB (ungeklemmt; nil, wenn außerhalb des Farbraums).
    static func linear(u: Double, v: Double, Y: Double) -> [Double]? {
        let den = 6 * u - 16 * v + 12
        let x = 9 * u / den, y = 4 * v / den
        guard y > 0 else { return nil }
        let X = x * Y / y, Z = (1 - x - y) * Y / y
        let rgb = [3.2406 * X - 1.5372 * Y - 0.4986 * Z,
                   -0.9689 * X + 1.8758 * Y + 0.0415 * Z,
                   0.0557 * X - 0.2040 * Y + 1.0570 * Z]
        return rgb.allSatisfy { $0 >= 0 && $0 <= 1 } ? rgb : nil
    }

    static func gamma(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    static func color(_ axis: ColorAxis?, _ d: Double, Y: Double) -> Color {
        let p = axis.map { uv($0, d) } ?? white
        let rgb = linear(u: p.u, v: p.v, Y: Y) ?? [Y, Y, Y]
        return Color(.sRGB, red: gamma(rgb[0]), green: gamma(rgb[1]), blue: gamma(rgb[2]))
    }

    /// Größte Abweichung je Achse, die bei allen Helligkeitsstufen noch darstellbar ist.
    static func maxD(_ axis: ColorAxis) -> Double {
        var d = 0.0
        while d < 0.2 {
            let n = d + 0.002, p = uv(axis, n)
            guard levels.allSatisfy({ linear(u: p.u, v: p.v, Y: $0) != nil }) else { break }
            d = n
        }
        return d
    }
}

/// Treppenverfahren je Achse: richtig → schwächer, falsch → stärker; Schwelle = Mittel der letzten Umkehrpunkte.
struct Staircase {
    var d: Double
    let maxD: Double
    var reversals: [Double] = []
    var lastCorrect: Bool?
    var trials = 0
    var missesAtMax = 0

    var done: Bool { reversals.count >= 6 || trials >= 16 || missesAtMax >= 2 }
    var threshold: Double {
        if missesAtMax >= 2 { return maxD }
        let r = reversals.suffix(4)
        return r.isEmpty ? d : exp(r.map { log($0) }.reduce(0, +) / Double(r.count))
    }

    mutating func answer(_ correct: Bool) {
        trials += 1
        if let l = lastCorrect, l != correct { reversals.append(d) }
        lastCorrect = correct
        if !correct && d >= maxD * 0.99 { missesAtMax += 1 }
        d = correct ? max(d / 1.6, 0.002) : min(d * 1.6, maxD)
    }
}

struct ColorTestResult: Equatable {
    var thresholds: [Double]   // protan, deutan, tritan (u′v′)
    var vision: ColorVision
    var severity: Double       // 0,5 = leicht (anomal), 1 = stark (dichromat)

    var text: String {
        switch vision {
        case .normal: return tr("Unauffällig – dein Farbsehen wirkt normal.")
        case .achromat: return tr("Du hast auf allen Achsen Farben kaum unterschieden. Das kann an starker Farbsehschwäche liegen – oder an Licht und Bildschirm.")
        default: return tr(severity < 1 ? "Hinweis auf leichte %@." : "Hinweis auf deutliche %@.", vision.title)
        }
    }

    /// Grenzwerte großzügig, weil Fernseher und Raumlicht nicht kalibriert sind.
    /// Normal (CCT, kalibriert): Rot/Grün ≲ 0,01, Blau ≲ 0,015 u′v′; Dichromaten meist > 0,06.
    static func classify(_ t: [Double]) -> ColorTestResult {
        let (p, d, b) = (t[0], t[1], t[2])
        let rg = max(p, d)
        let sev = { (x: Double) in x > 0.06 ? 1.0 : 0.5 }
        if rg <= 0.02 && b <= 0.035 { return .init(thresholds: t, vision: .normal, severity: 0) }
        if rg > 0.04 && b > 0.06 { return .init(thresholds: t, vision: .achromat, severity: 1) }
        if rg > 0.02 && rg >= b * 0.8 {
            // Häufiger ist Grün-Schwäche – bei unklarem Unterschied lieber die.
            let v: ColorVision = p > d * 1.25 ? .protan : .deutan
            return .init(thresholds: t, vision: v, severity: sev(rg))
        }
        return .init(thresholds: t, vision: .tritan, severity: sev(b))
    }

    static func selfTest() {
        precondition(classify([0.006, 0.007, 0.01]).vision == .normal)
        precondition(classify([0.09, 0.05, 0.012]).vision == .protan)
        let deut = classify([0.03, 0.08, 0.015])
        precondition(deut.vision == .deutan && deut.severity == 1)
        precondition(classify([0.03, 0.025, 0.012]).severity == 0.5)
        precondition(classify([0.008, 0.009, 0.08]).vision == .tritan)
        // Farbmathematik: Grau bleibt grau; Ringfarbe für einen simulierten Dichromaten kaum vom Grau zu unterscheiden.
        let g = ColorMath.linear(u: ColorMath.white.u, v: ColorMath.white.v, Y: 0.2)!
        precondition(abs(g[0] - g[1]) < 0.01 && abs(g[1] - g[2]) < 0.01, "D65-Grau")
        for a in ColorAxis.allCases {
            let dm = ColorMath.maxD(a)
            precondition(dm > 0.03, "Achse \(a) zu klein darstellbar: \(dm)")
            let p = ColorMath.uv(a, dm)
            let c = ColorMath.linear(u: p.u, v: p.v, Y: 0.16)!, bg = ColorMath.linear(u: ColorMath.white.u, v: ColorMath.white.v, Y: 0.16)!
            func dist(_ x: [Double], _ y: [Double]) -> Double { sqrt(zip(x, y).map { ($0 - $1) * ($0 - $1) }.reduce(0, +)) }
            let normal = dist(c, bg)
            let seen = dist(ColorVision.apply(a.vision.simulation, c), ColorVision.apply(a.vision.simulation, bg))
            precondition(seen < normal * 0.35, "Verwechslungslinie \(a): \(seen) vs \(normal)")
        }
        var s = Staircase(d: 0.06, maxD: 0.1)
        for _ in 0..<20 { s.answer(s.d > 0.01) }   // Beobachter mit Schwelle 0,01
        precondition(s.done && s.threshold > 0.005 && s.threshold < 0.02, "Treppe: \(s.threshold)")
        print("✓ Farbsehtest")
    }
}

// MARK: - Ablauf

struct ColorTest {
    enum Phase { case intro, trial, result }
    var phase = Phase.intro
    var stairs: [Staircase] = ColorAxis.allCases.map { Staircase(d: 0.06, maxD: ColorMath.maxD($0)) }
    var axis = ColorAxis.protan
    var gap = 0                 // 0 = oben, 1 = unten, 2 = links, 3 = rechts
    var seed: UInt64 = 1
    var result: ColorTestResult?

    var progress: Double {
        let total = stairs.reduce(0) { $0 + min($1.trials, 16) }
        return stairs.allSatisfy(\.done) ? 1 : min(Double(total) / 36, 0.97)
    }

    mutating func next() {
        let open = ColorAxis.allCases.filter { !stairs[$0.rawValue].done }
        guard let a = open.randomElement() else {
            phase = .result
            result = .classify(stairs.map(\.threshold))
            return
        }
        axis = a
        gap = Int.random(in: 0..<4)
        seed = UInt64.random(in: 1...UInt64.max)
        phase = .trial
    }

    mutating func answer(_ dir: Int?) {
        stairs[axis.rawValue].answer(dir == gap)
        next()
    }
}

extension AppState {
    func startColorTest() {
        colorTest = ColorTest()
        formFocus = 0
        sheet = .colorTest
        applyDisplayFilter()   // während des Tests: keine Farbanpassung, kein Stil-Filter
    }

    func handleColorTest(_ e: PadEvent) {
        switch colorTest.phase {
        case .intro:
            if handleBack(e, close: { closeColorTest() }) { return }
            switch e {
            case .up: backFocus = true
            case .a: colorTest.next()
            case .b: closeColorTest()
            default: break
            }
        case .trial:
            switch e {
            case .up: colorTest.answer(0)
            case .down: colorTest.answer(1)
            case .left: colorTest.answer(2)
            case .right: colorTest.answer(3)
            case .a: colorTest.answer(nil)       // „kein Ring zu sehen“
            case .b: closeColorTest()
            default: break
            }
        case .result:
            switch e {
            case .left, .right: formFocus = formFocus == 0 ? 1 : 0
            case .a: if formFocus == 0 { adoptColorTest() } else { closeColorTest() }
            case .b: closeColorTest()
            default: break
            }
        }
    }

    func adoptColorTest() {
        if let r = colorTest.result {
            colorVisionSeverity = r.vision == .normal ? 1 : r.severity
            colorVision = r.vision
        }
        closeColorTest()
    }

    func closeColorTest() {
        sheet = setupFlow ? .genres : .access   // in der Einrichtung weiter zu den Genres
        applyDisplayFilter()
    }
}

/// Punktfeld mit Landolt-Ring – immer ohne Farbfilter der App (der Test misst die echten Farben).
struct DotPlate: View {
    let axis: ColorAxis
    let d: Double
    let gap: Int
    let seed: UInt64

    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix(seed: seed)
            let r = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var dots: [(CGPoint, CGFloat)] = []
            // Punkte zufällig, ohne Überlappung (einfaches Ausprobieren reicht bei ~2500 Versuchen).
            for _ in 0..<2600 {
                let rad = r * CGFloat(0.014 + rng.next() * 0.026)
                let a = rng.next() * 2 * .pi, dist = (rng.next()).squareRoot() * (r - rad)
                let p = CGPoint(x: center.x + CGFloat(cos(a)) * dist, y: center.y + CGFloat(sin(a)) * dist)
                if dots.allSatisfy({ hypot($0.0.x - p.x, $0.0.y - p.y) > $0.1 + rad + r * 0.004 }) { dots.append((p, rad)) }
            }
            let gapAngle: Double = [-.pi / 2, .pi / 2, .pi, 0][gap]
            for (p, rad) in dots {
                let dx = Double(p.x - center.x), dy = Double(p.y - center.y)
                let dr = (dx * dx + dy * dy).squareRoot() / Double(r)
                var ang = atan2(dy, dx) - gapAngle
                ang = atan2(sin(ang), cos(ang))
                let inRing = dr > 0.36 && dr < 0.66 && abs(ang) > 0.42
                let Y = ColorMath.levels[Int(rng.next() * Double(ColorMath.levels.count)) % ColorMath.levels.count]
                let c = ColorMath.color(inRing ? axis : nil, inRing ? d : 0, Y: Y)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2)), with: .color(c))
            }
        }
        .accessibilityLabel(tr("Punktfeld mit Ring – wo ist die Lücke?"))
    }
}

/// Kleiner, reproduzierbarer Zufall (gleiches Muster beim Neuzeichnen).
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}

struct ColorTestPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        let t = state.colorTest
        switch t.phase {
        case .intro:
            OverlayPage(title: tr("Farbsehen testen"),
                        step: state.setupFlow ? tr("Schritt %@ von %@", 5, 6) : nil,
                        intro: tr("Du siehst ein Punktfeld mit einem Ring, der an einer Stelle offen ist. Zeig mit dem Steuerkreuz, wo die Lücke ist – oben, unten, links oder rechts. Siehst du keinen Ring, drück A. Die Farben werden immer schwächer, bis es schwer wird. Dauer etwa 2 Minuten."),
                        close: { state.closeColorTest() },
                        hints: state.backFocus ? [("A", tr("Zurück"))] : [("A", tr("Test starten")), ("B", state.setupFlow ? tr("Später") : tr("Abbrechen"))]) {
                VStack(alignment: .leading, spacing: 14) {
                    Label(tr("Kein medizinischer Test: Fernseher und Raumlicht verändern Farben. Für eine Diagnose: Augenarzt."),
                          systemImage: "info.circle")
                        .font(.read(16)).dimText(0.85)
                    Label(tr("Bildmodus am Fernseher am besten auf „Film“ oder „Kino“, Raum nicht zu hell."), systemImage: "tv")
                        .font(.read(16)).dimText(0.85)
                    Button { state.colorTest.next() } label: {
                        Text(tr("Test starten")).font(.read(19, weight: .bold))
                            .padding(.horizontal, 30).padding(.vertical, 13)
                            .foregroundColor(Ink.bg)
                            .background(Capsule().fill(theme.bold ? theme.p.accent : Ink.fg))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
            }
        case .trial:
            trial(t)
        case .result:
            result(t)
        }
    }

    private func trial(_ t: ColorTest) -> some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()   // neutraler Grund, unabhängig vom Stil
            VStack(spacing: 22 * Metrics.s) {
                ProgressView(value: t.progress).frame(width: 420 * Metrics.s).tint(Color.white)
                GeometryReader { g in
                    let side = min(g.size.width, g.size.height)
                    DotPlate(axis: t.axis, d: t.stairs[t.axis.rawValue].d, gap: t.gap, seed: t.seed)
                        .frame(width: side, height: side)
                        .position(x: g.size.width / 2, y: g.size.height / 2)
                }
                // Für Maus/Tastatur: Pfeilknöpfe; am Controller das Steuerkreuz.
                HStack(spacing: 14) {
                    ForEach([(2, "arrow.left"), (0, "arrow.up"), (1, "arrow.down"), (3, "arrow.right")], id: \.0) { dir, sym in
                        Button { state.colorTest.answer(dir) } label: {
                            Image(systemName: sym).font(.ui(22, weight: .bold)).frame(width: 56 * Metrics.s, height: 46 * Metrics.s)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                        }.buttonStyle(.plain)
                    }
                    Button { state.colorTest.answer(nil) } label: {
                        Text(tr("Kein Ring")).font(.read(17, weight: .semibold)).padding(.horizontal, 18).frame(height: 46 * Metrics.s)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }.buttonStyle(.plain)
                }
                FlowLayout(spacing: 22, lineSpacing: 8) {
                    Hint(glyph: .symbol("dpad"), text: tr("Wo ist die Lücke?"))
                    Hint(glyph: .letter("A", .green), text: tr("Kein Ring zu sehen"))
                    Hint(glyph: .letter("B", .red), text: tr("Abbrechen"))
                }
                .font(.read(15, weight: .medium))
            }
            .foregroundColor(Color.white)
            .padding(.vertical, 30)
        }
    }

    private func result(_ t: ColorTest) -> some View {
        let r = t.result ?? .classify([0, 0, 0])
        return OverlayPage(title: tr("Ergebnis"), intro: r.text, close: { state.closeColorTest() },
                           hints: [("dpad", tr("Auswahl")), ("A", "OK"), ("B", tr("Schließen"))]) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ColorAxis.allCases, id: \.rawValue) { a in
                    let v = r.thresholds[a.rawValue], maxD = t.stairs[a.rawValue].maxD
                    HStack(spacing: 14) {
                        Text([tr("Rot-Achse"), tr("Grün-Achse"), tr("Blau-Achse")][a.rawValue]).font(.read(18, weight: .semibold))
                            .frame(width: 150 * Metrics.text(18), alignment: .leading)
                        // Balken: wie stark die Farbe sein musste (kurz = feines Farbsehen)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Ink.fg.opacity(0.12))
                                Capsule().fill(Ink.fg.opacity(0.85)).frame(width: max(g.size.width * min(v / maxD, 1), 8))
                            }
                        }
                        .frame(width: 420 * Metrics.s, height: 14 * Metrics.s)
                        Text(v >= maxD * 0.99 ? tr("nicht erkannt") : v <= 0.02 ? tr("fein") : tr("erhöht")).font(.read(16)).dimText(0.85)
                    }
                }
                if r.vision != .normal {
                    Text(tr("Empfehlung: Farben für „%@“ anpassen.", r.vision.title)).font(.read(18, weight: .semibold)).padding(.top, 8)
                }
                HStack(spacing: 16) {
                    pill(r.vision == .normal ? tr("Normal übernehmen") : tr("Anpassung übernehmen"), 0) { state.adoptColorTest() }
                    pill(tr("Nicht übernehmen"), 1) { state.closeColorTest() }
                }
                .padding(.top, 10)
            }
        }
    }

    private func pill(_ text: String, _ i: Int, action: @escaping () -> Void) -> some View {
        let on = state.formFocus == i
        return Button(action: action) {
            Text(text).font(.read(19, weight: .bold)).fixedSize()
                .padding(.horizontal, 26).padding(.vertical, 13)
                .foregroundColor(on ? Ink.bg : Ink.fg)
                .background(Capsule().fill(on ? (theme.bold ? theme.p.accent : Ink.fg) : Ink.fg.opacity(0.12)))
                .overlay(Capsule().strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: 4).padding(-7).opacity(on ? 1 : 0))
        }
        .buttonStyle(.plain)
    }
}
