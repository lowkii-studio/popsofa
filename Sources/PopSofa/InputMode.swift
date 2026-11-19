import SwiftUI
import AppKit

/// Zuletzt benutztes Eingabegerät – wechselt automatisch.
enum InputMode { case controller, keyboard }

extension AppState {
    /// Pfeiltasten, Enter und Esc steuern dieselbe Navigation wie der Controller.
    func startKeyboardInput() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .scrollWheel]) { [weak self] ev in
            guard let self else { return ev }
            // Vom Controller erzeugte Maus-Ereignisse (Maus-Modus) zählen nicht als Tastatur/Maus.
            if self.controller.mouseMode { return ev }
            if ev.type != .keyDown {
                self.inputMode = .keyboard
                return ev
            }
            return self.handleKey(ev)
        }
    }

    private func handleKey(_ ev: NSEvent) -> NSEvent? {
        // Im Browser, in Dialogen und mit ⌘/⌃/⌥ gehören Tasten der jeweiligen Ansicht.
        guard webURL == nil, NSApp.keyWindow is NSPanel == false,
              ev.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return ev }
        // Dienste verwalten: ⇧ + Pfeil verschiebt den Dienst direkt.
        if editMode, ev.modifierFlags.contains(.shift), NSApp.keyWindow?.firstResponder is NSTextView == false {
            let d: [UInt16: Int] = [123: -1, 124: 1, 125: columns, 126: -columns]
            if let delta = d[ev.keyCode] {
                inputMode = .keyboard
                moveService(by: delta)
                return nil
            }
        }
        // L = Gefällt mir, N = Nicht mein Fall (wie X/Y am Controller)
        if ev.keyCode == 37 || ev.keyCode == 45, NSApp.keyWindow?.firstResponder is NSTextView == false, let t = currentTitle {
            inputMode = .keyboard
            ev.keyCode == 37 ? like(t) : dislike(t)
            return nil
        }
        // G = Genres wählen (wie RB in den Poster-Reihen), auf der Startseite ohne offene Seite
        if ev.keyCode == 5, sheet == nil, detail == nil, !searchOpen, NSApp.keyWindow?.firstResponder is NSTextView == false {
            inputMode = .keyboard
            genreFocus = 0
            sheet = .genres
            return nil
        }
        let keys: [UInt16: PadEvent] = [123: .left, 124: .right, 125: .down, 126: .up, 36: .a, 76: .a, 53: .b]
        guard let e = keys[ev.keyCode] else { return ev }
        inputMode = .keyboard

        // Steht der Cursor im Suchfeld: ← → ↩ gehören dem Feld, ↓ springt zu den Ergebnissen, Esc schließt.
        if NSApp.keyWindow?.firstResponder is NSTextView {
            switch e {
            case .down:
                NSApp.keyWindow?.makeFirstResponder(nil)
                handle(.down)
                return nil
            case .b:
                NSApp.keyWindow?.makeFirstResponder(nil)
                if sheet != nil { editingField = nil } else if searchOpen { searchOpen = false }
                return nil
            default:
                return ev
            }
        }
        handle(e)
        return nil
    }

    /// Tastenhinweise für den Tastatur-Modus, passend zur aktuellen Ansicht.
    var keyboardHints: [(String, String)] {
        let rate = [("L", tr("Gefällt mir")), ("N", tr("Nicht mein Fall"))]
        if detail != nil { return [("← →", tr("Anbieter")), ("↩", tr("Ansehen"))] + rate + [("esc", tr("Zurück"))] }
        if category != nil { return [("← → ↑ ↓", tr("Auswahl")), ("↩", tr("Details"))] + rate + [("esc", tr("Zurück"))] }
        if searchOpen {
            return [("↩", tr("Suchen / Details")), ("↑ ↓", tr("Ergebnisse"))] + (searchInResults ? rate : []) + [("esc", tr("Zurück"))]
        }
        if oursOpen { return [("← → ↑ ↓", tr("Auswahl")), ("↩", tr("Details"))] + rate + [("esc", tr("Zurück"))] }
        if posterRow != nil {
            if showSetupCard { return [("↩", tr("Einrichten")), ("esc", tr("Zurück"))] }
            return [("← → ↑ ↓", tr("Auswahl")), ("↩", tr("Details"))] + rate + [("G", tr("Genres")), ("esc", tr("Zurück"))]
        }
        if editMode { return [("← → ↑ ↓", tr("Auswahl")), ("⇧ + Pfeil", tr("Verschieben")), ("Maus", tr("Ziehen")), ("↩", tr("An/Aus")), ("esc", tr("Fertig"))] }
        return [("← → ↑ ↓", tr("Auswahl")), ("↩", tr("Öffnen")), ("Trackpad", tr("Scrollen"))]
    }
}

struct KeyboardHints: View {
    @EnvironmentObject var state: AppState

    /// Lange Tastennamen als Symbol – kurz, eindeutig und ohne Kürzung.
    static let symbols: [String: String] = [
        "← → ↑ ↓": "arrow.up.and.down.and.arrow.left.and.right", "← →": "arrow.left.and.right",
        "↑ ↓": "arrow.up.and.down", "↩": "return", "esc": "escape", "⇧ + Pfeil": "shift",
        "Trackpad": "hand.point.up.left", "Maus": "computermouse",
    ]

    var body: some View {
        // Group statt HStack: die Hinweise werden Teil der umgebenden FlowLayout-Zeile und brechen mit um.
        Group {
            ForEach(state.keyboardHints, id: \.0) { key, text in
                Hint(glyph: Self.symbols[key].map { .symbol($0) } ?? .letter(key, .gray), text: text)
            }
        }
    }
}

/// Leiste über dem eingebauten Browser: zurück zu PopSofa (Controller: B bzw. ⧉).
struct WebBar: View {
    @EnvironmentObject var state: AppState
    let host: String

    var body: some View {
        HStack(spacing: 14) {
            BackButton(text: "PopSofa", dark: true) { state.webURL = nil }
            Text(host).font(.ui(15, weight: .medium)).foregroundColor(Ink.fg.opacity(0.55)).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Ink.bg)
    }
}

/// „‹ Zurück“ oben links auf jeder Ebene unter dem Startbildschirm – für Maus, Touchpad und iPhone.
struct BackButton: View {
    @Environment(\.theme) private var theme
    var text = tr("Zurück")
    var dark = false
    var focused = false                 // per Controller angewählt (↑ aus der obersten Zeile)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.ui(16, weight: .bold))
                Text(text).font(.ui(17, weight: .semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .foregroundColor(theme.bold && !dark ? Ink.bg : Ink.fg)
            .background(Capsule().fill(dark ? Ink.bg.opacity(0.7)
                                            : (theme.bold ? theme.p.paper : Ink.fg.opacity(0.14))))
            .overlay(Capsule().strokeBorder(theme.bold && !dark ? Ink.bg : .clear, lineWidth: 2))
            .overlay(Capsule().strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: 3)
                .padding(-5).opacity(focused ? 1 : 0))
            .scaleEffect(focused && !Typo.calm ? 1.1 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: focused)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(text)
        .accessibilityLabel(text)
    }
}
