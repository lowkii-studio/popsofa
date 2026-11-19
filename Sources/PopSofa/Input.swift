import CoreGraphics
import AppKit
import ApplicationServices

/// Erzeugt synthetische Tastatur-Eingaben für die jeweils vorderste App.
/// Benötigt die Berechtigung "Bedienungshilfen".
enum Input {
    static func hasAccessibility(prompt: Bool) -> Bool {
        let opts = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Einzelne Taste (virtueller Keycode) drücken und loslassen.
    static func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Systemlautstärke wie mit den Lautstärketasten der Tastatur – mit macOS-Anzeige,
    /// funktioniert für jede Ausgabe (Lautsprecher, AirPods, HDMI mit Lautstärkeregelung).
    static func volume(up: Bool) { media(up ? 0 : 1) }          // NX_KEYTYPE_SOUND_UP / _DOWN

    /// Ton aus/an (NX_KEYTYPE_MUTE).
    static func mute() { media(7) }

    /// Medientaste (Systemdefined-Event) drücken und loslassen.
    private static func media(_ key: Int) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        subtype: 8, data1: (key << 16) | (state << 8), data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Beliebigen Text (inkl. Umlaute, Emojis) in das fokussierte Feld tippen.
    static func type(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            let end = min(i + 16, units.count)
            let chunk = Array(units[i..<end])
            i = end
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                var c = chunk
                e?.keyboardSetUnicodeString(stringLength: c.count, unicodeString: &c)
                e?.post(tap: .cghidEventTap)
            }
        }
    }

    // Virtuelle Keycodes (ANSI/ISO-unabhängige Steuertasten)
    enum Code {
        static let returnKey: CGKeyCode = 36
        static let tab: CGKeyCode = 48
        static let space: CGKeyCode = 49
        static let delete: CGKeyCode = 51
        static let leftArrow: CGKeyCode = 123
        static let rightArrow: CGKeyCode = 124
        static let downArrow: CGKeyCode = 125
        static let upArrow: CGKeyCode = 126
        static let f: CGKeyCode = 3
        static let leftBracket: CGKeyCode = 33
    }
}
