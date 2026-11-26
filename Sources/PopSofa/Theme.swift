import SwiftUI
import AppKit

/// Gestaltung: ruhiges Apple-TV-Glas, knalliges Pop-Art (Comic, Rasterpunkte) oder Webmuster (gewebte Bänder und Erdtöne, angelehnt an Kente).
enum Theme: String, CaseIterable {
    case apple, pop, woven, clear, clearLight, popLight
    /// Gespeicherter Stil; „afro“ hieß der Stil „Webmuster“ bis Version 1.0.
    static func stored(_ s: String) -> Theme? { Theme(rawValue: s == "afro" ? "woven" : s) }
    var title: String {
        switch self {
        case .apple: return "Apple"; case .pop: return "Pop-Art"; case .woven: return tr("Webmuster")
        case .clear: return tr("Klar dunkel"); case .clearLight: return tr("Klar hell"); case .popLight: return tr("Pop hell (Prismen)")
        }
    }
    /// Lesbarkeits-Stile (Atkinson-Schrift, ruhige Flächen, gedämpfter Kontrast).
    var isClear: Bool { self == .clear || self == .clearLight || self == .popLight }
    /// Helle Stile: dunkle Schrift auf warmem Grund, abends gedimmt.
    var isLight: Bool { self == .clearLight || self == .popLight }
    /// Seitengrund der ruhigen Stile (Apple, Klar, Pop hell).
    var pageHex: String {
        switch self {
        case .clear: return "#1E2024"
        case .clearLight: return "#E2D6C2"
        case .popLight: return "#F1E3CA"
        default: return "#0A0A0F"
        }
    }
    /// Pop, Webmuster und Pop hell teilen den grafischen Stil: flache Flächen, Kontur, harte Schatten.
    /// „Klar“ baut auf dem ruhigen Apple-Stil auf (siehe Access.swift).
    var bold: Bool { self == .pop || self == .woven || self == .popLight }
    var p: Pop { self == .woven ? .woven : self == .popLight ? .popLight : .pop }
    /// Akzentfarbe als Schrift: auf hellem Grund wäre Gelb unlesbar – dort Tinte.
    var accentText: Color { self == .popLight ? Color(hex: Pop.inkHexLight) : p.accent }
    var next: Theme { let a = Self.allCases; return a[(a.firstIndex(of: self)! + 1) % a.count] }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme.apple }

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Palette der grafischen Stile.
struct Pop {
    let bgHex: String, accentHex: String
    let paper: Color, card: Color, dots: Color
    let font: String, fontScale: CGFloat
    /// Flache Farben statt Verläufen für die Dienst-Kacheln.
    let tiles: [String]
    /// Farbrichtungen für Dienst-Kacheln (rot, blau …) in der Stil-Palette.
    let tones: [String: String]
    var bg: Color { Color(hex: bgHex) }
    var accent: Color { Color(hex: accentHex) }

    /// Pop-Art (aus dem App-Icon abgeleitet): tiefes Petrol, Comic-Gelb.
    static let pop = Pop(bgHex: "#0E5E66", accentHex: "#FFD23F",
                         paper: Color(hex: "#FFF8E7"), card: Color(hex: "#2F6FDB"), dots: Color(hex: "#36C5C9"),
                         font: "Futura-CondensedExtraBold", fontScale: 1.12,
                         tiles: ["#EF3E36", "#FFD23F", "#FF5DA2", "#2F6FDB", "#36C5C9", "#7BC950", "#FF8C42"],
                         tones: ["red": "#EF3E36", "orange": "#FF8C42", "yellow": "#FFD23F", "green": "#7BC950",
                                 "cyan": "#36C5C9", "blue": "#2F6FDB", "purple": "#9B5DE5", "pink": "#FF5DA2",
                                 "ink": "#2B2D42"])
    /// Pop hell (Prismen): volles Pop-Art auf Creme – kräftige Comic-Farben, Raster, Konturen, Versatzschatten.
    /// Nur wo Text auf Fläche liegt, wird beruhigt: Kachelnamen auf Papier-Etiketten, kaum sichtbare Punkte
    /// auf der Seite, Tinte statt Schwarz, kein Schatten hinter Schrift (siehe `Typo.prism`).
    static let popLight = Pop(bgHex: "#F1E3CA", accentHex: "#FFC93C",
                              paper: Color(hex: "#FFF7E8"), card: Color(hex: "#2F6FDB"), dots: Color(hex: "#D2B98F"),
                              font: "Futura-CondensedExtraBold", fontScale: 1.12,
                              tiles: ["#EF3E36", "#FFD23F", "#FF5DA2", "#2F6FDB", "#36C5C9", "#7BC950", "#FF8C42"],
                              tones: ["red": "#EF3E36", "orange": "#FF8C42", "yellow": "#FFD23F", "green": "#7BC950",
                                      "cyan": "#36C5C9", "blue": "#2F6FDB", "purple": "#9B5DE5", "pink": "#FF5DA2",
                                      "ink": "#2B2D42"])
    /// Dunkle Tinte (Schrift, Linien) für Pop hell – weicher als Schwarz.
    static let inkHexLight = "#2B2622"
    var inkHex: String { Self.inkHexLight }

    /// Webmuster: Kakao-Braun, Kente-Gold, Rot, Grün, Terrakotta, Ocker, Indigo; Schlamm-Tuch-Creme als Papier.
    static let woven = Pop(bgHex: "#3B1F14", accentHex: "#F4B63F",
                          paper: Color(hex: "#F2E2C4"), card: Color(hex: "#D9822B"), dots: Color(hex: "#C8552B"),
                          font: "Rockwell-Bold", fontScale: 1.0,
                          tiles: ["#F4B63F", "#C1272D", "#1E7A46", "#D9822B", "#7A2E5D", "#E3A13B", "#2A8C82"],
                          tones: ["red": "#C1272D", "orange": "#D9822B", "yellow": "#F4B63F", "green": "#1E7A46",
                                  "cyan": "#2A8C82", "blue": "#2D4F8A", "purple": "#7A2E5D", "pink": "#B8476A",
                                  "ink": "#2A1810"])

    /// Schwarz oder Weiß – je nachdem, was auf der Fläche den höheren Kontrast hat (WCAG).
    static func textOn(_ hex: String) -> Color { textHexOn(hex) == "#000000" ? .black : .white }
    static func textHexOn(_ hex: String) -> String {
        Contrast.ratio(hex, "#000000") >= Contrast.ratio(hex, "#FFFFFF") ? "#000000" : "#FFFFFF"
    }

    /// Stil-Farbe in Richtung der Markenfarbe: feste Zuordnung für bekannte Dienste,
    /// sonst nach Farbton (dunkle/graue Marken → „ink“).
    func tone(for s: Service) -> String {
        if let t = Catalog.tones[s.id], let hex = tones[t] { return hex }
        let c = NSColor(Color(hex: s.colorTop)).usingColorSpace(.sRGB) ?? NSColor.black
        if c.brightnessComponent < 0.3 || c.saturationComponent < 0.2 { return tones["ink"] ?? "#000000" }
        let hue = c.hueComponent * 360
        func dist(_ hex: String) -> CGFloat {
            let h = (NSColor(Color(hex: hex)).usingColorSpace(.sRGB)?.hueComponent ?? 0) * 360
            let d = abs(h - hue).truncatingRemainder(dividingBy: 360)
            return min(d, 360 - d)
        }
        return tones.filter { $0.key != "ink" }.values.min { dist($0) < dist($1) } ?? tiles[0]
    }

    /// Feste Kachelfarbe je Dienst (gleiche Farbe bei jedem Start, auch auf dem iPhone).
    func tile(for id: String) -> String {
        let i = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return tiles[i % tiles.count]
    }
}

/// Rasterpunkte wie im Comic-Druck; Punkte werden nach unten größer.
struct Halftone: View {
    var color: Color = Ink.bg
    var spacing: CGFloat = 16
    var maxRadius: CGFloat = 3.2

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0, row = 0
            while y < size.height + spacing {
                let r = maxRadius * (0.25 + 0.75 * min(max(y / max(size.height, 1), 0), 1))
                var x: CGFloat = row % 2 == 0 ? 0 : spacing / 2
                while x < size.width + spacing {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(color))
                    x += spacing
                }
                y += spacing * 0.866; row += 1
            }
        }
        .allowsHitTesting(false)
    }
}

/// Kente-artiges Webmuster: Streifen, Zickzack-Dreiecke und Rauten in Bändern.
struct Kente: View {
    var color: Color = Ink.bg
    var unit: CGFloat = 12

    var body: some View {
        Canvas { ctx, size in
            let t = unit, band = unit * 5.5
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: t / 4)), with: .color(color))
                var tri = Path(), dia = Path()
                var x: CGFloat = 0
                while x < size.width {
                    let top = y + t * 0.8
                    tri.move(to: CGPoint(x: x, y: top))
                    tri.addLine(to: CGPoint(x: x + t, y: top + t))
                    tri.addLine(to: CGPoint(x: x + 2 * t, y: top))
                    tri.closeSubpath()
                    if Int(x / (2 * t)) % 2 == 0 {
                        let c = CGPoint(x: x + t, y: y + t * 3.7), r = t * 0.45
                        dia.move(to: CGPoint(x: c.x, y: c.y - r))
                        dia.addLine(to: CGPoint(x: c.x + r, y: c.y))
                        dia.addLine(to: CGPoint(x: c.x, y: c.y + r))
                        dia.addLine(to: CGPoint(x: c.x - r, y: c.y))
                        dia.closeSubpath()
                    }
                    x += 2 * t
                }
                ctx.fill(tri, with: .color(color))
                ctx.fill(dia, with: .color(color))
                y += band
            }
        }
        .allowsHitTesting(false)
    }
}

/// Flächenmuster des Stils: Rasterpunkte (Pop) oder gewebte Bänder (Webmuster). `fine` = kleiner, für Kacheln.
struct ThemePattern: View {
    @Environment(\.theme) private var theme
    var color: Color
    var fine = false

    var body: some View {
        if theme == .woven {
            Kente(color: color, unit: fine ? 9 : 14)
        } else {
            Halftone(color: color, spacing: fine ? 12 : 18, maxRadius: fine ? 2.6 : 4)
        }
    }
}

/// Seitenhintergrund im jeweiligen Stil.
struct ThemedBackground: View {
    @Environment(\.theme) private var theme
    var accent: Color? = nil

    var body: some View {
        if theme.bold {
            ZStack {
                theme.p.bg
                if let a = accent {
                    RadialGradient(colors: [a.opacity(0.55), .clear], center: .topTrailing, startRadius: 10, endRadius: 900)
                }
                ThemePattern(color: theme.p.dots.opacity(0.35))
            }
        } else {
            // Klar: Anthrazit bzw. warmes Papier statt Schwarz/Weiß, ohne Muster
            Color(hex: theme.pageHex)
        }
    }
}

/// WCAG-Kontrastverhältnis zweier Farben (1…21).
enum Contrast {
    static func luminance(_ hex: String) -> Double {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        func ch(_ c: UInt64) -> Double {
            let s = Double(c) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * ch((v >> 16) & 0xFF) + 0.7152 * ch((v >> 8) & 0xFF) + 0.0722 * ch(v & 0xFF)
    }

    static func ratio(_ a: String, _ b: String) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    static func selfTest() {
        precondition(abs(ratio("#000000", "#FFFFFF") - 21) < 0.01, "Schwarz/Weiß = 21:1")
        // Seiten (Formulare, Genres): Löschen-Knopf und gewähltes Genre im Apple-Stil
        precondition(ratio("#FFFFFF", "#B3261E") >= 4.5, "Weiß auf Löschen-Rot lesbar")
        precondition(ratio("#FFFFFF", "#2E7D32") >= 4.5, "Weiß auf Genre-Grün lesbar")
        precondition(Pop.textOn("#FFD23F") == .black, "auf Gelb schwarze Schrift")
        precondition(Pop.textOn("#2F6FDB") == .white, "auf Blau weiße Schrift")
        for p in [Pop.pop, Pop.woven] {
            for (id, t) in Catalog.tones { precondition(p.tones[t] != nil, "Farbrichtung \(t) für \(id) fehlt") }
            precondition(p.tone(for: Catalog.all.first { $0.id == "youtube" }!) == p.tones["red"], "YouTube → Rot")
            let custom = Service(id: "x", name: "x", url: "", colorTop: "#1DB954", colorBottom: "#000000", symbol: "")
            precondition(p.tone(for: custom) != p.tones["ink"], "farbige eigene Dienste bleiben farbig")
            precondition(ratio("#FFFFFF", p.bgHex) >= 4.5, "Weiß auf \(p.bgHex) lesbar")
            precondition(ratio(p.accentHex, p.bgHex) >= 4.5, "Akzent-Überschrift auf \(p.bgHex) lesbar")
            precondition(ratio("#000000", p.accentHex) >= 4.5, "Schwarz auf Akzent-Knopf lesbar")
        }
        precondition(Theme.stored("afro") == .woven && Theme.stored("pop") == .pop && Theme.stored("?") == nil, "alte Stil-Namen")
        precondition(Pop.textOn("#F4B63F") == .black && Pop.textOn("#7A2E5D") == .white, "Webmuster-Kacheln")
        precondition(Theme.popLight.next == .apple && Theme.apple.next == .pop, "Stil-Reihenfolge")
        // Pop hell: Text liegt nur auf Creme, Papier-Etiketten oder Gelb – Tinte überall ≥ 7:1 (AAA)
        for t in [Pop.popLight.bgHex, "#FFF7E8", Pop.popLight.accentHex] {
            precondition(ratio(Pop.popLight.inkHex, t) >= 7, "Pop hell: Tinte auf \(t) zu schwach")
        }
        // Ruhige Tastenfarben (Pastell auf mittlerem Grau) ≥ 4,5:1
        for c in Hint.calmColors.values { precondition(ratio(c, Hint.calmKeyHex) >= 4.5, "ruhige Taste \(c)") }
        precondition(ratio("#1A1A1A", "#E2D6C2") >= 7, "Klar hell: Text AAA")
        // Klar: Nebentext (85 % Weiß) auf Anthrazit ≥ 7:1 (AAA) – vor dem Filter gemessen
        precondition(ratio("#D9D9D9", "#1E2024") >= 7, "Klar: Nebentext AAA")
        // Xbox-Tastenfarben auf dunklem Knopf ≥ 4,5:1
        for c in ["#5DC21E", "#F0524F", "#3D9BE9", "#FFC93C"] {
            precondition(ratio(c, "#1B1B1B") >= 4.5, "Tastenfarbe \(c) zu schwach")
        }
    }
}

extension View {
    /// Gedämpfter Nebentext: im Apple-Stil grau, im Pop-Stil fast weiß (Kontrast auf Petrol + Rasterpunkten).
    func dimText(_ opacity: Double) -> some View { modifier(DimText(opacity: opacity)) }

    /// Überschrift: Apple = runde Systemschrift, Pop = schmale Comic-Versalien.
    func headingFont(_ size: CGFloat) -> some View { modifier(HeadingFont(size: size)) }

    /// Kachel/Knopf-Rahmen: Apple = Glas, Pop = Papier mit schwarzer Kontur und hartem Schatten.
    func themedCard(radius: CGFloat = 18, focused: Bool, fill: Color? = nil) -> some View {
        modifier(ThemedCard(radius: radius, focused: focused, fill: fill))
    }

    /// Harter Comic-Schatten für Text (nur Pop-Art).
    func popTextShadow() -> some View { modifier(PopTextShadow()) }
}

extension Font {
    /// Systemschrift, skaliert mit der Textgröße (Metrics.s) – größer am Fernseher.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let pt = size * Metrics.text(size)
        if let f = Typo.family { return .custom(f, size: pt).weight(Typo.heavier(weight)) }
        return .system(size: pt, weight: weight, design: design)
    }

    /// Lesetext (Fußzeilen-Hinweise, Beschreibungen): wächst zusätzlich mit dem Sitzabstand (Metrics.read).
    static func read(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let pt = size * Metrics.text(size) * Metrics.read
        if let f = Typo.family { return .custom(f, size: pt).weight(Typo.heavier(weight)) }
        return .system(size: pt, weight: weight, design: design)
    }
}

private struct HeadingFont: ViewModifier {
    @Environment(\.theme) private var theme
    let size: CGFloat

    func body(content: Content) -> some View {
        if theme.bold {
            content.font(.custom(theme.p.font, size: size * Metrics.text(size) * theme.p.fontScale)).textCase(.uppercase).tracking(0.5)
        } else {
            content.font(.ui(size, weight: .bold, design: .rounded))
        }
    }
}

private struct DimText: ViewModifier {
    @Environment(\.theme) private var theme
    let opacity: Double
    func body(content: Content) -> some View {
        // Klar: Nebentext nie unter 85 % – blasser Text ist für Sehschwache das erste, was verschwimmt.
        content.foregroundColor(Ink.fg.opacity(theme.bold ? max(opacity, 0.92) : theme.isClear ? max(opacity, 0.85) : opacity))
    }
}

private struct PopTextShadow: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        // Pop hell: kein Schatten hinter Schrift – eine versetzte Kopie wirkt mit Prismenbrille wie ein Doppelbild.
        if theme.bold && theme != .popLight { content.shadow(color: Ink.bg, radius: 0, x: 2, y: 2) } else { content }
    }
}

private struct ThemedCard: ViewModifier {
    @Environment(\.theme) private var theme
    let radius: CGFloat
    let focused: Bool
    let fill: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if theme.bold {
            content
                .foregroundColor(Ink.bg)
                .background(shape.fill(fill ?? (focused ? theme.p.accent : theme.p.paper)))
                .overlay(shape.strokeBorder(Ink.bg, lineWidth: focused ? 4 : 3))
                .background(shape.fill(Ink.bg).offset(x: focused ? 8 : 5, y: focused ? 8 : 5))
                .scaleEffect(focused && !Typo.calm ? 1.08 : 1)
                .rotationEffect(.degrees(focused ? -1.5 : 0))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: focused)
        } else {
            content
                .background(shape.fill(fill ?? Ink.fg.opacity(focused ? 0.22 : 0.08)))
                .overlay(shape.strokeBorder(Ink.fg.opacity(focused ? 0.9 : 0.1), lineWidth: focused ? (theme.isClear ? 5 : 3) : 1))
                .scaleEffect(focused && !Typo.calm ? 1.08 : 1)
                .shadow(color: Ink.bg.opacity(focused ? 0.5 : 0), radius: 20, y: 12)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: focused)
        }
    }
}

/// Reihe, die bei Platzmangel in die nächste Zeile umbricht (Tastenhinweise, Chips) – statt abzuschneiden.
struct FlowLayout: Layout {
    var spacing: CGFloat = 20
    var lineSpacing: CGFloat = 10
    var centered = true

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Ohne feste Breite (oder bei 0-Probe) eine Zeile – umbrechen nur, wenn wirklich zu wenig Platz ist.
        let w0 = proposal.width ?? .infinity
        let rows = arrange(w0 <= 0 ? .infinity : w0, subviews)
        let w = rows.map { $0.width }.max() ?? 0
        let h = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX + (centered ? (bounds.width - row.width) / 2 : 0)
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func arrange(_ maxW: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var cur: [Int] = [], w: CGFloat = 0, h: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let size = v.sizeThatFits(.unspecified)
            // +1: Rundung beim Platzieren darf die gemessene Zeile nicht nachträglich umbrechen.
            if !cur.isEmpty && w + spacing + size.width > maxW + 1 {
                rows.append((cur, w, h)); cur = []; w = 0; h = 0
            }
            w += (cur.isEmpty ? 0 : spacing) + size.width
            h = max(h, size.height)
            cur.append(i)
        }
        if !cur.isEmpty { rows.append((cur, w, h)) }
        return rows
    }
}

/// Grundfarben für Text und Flächen. Hell/dunkel tauschen sie (Stil „Klar hell“), sonst Weiß/Schwarz wie bisher.
enum Ink {
    static var light = false
    /// Pop hell: Konturen, Schatten und Schrift auf Papier sind Tinte (statt Schwarz) – nicht hell.
    static var boldLight = false
    /// Text und helle Flächen: Weiß bzw. fast Schwarz (nie reines Schwarz – weniger harte Kanten).
    static var fg: Color { light ? Color(hex: boldLight ? Pop.inkHexLight : "#1A1A1A") : .white }
    /// Gegenfarbe (Schrift auf `fg`-Knöpfen, Abdunkelungen); im Pop-Stil die Kontur-Farbe.
    static var bg: Color { boldLight ? Color(hex: Pop.inkHexLight) : light ? Color(hex: "#EADFCC") : .black }
    /// Menü-Hintergrund.
    static var panel: Color { light ? Color(hex: "#EADFCC") : Color(white: 0.12) }
}
