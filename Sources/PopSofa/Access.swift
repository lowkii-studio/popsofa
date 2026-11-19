import SwiftUI
import AppKit
import CoreImage

// MARK: - Schrift für den Stil „Klar“

/// Atkinson Hyperlegible Next (Braille Institute): eindeutige Formen für l/I/1, 0/O, b/d – für Sehschwäche gemacht.
enum Typo {
    static let atkinson = "Atkinson Hyperlegible Next"
    /// Schriftfamilie des aktiven Stils; nil = Systemschrift.
    static var family: String?

    /// Einmal beim Start aus dem App-Bundle laden (nur für PopSofa, nicht systemweit).
    static func register() {
        guard let url = Bundle.main.url(forResource: "AtkinsonHyperlegibleNext", withExtension: "woff2", subdirectory: "Fonts")
        else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// Ruhiger Modus (Stile „Klar“): keine Vergrößerung beim Auswählen – skalierte Schrift flimmert beim Animieren.
    static var calm = false
    /// Alle Lesbarkeits-Stile (auch Pop hell): kein Text auf Bildern, ruhige Tastenfarben.
    static var prism = false

    static func update(for theme: Theme) {
        calm = theme == .clear || theme == .clearLight
        prism = theme.isClear
        Ink.light = theme.isLight
        Ink.boldLight = theme == .popLight
        family = theme.isClear && NSFont(name: "AtkinsonHyperlegibleNext-Regular", size: 12) != nil ? atkinson : nil
    }

    /// Eine Stufe kräftiger: dünne Striche flimmern bei Prismen/Astigmatismus zuerst.
    static func heavier(_ w: Font.Weight) -> Font.Weight {
        switch w {
        case .ultraLight, .thin, .light: return .regular
        case .regular: return .medium
        case .medium: return .semibold
        case .semibold: return .bold
        case .bold: return .heavy
        default: return w
        }
    }
}

// MARK: - Farbsehen: Anpassung (Daltonisierung) und Simulation

/// Farbsehschwäche. Matrizen nach Machado, Oliveira & Fernandes (2009), Schweregrad 1,0, lineares RGB.
enum ColorVision: String, CaseIterable {
    case normal, protan, deutan, tritan, achromat

    var title: String {
        switch self {
        case .normal: return tr("Normales Farbsehen")
        case .protan: return tr("Rot-Schwäche (Protanopie)")
        case .deutan: return tr("Grün-Schwäche (Deuteranopie)")
        case .tritan: return tr("Blau-Gelb-Schwäche (Tritanopie)")
        case .achromat: return tr("Keine Farben (Achromatopsie)")
        }
    }

    var hint: String {
        switch self {
        case .normal: return tr("Farben unverändert")
        case .protan, .deutan: return tr("Farben werden verschoben, damit Rot und Grün unterscheidbar bleiben")
        case .tritan: return tr("Farben werden verschoben, damit Blau und Gelb unterscheidbar bleiben")
        case .achromat: return tr("Keine Farbverschiebung möglich – PopSofa zeigt Zustände zusätzlich mit Symbolen und Text")
        }
    }

    typealias M = [[Double]]
    static let identity: M = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]

    /// Stärke (0…1) aus dem Farbsehtest; dazwischen wird linear gemischt (Näherung an Machados Stufen).
    static var severity = 1.0

    /// So sieht ein Mensch mit dieser Schwäche die Farben.
    var simulation: M {
        let full = fullSimulation, s = Self.severity
        return (0..<3).map { i in (0..<3).map { j in Self.identity[i][j] + s * (full[i][j] - Self.identity[i][j]) } }
    }

    private var fullSimulation: M {
        switch self {
        case .normal: return Self.identity
        case .protan: return [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]
        case .deutan: return [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]
        case .tritan: return [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]]
        case .achromat: return Array(repeating: [0.2126, 0.7152, 0.0722], count: 3)
        }
    }

    /// Anpassung: Was die Schwäche verschluckt, wird auf Kanäle verschoben, die noch unterscheidbar sind
    /// (Daltonisierung: M = I + D · (I − S)). Ohne Farben hilft keine Farbverschiebung – da tragen Symbole.
    var adaptation: M {
        let d: M
        switch self {
        case .normal, .achromat: return Self.identity
        case .protan, .deutan: d = [[0, 0, 0], [0.7, 1, 0], [0.7, 0, 1]]
        case .tritan: d = [[1, 0, 0.7], [0, 1, 0.7], [0, 0, 0]]
        }
        let err = Self.sub(Self.identity, simulation)
        return Self.add(Self.identity, Self.mul(d, err))
    }

    static func mul(_ a: M, _ b: M) -> M {
        (0..<3).map { i in (0..<3).map { j in (0..<3).reduce(0) { $0 + a[i][$1] * b[$1][j] } } }
    }
    static func add(_ a: M, _ b: M) -> M { (0..<3).map { i in (0..<3).map { a[i][$0] + b[i][$0] } } }
    static func sub(_ a: M, _ b: M) -> M { (0..<3).map { i in (0..<3).map { a[i][$0] - b[i][$0] } } }
    static func apply(_ m: M, _ v: [Double]) -> [Double] {
        (0..<3).map { i in min(max((0..<3).reduce(0) { $0 + m[i][$1] * v[$1] }, 0), 1) }
    }
}

/// Kontraststufe der Klar-Stile: Abstand zwischen hellster und dunkelster Farbe (WCAG-Verhältnis).
/// Je kleiner, desto weniger Überstrahlen und Farbsäume an Schriftkanten (Prismenbrille, Astigmatismus).
enum ClearContrast: String, CaseIterable {
    case strong, medium, soft
    var ratio: Double { [14, 10, 7][Self.allCases.firstIndex(of: self)!] }
    var title: String { [tr("Stark (14:1)"), tr("Mittel (10:1)"), tr("Sanft (7:1)")][Self.allCases.firstIndex(of: self)!] }
    var next: ClearContrast { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
}

/// Farbfilter über dem ganzen Fenster: Farbsehen-Anpassung → Stil „Klar“ (gegen Überstrahlen) → Simulation.
enum DisplayFilter {
    /// Linearer Farbraum. Hellste Farbe dunkel: 0,82 (≈ #EBEBEB), hell: 0,74 (Papier statt Reinweiß – blendet weniger).
    /// Dunkelste Farbe ergibt sich aus der Kontraststufe; dazu 25 % weniger Sättigung (kräftige Farben säumen am stärksten).
    static let saturation = 0.75

    /// Hell: Abendmodus – hellste Farbe nur 0,58 (≈ #C8 statt #FF) und warm getönt (weniger Blau, wie Night Shift).
    static let warm = [1.0, 0.93, 0.78]

    static func levels(_ theme: Theme, _ contrast: ClearContrast) -> (white: Double, black: Double) {
        let light = theme.isLight
        let w = light ? 0.58 : 0.82
        // Helligkeit des (getönten) Weiß bestimmt, wie dunkel Schwarz sein muss.
        let wl = light ? w * (0.2126 * warm[0] + 0.7152 * warm[1] + 0.0722 * warm[2]) : w
        return (w, max((wl + 0.05) / contrast.ratio - 0.05, 0))
    }

    static func matrix(theme: Theme, vision: ColorVision, simulate: Bool, contrast: ClearContrast = .strong) -> (m: ColorVision.M, bias: Double) {
        var m = vision.adaptation, bias = 0.0
        if theme.isClear {
            let (w, b) = levels(theme, contrast)
            let lum = [0.2126, 0.7152, 0.0722]
            let sv = theme == .popLight ? 0.9 : saturation   // Pastelltöne sind schon sanft
            let sat: ColorVision.M = (0..<3).map { i in (0..<3).map { j in (1 - sv) * lum[j] + (i == j ? sv : 0) } }
            m = ColorVision.mul(sat, m).map { $0.map { $0 * (w - b) } }
            if theme.isLight { m = (0..<3).map { i in m[i].map { $0 * warm[i] } } }
            bias = b
        }
        if simulate { m = ColorVision.mul(vision.simulation, m) }   // Bias ist grau → bleibt grau
        return (m, bias)
    }

    static var current: CIFilter?

    /// Auf alle PopSofa-Fenster anwenden (Hauptfenster, Tastatur, Hinweise).
    @MainActor static func apply(theme: Theme, vision: ColorVision, simulate: Bool, contrast: ClearContrast = .strong) {
        let (m, bias) = matrix(theme: theme, vision: vision, simulate: simulate, contrast: contrast)
        let isIdentity = m == ColorVision.identity && bias == 0
        current = isIdentity ? nil : filter(m, bias)
        for w in NSApp.windows {
            guard let v = w.contentView else { continue }
            v.wantsLayer = true
            v.layerUsesCoreImageFilters = true
            v.contentFilters = current.map { [$0] } ?? []
        }
    }

    static func filter(_ m: ColorVision.M, _ bias: Double) -> CIFilter? {
        guard let f = CIFilter(name: "CIColorMatrix") else { return nil }
        f.setValue(CIVector(x: m[0][0], y: m[0][1], z: m[0][2], w: 0), forKey: "inputRVector")
        f.setValue(CIVector(x: m[1][0], y: m[1][1], z: m[1][2], w: 0), forKey: "inputGVector")
        f.setValue(CIVector(x: m[2][0], y: m[2][1], z: m[2][2], w: 0), forKey: "inputBVector")
        f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        f.setValue(CIVector(x: bias, y: bias, z: bias, w: 0), forKey: "inputBiasVector")
        return f
    }

    /// Für Test-Screenshots: denselben Filter aufs Bild rechnen (cacheDisplay zeigt Ebenen-Filter nicht).
    static func render(_ rep: NSBitmapImageRep) -> Data? {
        guard let f = current, let img = CIImage(bitmapImageRep: rep) else { return rep.representation(using: .png, properties: [:]) }
        f.setValue(img, forKey: kCIInputImageKey)
        guard let out = f.outputImage, let cg = CIContext().createCGImage(out, from: img.extent) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    static func selfTest() {
        func lin(_ hex: String) -> [Double] {
            var v: UInt64 = 0
            Scanner(string: String(hex.dropFirst())).scanHexInt64(&v)
            return [16, 8, 0].map { s in
                let c = Double((v >> UInt64(s)) & 0xFF) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
        }
        func dist(_ a: [Double], _ b: [Double]) -> Double { sqrt(zip(a, b).map { ($0 - $1) * ($0 - $1) }.reduce(0, +)) }
        // Rot/Grün (Gefällt mir / Nicht mein Fall): mit Grün-Schwäche ohne Anpassung kaum zu trennen, mit deutlich besser.
        let red = lin("#C62828"), green = lin("#2E7D32")
        for v in [ColorVision.deutan, .protan] {
            let s = v.simulation, a = v.adaptation
            let before = dist(ColorVision.apply(s, red), ColorVision.apply(s, green))
            let after = dist(ColorVision.apply(s, ColorVision.apply(a, red)), ColorVision.apply(s, ColorVision.apply(a, green)))
            precondition(after > before * 1.5, "Anpassung \(v) trennt Rot/Grün nicht besser (\(before) → \(after))")
        }
        precondition(ColorVision.normal.adaptation == ColorVision.identity)
        // Stil „Klar“: Weiß/Schwarz nach Filter zwischen 7:1 und 16:1
        for t in [Theme.clear, .clearLight, .popLight] {
            for c in ClearContrast.allCases {
                let (m, b) = matrix(theme: t, vision: .normal, simulate: false, contrast: c)
                let rows = m.map { $0.reduce(0, +) + b }
                let white = 0.2126 * rows[0] + 0.7152 * rows[1] + 0.0722 * rows[2], black = b
                let ratio = (white + 0.05) / (black + 0.05)
                // Hell ist abends gedimmt: „Stark“ erreicht dort, was mit dem dunkleren Weiß möglich ist (≈ 11:1).
                let target = min(c.ratio, (white + 0.05) / 0.05)
                precondition(abs(ratio - target) < 0.6 && ratio >= 6.99, "Kontrast \(t) \(c): \(ratio)")
            }
        }
        print("✓ Farbsehen & Stil Klar")
    }
}

// MARK: - Seite „Barrierefreiheit“

extension AppState {
    /// Zeilen: 0 = Stil „Klar“, 1 = Farbsehtest, 2…6 = Farbsehen, 7 = Simulation, 8 = Fertig.
    static let accessRows = 5 + ColorVision.allCases.count + 1   // 0 Klar, 1 Kontrast, 2 Test, 3… Farbsehen, Simulation, Prismen, Fertig

    func applyDisplayFilter() {
        Typo.update(for: theme)
        ColorVision.severity = colorVisionSeverity
        // Beim Farbsehtest zählen die echten Farben – kein Filter.
        if sheet == .colorTest { DisplayFilter.apply(theme: .apple, vision: .normal, simulate: false); return }
        DisplayFilter.apply(theme: theme, vision: colorVision, simulate: simulateVision && colorVision != .normal, contrast: clearContrast)
    }

    func chooseAccess(_ i: Int) {
        formFocus = i
        let visions = ColorVision.allCases
        switch i {
        case 0: chooseReadableStyle()   // Auswahlliste statt Weiterschalten
        case 1: chooseContrast()
        case 2:
            startColorTest()
        case 3...visions.count + 2:
            colorVision = visions[i - 3]
            colorVisionSeverity = 1   // von Hand gewählt: volle Anpassung
            if colorVision == .normal { simulateVision = false }
        case visions.count + 3:
            if colorVision != .normal { simulateVision.toggle() }
        case visions.count + 4:
            startPrismTest()
        default:
            sheet = nil
        }
    }

    func handleAccess(_ e: PadEvent) {
        if handleBack(e, close: { sheet = nil }) { return }
        switch e {
        case .up: if formFocus == 0 { backFocus = true } else { formFocus -= 1 }
        case .down: formFocus = min(formFocus + 1, Self.accessRows - 1)
        case .a: chooseAccess(formFocus)
        case .b: sheet = nil
        default: break
        }
    }
}

struct AccessPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        let visions = ColorVision.allCases
        OverlayPage(title: tr("Barrierefreiheit"),
                    intro: tr("Ein Stil für beste Lesbarkeit und Farben, die zu deinem Farbsehen passen. Mit „Simulation“ siehst du die App so, wie jemand mit dieser Farbsehschwäche sie sieht."),
                    close: { state.sheet = nil },
                    hints: state.backFocus ? [("A", tr("Zurück"))] : [("dpad", tr("Auswahl")), ("A", tr("Ändern")), ("B", tr("Fertig"))]) {
            FocusScroll(axis: .vertical, target: "r\(state.formFocus)", position: 0.45, space: "access", wheel: true) {
                VStack(alignment: .leading, spacing: 10 * Metrics.s) {
                    section(tr("Lesbarkeit"))
                    row(0, symbol: state.theme.isClear ? "textformat" : "square",
                        title: tr("Lesbarkeits-Stil: %@", state.theme.isClear ? state.theme.title : tr("Aus")) + "  ›",
                        detail: tr("Atkinson-Hyperlegible-Schrift, kräftiger, ruhige Flächen, keine Vergrößerung beim Auswählen. Hell ist bei Hornhautverkrümmung oft angenehmer."))
                    row(1, symbol: "circle.lefthalf.filled",
                        title: tr("Kontrast: %@", state.clearContrast.title) + "  ›",
                        detail: state.theme.isClear ? tr("Weniger Kontrast = weniger Blitzen und Farbsäume an Schriftkanten. Sanft ist noch AAA-lesbar.") : tr("Gilt für die Stile „Klar“"))
                        .opacity(state.theme.isClear ? 1 : 0.6)
                    section(tr("Farbsehen"))
                    row(2, symbol: "circle.dotted.circle", title: tr("Farbsehen testen (ca. 2 Min.)"),
                        detail: tr("Punktfeld mit Ring – findet heraus, welche Farben du schwer unterscheidest, und schlägt die passende Anpassung vor"))
                    ForEach(Array(visions.enumerated()), id: \.offset) { k, v in
                        row(k + 3, symbol: state.colorVision == v ? "largecircle.fill.circle" : "circle", title: v.title,
                            detail: v.hint)
                    }
                    section(tr("Testen"))
                    row(visions.count + 3, symbol: state.simulateVision ? "checkmark.square.fill" : "square",
                        title: tr("Simulation: so sieht es mit dieser Schwäche aus"),
                        detail: state.colorVision == .normal ? tr("Erst oben eine Farbsehschwäche wählen") : tr("Gilt für die ganze App, bis du sie ausschaltest"))
                        .opacity(state.colorVision == .normal ? 0.6 : 1)
                    row(visions.count + 4, symbol: "eyeglasses", title: tr("Prismen-Check"),
                        detail: tr("Für Brillen mit Prismen: prüft, ob ein heller Stil angenehmer ist"))
                    swatches.padding(.top, 8)
                    let on = !state.backFocus && state.formFocus == AppState.accessRows - 1
                    Button { state.sheet = nil } label: {
                        Text(tr("Fertig")).font(.read(18, weight: .bold))
                            .padding(.horizontal, 30).padding(.vertical, 13)
                            .foregroundColor(Ink.bg)
                            .background(Capsule().fill(theme.bold ? theme.p.accent : Ink.fg))
                            .overlay(Capsule().strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: 4).padding(-7).opacity(on ? 1 : 0))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .scrollAnchor("r\(AppState.accessRows - 1)", in: "access")
                }
                .padding(.vertical, 8)
                .frame(maxWidth: 1000 * Metrics.text(18), alignment: .leading)
            }
        }
    }

    private func section(_ t: String) -> some View {
        Text(t.uppercased()).font(.ui(15, weight: .heavy)).tracking(1).dimText(0.85).padding(.top, 10)
    }

    private func row(_ i: Int, symbol: String, title: String, detail: String) -> some View {
        let on = !state.backFocus && state.formFocus == i
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.ui(24, weight: .semibold)).frame(width: 34 * Metrics.text(24))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.read(19, weight: .semibold))
                Text(detail).font(.read(15)).dimText(0.85).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundColor(Ink.fg)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(shape.fill(Ink.bg.opacity(on ? 0.45 : 0.22)))
        .overlay(shape.strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: 4).opacity(on ? 1 : 0))
        .contentShape(Rectangle())
        .onTapGesture { state.chooseAccess(i) }
        .scrollAnchor("r\(i)", in: "access")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Farbproben aus der App: Tasten und Bewertungen – zum Vergleichen mit und ohne Simulation.
    private var swatches: some View {
        FlowLayout(spacing: 16, lineSpacing: 10, centered: false) {
            Hint(glyph: .letter("A", .green), text: tr("Ansehen"))
            Hint(glyph: .letter("B", .red), text: tr("Zurück"))
            Hint(glyph: .letter("X", .blue), text: tr("Gefällt mir"))
            Hint(glyph: .letter("Y", .yellow), text: tr("Nicht mein Fall"))
            chip(tr("Ausgewählt"), "#2E7D32", "checkmark.circle.fill")
            chip(tr("Löschen"), "#B3261E", "trash.fill")
        }
        .font(.read(15, weight: .medium))
    }

    private func chip(_ t: String, _ hex: String, _ symbol: String) -> some View {
        Label(t, systemImage: symbol).font(.read(15, weight: .semibold))
            .foregroundColor(Ink.fg)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(Color(hex: hex)))
    }
}
