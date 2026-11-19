import SwiftUI
import AppKit

/// Scrollt zum fokussierten Element – ohne ScrollViewReader, der auf macOS dem Controller-Fokus
/// nicht zuverlässig folgt. Kinder markieren sich mit `.scrollAnchor(id, in: space)`.
struct FocusScroll<Content: View>: View {
    let axis: Axis
    let target: String?
    var position: CGFloat = 0.5          // wo das fokussierte Element landet (0 = Anfang, 1 = Ende)
    let space: String
    var wheel = false                    // Trackpad/Mausrad scrollt diese Ansicht
    @ViewBuilder let content: () -> Content

    @State private var frames: [String: CGRect] = [:]
    @State private var offset: CGFloat = 0
    @State private var wheelBox = WheelBox()

    var body: some View {
        GeometryReader { outer in
            content()
                .fixedSize(horizontal: axis == .horizontal, vertical: axis == .vertical)
                .coordinateSpace(name: space)
                .onPreferenceChange(AnchorFrames.self) { f in
                    // Nur nachziehen, wenn sich das Ziel spürbar verschoben hat (z. B. Reihen geladen) –
                    // nicht bei jedem Animationsschritt.
                    let moved = target.map { id in
                        guard let a = frames[id], let b = f[id] else { return true }
                        return abs(a.minY - b.minY) > 4 || abs(a.minX - b.minX) > 4
                    } ?? false
                    frames = f
                    if moved { update(outer.size, animated: false) }
                }
                .offset(x: axis == .horizontal ? -offset : 0, y: axis == .vertical ? -offset : 0)
                .frame(width: outer.size.width, height: outer.size.height, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .onHover { wheelBox.hovered = $0 }
                .onChange(of: target) { _ in update(outer.size, animated: true) }
                .onChange(of: outer.size) { s in update(s, animated: false) }
                .onAppear { wheelBox.viewport = outer.size; wheelBox.enabled = wheel; installWheel() }
                .onChange(of: outer.size) { s in wheelBox.viewport = s }
                .onDisappear { wheelBox.remove() }
                .onChange(of: wheel) { w in wheelBox.enabled = w }
        }
        // Eigene Anker nicht an äußere FocusScrolls weiterreichen (andere Koordinaten).
        .transformPreference(AnchorFrames.self) { $0 = [:] }
    }

    private var contentEnd: CGFloat {
        (frames.values.map { axis == .vertical ? $0.maxY : $0.maxX }.max() ?? 0) + 40
    }

    // Vertikal: ganze Ansicht (wenn `wheel`). Horizontal: nur die Reihe unter dem Zeiger, per dX
    // (Trackpad, iPhone-Touchpad, rechter Stick) oder Shift+Mausrad.
    // Achsen-Lock: Jede Wischgeste gehört entweder der Reihe oder der Seite (siehe `WheelAxis`).
    private func installWheel() {
        guard wheelBox.monitor == nil, wheel || axis == .horizontal else { return }
        let horizontal = axis == .horizontal
        // Rechter Stick (Controller): senkrechte, scrollbare Ansichten, die gerade vorne sind.
        if !horizontal {
            wheelBox.padObserver = NotificationCenter.default.addObserver(forName: .padScroll, object: nil, queue: .main) { n in
                guard wheelBox.enabled, let d = n.userInfo?["dy"] as? CGFloat else { return }
                offset = min(max(offset - d, 0), max(contentEnd - wheelBox.viewport.height, 0))
            }
        }
        wheelBox.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { ev in
            guard wheelBox.enabled || horizontal else { return ev }
            guard WheelAxis.of(ev) == axis else { return ev }
            var d: CGFloat
            if horizontal {
                guard wheelBox.hovered else { return ev }
                d = ev.scrollingDeltaX
                if d == 0, ev.modifierFlags.contains(.shift) { d = ev.scrollingDeltaY }
            } else {
                d = ev.scrollingDeltaY
            }
            guard d != 0 else { return ev }
            if !ev.hasPreciseScrollingDeltas { d *= 12 }
            let view = horizontal ? wheelBox.viewport.width : wheelBox.viewport.height
            offset = min(max(offset - d, 0), max(contentEnd - view, 0))
            return ev
        }
    }

    private func update(_ viewport: CGSize, animated: Bool) {
        guard let id = target, let f = frames[id] else { return }
        // Inhaltslänge = Ende des letzten Ankers + Rand (zuverlässiger als eine gemessene Gesamtgröße).
        let new = FocusScrollMath.offset(
            itemMin: axis == .vertical ? f.minY : f.minX,
            itemMax: axis == .vertical ? f.maxY : f.maxX,
            viewport: axis == .vertical ? viewport.height : viewport.width,
            content: contentEnd,
            position: position)
        guard abs(new - offset) > 0.5 else { return }
        if Debug.on { print("scroll \(space): \(id) → \(Int(new))") }
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) { offset = new }
        } else {
            offset = new
        }
    }
}

/// Entscheidet je Wischgeste einmal, ob sie seitlich oder senkrecht gemeint ist – inklusive Nachschwung.
/// Sonst wackelt beim seitlichen Wischen die Seite mit, weil das Trackpad immer auch etwas dY liefert.
@MainActor enum WheelAxis {
    private static var current: Axis?
    private static var last = Date.distantPast

    static func of(_ ev: NSEvent) -> Axis? {
        // Mausrad (Rastung): senkrecht, mit Shift seitlich; Kipprad/iPhone nach der stärkeren Richtung.
        guard ev.hasPreciseScrollingDeltas else {
            if ev.modifierFlags.contains(.shift) { return .horizontal }
            return decide(dx: ev.scrollingDeltaX, dy: ev.scrollingDeltaY) ?? .vertical
        }
        let now = Date()
        // Neue Geste: Finger aufgesetzt oder längere Pause (Momentum gehört zur alten Geste).
        if ev.phase == .began || (ev.momentumPhase.isEmpty && now.timeIntervalSince(last) > 0.3) { current = nil }
        last = now
        if current == nil { current = decide(dx: ev.scrollingDeltaX, dy: ev.scrollingDeltaY) }
        return current
    }

    /// Erste spürbare Bewegung entscheidet; winzige Werte warten auf die nächste.
    nonisolated static func decide(dx: CGFloat, dy: CGFloat) -> Axis? {
        guard abs(dx) + abs(dy) > 0.5 else { return nil }
        return abs(dx) > abs(dy) ? .horizontal : .vertical
    }
}

/// Hält den Rad-Monitor über Neuzeichnungen hinweg.
final class WheelBox {
    var monitor: Any?
    var viewport: CGSize = .zero
    var enabled = true
    var hovered = false
    var padObserver: NSObjectProtocol?
    func remove() {
        if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil
        if let o = padObserver { NotificationCenter.default.removeObserver(o) }; padObserver = nil
    }
    deinit { remove() }
}

/// Test-Modus: `PopSofa --press down,down,right,a,left` drückt Tasten automatisch und protokolliert.
enum Debug {
    static let on = CommandLine.arguments.contains("--press")

    @MainActor static func run(_ state: AppState) {
        guard let i = CommandLine.arguments.firstIndex(of: "--press"), i + 1 < CommandLine.arguments.count else { return }
        let names: [String: PadEvent] = ["up": .up, "down": .down, "left": .left, "right": .right,
                                         "a": .a, "b": .b, "x": .x, "y": .y, "lb": .lb, "rb": .rb]
        let steps = CommandLine.arguments[i + 1].split(separator: ",").map(String.init)
        print("bedienungshilfen:", Input.hasAccessibility(prompt: false))
        Task { @MainActor in
            for i in 1...3 {                                     // Start-Animation
                try? await Task.sleep(nanoseconds: 400_000_000)
                shot("splash\(i)")
            }
            try? await Task.sleep(nanoseconds: 4_800_000_000)   // Empfehlungen laden lassen
            print("rows:", state.rows.map { "\($0.id)(\($0.items.count))" })
            for (n, step) in steps.enumerated() {
                if step == "volup" || step == "voldown" {
                    Input.volume(up: step == "volup")
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    print("\(step): ok")
                    continue
                }
                if step.hasPrefix("q=") {                            // Suche: q=Money Heist
                    state.openSearch(); state.runSearch(String(step.dropFirst(2)))
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    print("search \(step): \(state.searchStatus ?? "-") | " + state.searchResults.prefix(5)
                        .map { "\($0.name) (\(state.serviceName(for: $0) ?? "?"))" }.joined(separator: ", "))
                    shot("search-\(n)")
                    continue
                }
                if step == "sup" || step == "sdown" {               // rechter Stick: 300 pt scrollen
                    NotificationCenter.default.post(name: .padScroll, object: nil, userInfo: ["dy": CGFloat(step == "sup" ? 300 : -300)])
                } else if step == "end" { state.posterIndex = 9999; state.handle(.right) }   // zur Karte „Alle anzeigen“
                else if step != "wait" { guard let k = names[step] else { continue }; state.handle(k) }
                let k = step
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                shot("\(n)-\(k)")
                print("\(k): grid=\(state.focusedIndex) row=\(state.posterRow.map(String.init) ?? "-") poster=\(state.posterIndex) detail=\(state.detail != nil) provider=\(state.detailFocus)/\(state.detailOptions.count) trailer=\(state.detailInfo?.trailer ?? "-") web=\(state.webURL?.host ?? "-") wl=\(state.watchlist.count) row0=\(state.rows.first?.id ?? "-") cat=\(state.category.map { "\($0.title):\($0.items.count)" } ?? "-") scale=\(state.uiScale)")
            }
            exit(0)
        }
    }

    /// `--shot <ordner>`: speichert nach jedem Schritt ein Bild des Fensters (ohne Bildschirmaufnahme-Freigabe).
    @MainActor static func shot(_ name: String) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--shot"), i + 1 < args.count,
              let main = NSApp.windows.first(where: { $0.canBecomeMain }),
              let v = (main.attachedSheet ?? main).contentView,
              let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? DisplayFilter.render(rep)?
            .write(to: URL(fileURLWithPath: args[i + 1]).appendingPathComponent(name + ".png"))
    }
}

enum FocusScrollMath {
    /// Versatz, damit das Element bei `position` steht – nie über Anfang/Ende hinaus.
    static func offset(itemMid: CGFloat, viewport: CGFloat, content: CGFloat, position: CGFloat) -> CGFloat {
        offset(itemMin: itemMid, itemMax: itemMid, viewport: viewport, content: content, position: position)
    }

    /// Wie oben, aber das ganze Element bleibt sichtbar (mit Rand) – auch auf kleinen Bildschirmen
    /// und bei großer Schrift, wo die Wunsch-Position die Reihe unten abschneiden würde.
    static func offset(itemMin: CGFloat, itemMax: CGFloat, viewport: CGFloat, content: CGFloat, position: CGFloat) -> CGFloat {
        let margin: CGFloat = 16
        var wanted = (itemMin + itemMax) / 2 - viewport * position
        if itemMax - itemMin + 2 * margin <= viewport {
            wanted = min(max(wanted, itemMax + margin - viewport), itemMin - margin)
        } else {
            wanted = (itemMin + itemMax - viewport) / 2   // passt nicht ganz: mittig
        }
        return min(max(wanted, 0), max(content - viewport, 0))
    }

    static func selfTest() {
        precondition(offset(itemMid: 100, viewport: 800, content: 2000, position: 0.5) == 0, "oben bleibt oben")
        precondition(offset(itemMid: 1000, viewport: 800, content: 2000, position: 0.5) == 600, "mittig")
        precondition(offset(itemMid: 1950, viewport: 800, content: 2000, position: 0.5) == 1200, "unten begrenzt")
        precondition(offset(itemMid: 500, viewport: 800, content: 600, position: 0.5) == 0, "passt komplett")
        // Reihe 1000…1400 in 500er-Fenster bei Position 0,38: Mitte allein → 1010, Unterkante (1400) abgeschnitten.
        let o = offset(itemMin: 1000, itemMax: 1400, viewport: 500, content: 3000, position: 0.38)
        precondition(o + 500 >= 1416 && o <= 984, "ganze Reihe sichtbar: \(o)")
        precondition(offset(itemMin: 1000, itemMax: 1600, viewport: 500, content: 3000, position: 0.38) == 1050, "zu groß → mittig")
        precondition(WheelAxis.decide(dx: -8, dy: 2) == .horizontal, "schräg seitlich → Reihe")
        precondition(WheelAxis.decide(dx: 1, dy: -6) == .vertical, "schräg senkrecht → Seite")
        precondition(WheelAxis.decide(dx: 0.2, dy: 0.1) == nil, "Zittern entscheidet nichts")
    }
}

struct AnchorFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func scrollAnchor(_ id: String, in space: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: AnchorFrames.self, value: [id: g.frame(in: .named(space))])
        })
    }
}

extension Notification.Name {
    /// Rechter Stick: senkrecht scrollen (userInfo["dy"], > 0 = nach oben).
    static let padScroll = Notification.Name("PopSofa.padScroll")
}
