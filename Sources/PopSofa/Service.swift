import SwiftUI
import AppKit

// MARK: - Farben

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Streaming-Dienst

struct Service: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var url: String
    var colorTop: String
    var colorBottom: String
    var symbol: String
    var isCustom: Bool = false
    /// Kopierschutz (DRM) → öffnet im externen Browser statt im eingebauten.
    var drm: Bool? = nil

    var gradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: colorTop), Color(hex: colorBottom)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var host: String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
    }
}

// MARK: - Katalog gängiger Anbieter
// Bewusst ohne Original-Logos: Kacheln in Markenfarbe (Apple-Stil) bzw. der passenden Stil-Farbe.

enum Catalog {
    static let all: [Service] = [
        Service(id: "netflix", name: "Netflix", url: "https://www.netflix.com",
                colorTop: "#E50914", colorBottom: "#4A0307", symbol: "play.rectangle.fill", drm: true),
        Service(id: "prime", name: "Prime Video", url: "https://www.primevideo.com",
                colorTop: "#00A8E1", colorBottom: "#0B2A4A", symbol: "play.tv.fill", drm: true),
        Service(id: "youtube", name: "YouTube", url: "https://www.youtube.com",
                colorTop: "#FF0033", colorBottom: "#4A0010", symbol: "play.circle.fill"),
        Service(id: "disney", name: "Disney+", url: "https://www.disneyplus.com",
                colorTop: "#113CCF", colorBottom: "#0A1433", symbol: "star.fill", drm: true),
        Service(id: "appletv", name: "Apple TV+", url: "https://tv.apple.com",
                colorTop: "#1D1D1F", colorBottom: "#0A0A0B", symbol: "tv.fill", drm: true),
        Service(id: "wow", name: "WOW", url: "https://www.wowtv.de",
                colorTop: "#6C3CE1", colorBottom: "#1D0F4A", symbol: "film.fill", drm: true),
        Service(id: "rtlplus", name: "RTL+", url: "https://plus.rtl.de",
                colorTop: "#E2007A", colorBottom: "#4A0030", symbol: "play.rectangle.fill", drm: true),
        Service(id: "joyn", name: "Joyn", url: "https://www.joyn.de",
                colorTop: "#E8A600", colorBottom: "#4A3600", symbol: "play.circle.fill", drm: true),
        Service(id: "ard", name: "ARD Mediathek", url: "https://www.ardmediathek.de",
                colorTop: "#0A5BE0", colorBottom: "#04204A", symbol: "tv.fill"),
        Service(id: "zdf", name: "ZDF Mediathek", url: "https://www.zdf.de",
                colorTop: "#FA7D19", colorBottom: "#4A2406", symbol: "tv.fill"),
        Service(id: "paramount", name: "Paramount+", url: "https://www.paramountplus.com",
                colorTop: "#0064FF", colorBottom: "#001F4D", symbol: "film.fill", drm: true),
        Service(id: "hbomax", name: "HBO Max", url: "https://www.hbomax.com",
                colorTop: "#002BE7", colorBottom: "#00104F", symbol: "play.rectangle.fill", drm: true),
        Service(id: "dazn", name: "DAZN", url: "https://www.dazn.com",
                colorTop: "#0C161C", colorBottom: "#000000", symbol: "sportscourt.fill", drm: true),
        Service(id: "crunchyroll", name: "Crunchyroll", url: "https://www.crunchyroll.com",
                colorTop: "#F47521", colorBottom: "#4A2306", symbol: "sparkles"),
        Service(id: "twitch", name: "Twitch", url: "https://www.twitch.tv",
                colorTop: "#9146FF", colorBottom: "#2A1550", symbol: "gamecontroller.fill"),
        Service(id: "spotify", name: "Spotify", url: "https://open.spotify.com",
                colorTop: "#1DB954", colorBottom: "#0A3D1C", symbol: "music.note"),
    ]

    /// Farbrichtung der Marke – der Stil (Pop-Art, Webmuster) setzt dafür seine eigene Farbe ein.
    static let tones: [String: String] = [
        "netflix": "red", "youtube": "red", "prime": "cyan", "disney": "blue", "appletv": "ink",
        "wow": "purple", "rtlplus": "pink", "joyn": "yellow", "ard": "blue", "zdf": "orange",
        "paramount": "blue", "hbomax": "blue", "dazn": "ink", "crunchyroll": "orange",
        "twitch": "purple", "spotify": "green",
    ]

    static let defaultEnabled: Set<String> = ["netflix", "prime", "youtube", "disney", "appletv"]

    static let customPalette: [(String, String)] = [
        ("#2E8B9A", "#0B2A30"), ("#B5487A", "#3A0F26"), ("#5C7AEA", "#141B3D"),
        ("#E07A3F", "#44200C"), ("#58A55C", "#12301A"),
    ]
}

// MARK: - Browser-Auswahl

enum BrowserChoice: String, CaseIterable, Codable {
    case system, safari, chrome, firefox, edge, brave

    var title: String {
        switch self {
        case .system: return tr("Standard-Browser")
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .firefox: return "Firefox"
        case .edge: return "Edge"
        case .brave: return "Brave"
        }
    }

    var bundleID: String? {
        switch self {
        case .system: return nil
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .firefox: return "org.mozilla.firefox"
        case .edge: return "com.microsoft.edgemac"
        case .brave: return "com.brave.Browser"
        }
    }

    /// Name des Browsers, der tatsächlich öffnet (bei „Standard“ der System-Standardbrowser).
    var displayName: String {
        guard self == .system else { return title }
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return "Browser" }
        return FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    var isInstalled: Bool {
        guard let id = bundleID else { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    /// Öffnet die Adresse. Ist im Browser schon ein Tab dieses Dienstes offen (`reuseHost`),
    /// wird dieser Tab mit der neuen Adresse geladen statt einen weiteren zu öffnen.
    func open(_ url: URL, reuseHost: String? = nil, profile: String? = nil) {
        if let id = effectiveBundleID(for: url) {
            BrowserZoom.apply(bundleID: id, scale: Metrics.m * Metrics.read)
            if let profile { StreamProfile.pick(bundleID: id, name: profile) }
        }
        guard let host = reuseHost, let browserID = effectiveBundleID(for: url),
              NSRunningApplication.runningApplications(withBundleIdentifier: browserID).isEmpty == false,
              let script = TabReuse.script(browserID: browserID, host: host, url: url) else {
            openNew(url); return
        }
        // AppleScript blockiert kurz (beim ersten Mal fragt macOS nach der Erlaubnis) → nicht im Hauptthread.
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&err).stringValue
            DispatchQueue.main.async { if result != "reused" { openNew(url) } }
        }
    }

    /// Welcher Browser tatsächlich öffnet (bei „Standard“ der System-Standardbrowser).
    private func effectiveBundleID(for url: URL) -> String? {
        if let id = bundleID { return id }
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return Bundle(url: app)?.bundleIdentifier
    }

    private func openNew(_ url: URL) {
        if let id = bundleID,
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: cfg)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Vorhandenen Tab wiederverwenden (Safari, Chrome, Edge, Brave)

enum TabReuse {
    static func script(browserID: String, host: String, url: URL) -> String? {
        // Nur Zeichen, die in AppleScript-Strings harmlos sind.
        let u = url.absoluteString, h = host
        guard !u.contains("\""), !h.contains("\""), !u.contains("\\") else { return nil }
        switch browserID {
        case "com.apple.Safari":
            return """
            tell application id "com.apple.Safari"
              repeat with w in windows
                repeat with t in tabs of w
                  try
                    if (URL of t) contains "\(h)" then
                      set URL of t to "\(u)"
                      set current tab of w to t
                      set index of w to 1
                      activate
                      return "reused"
                    end if
                  end try
                end repeat
              end repeat
            end tell
            return "none"
            """
        case "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser":
            return """
            tell application id "\(browserID)"
              repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                  set i to i + 1
                  if (URL of t) contains "\(h)" then
                    set URL of t to "\(u)"
                    set active tab index of w to i
                    set index of w to 1
                    activate
                    return "reused"
                  end if
                end repeat
              end repeat
            end tell
            return "none"
            """
        default:
            return nil   // Firefox & Co. lassen sich nicht so steuern → neuer Tab
        }
    }
}

// MARK: - Browser-Zoom passend zur Textgröße

/// Stellt im externen Browser die Zoomstufe ein, die der Skalierung der App am nächsten liegt, und schaltet das Fenster ins Vollbild.
/// Löst dafür die Menüpunkte „Originalgröße“ (⌘0) und „Vergrößern“ (⌘+) per Bedienungshilfen aus –
/// gefunden über das Tastenkürzel, nicht den Namen, also unabhängig von Sprache und Tastaturlayout.
enum BrowserZoom {
    // ponytail: feste Zoomstufen der Browser; ändert ein Browser seine Stufen, hier nachziehen.
    static func levels(_ bundleID: String) -> [CGFloat] {
        switch bundleID {
        case "com.apple.Safari": return [1, 1.15, 1.25, 1.5, 1.75, 2]
        case "org.mozilla.firefox": return [1, 1.1, 1.2, 1.33, 1.5, 1.7, 2]
        default: return [1, 1.1, 1.25, 1.5, 1.75, 2]   // Chrome, Edge, Brave
        }
    }

    /// Anzahl „Vergrößern“-Klicks ab 100 % für die Stufe, die `scale` am nächsten liegt.
    /// Nächstgelegene Stufe – aber sobald PopSofa vergrößert (ab 1,03), mindestens eine Stufe,
    /// damit „Auto“ mit leichter Vergrößerung (z. B. 1,05) im Browser auch etwas bewirkt.
    static func steps(bundleID: String, scale: CGFloat) -> Int {
        let l = levels(bundleID)
        let nearest = l.indices.min { abs(l[$0] - scale) < abs(l[$1] - scale) } ?? 0
        return scale >= 1.03 ? max(nearest, 1) : nearest
    }

    static func apply(bundleID: String, scale: CGFloat) {
        let n = steps(bundleID: bundleID, scale: scale)
        guard Input.hasAccessibility(prompt: false) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let pid = waitFront(bundleID) else { return }
            Thread.sleep(forTimeInterval: 0.8)   // kurz, bis der Tab steht
            let ax = AXUIElementCreateApplication(pid)
            if let reset = menuItem(ax, chars: ["0"]), let zoomIn = menuItem(ax, chars: ["+", "="]) {
                AXUIElementPerformAction(reset, kAXPressAction as CFString)
                for _ in 0..<n {
                    Thread.sleep(forTimeInterval: 0.08)
                    AXUIElementPerformAction(zoomIn, kAXPressAction as CFString)
                }
                if n > 0 { DispatchQueue.main.async { zoomedPID = pid } }
            }
            // Wie ein Fernseher: Browserfenster im Vollbild (macOS-Vollbild, nicht nur der Player).
            // Menüpunkt mit ⌃⌘F ist ein Umschalter → nur auslösen, wenn das Fenster noch nicht im Vollbild ist.
            let win: AXUIElement? = attr(ax, kAXFocusedWindowAttribute) ?? attr(ax, kAXMainWindowAttribute)
            if let win, (attr(win, "AXFullScreen") as Bool?) != true {
                if let full = menuItem(ax, chars: ["F", "f"], modifiers: 4) {   // 4 = ⌃ (⌘ ist immer dabei)
                    AXUIElementPerformAction(full, kAXPressAction as CFString)
                } else {
                    AXUIElementSetAttributeValue(win, "AXFullScreen" as CFString, kCFBooleanTrue)
                }
            }
        }
    }

    /// Browser, der gerade von PopSofa vergrößert wurde.
    private static var zoomedPID: pid_t?

    /// Zurück auf 100 %, sobald man PopSofa wieder aufruft – Safari/Chrome merken sich den Zoom
    /// sonst pro Website, und Netflix wäre auch außerhalb von PopSofa vergrößert.
    // ponytail: setzt nur den vorderen Tab des Browsers zurück; wer vorher den Tab gewechselt hat,
    // setzt dort zurück und Netflix bleibt vergrößert. Abhilfe dann: Tab-URL per AppleScript prüfen.
    static func reset() {
        guard let pid = zoomedPID else { return }
        zoomedPID = nil
        let ax = AXUIElementCreateApplication(pid)
        if let item = menuItem(ax, chars: ["0"]) { AXUIElementPerformAction(item, kAXPressAction as CFString) }
    }

    /// Erster Menüpunkt mit ⌘ + Zeichen und den Zusatztasten `modifiers` (AX-Maske: 2 = ⌥, 4 = ⌃;
    /// Umschalt ist immer erlaubt), bis Untermenü-Tiefe 3.
    private static func menuItem(_ app: AXUIElement, chars: Set<String>, modifiers: Int = 0) -> AXUIElement? {
        guard let bar: AXUIElement = attr(app, kAXMenuBarAttribute) else { return nil }
        func search(_ el: AXUIElement, depth: Int) -> AXUIElement? {
            if let c: String = attr(el, kAXMenuItemCmdCharAttribute), chars.contains(c),
               let m: Int = attr(el, kAXMenuItemCmdModifiersAttribute), m & ~1 == modifiers { return el }
            guard depth > 0, let kids: [AXUIElement] = attr(el, kAXChildrenAttribute) else { return nil }
            for k in kids { if let hit = search(k, depth: depth - 1) { return hit } }
            return nil
        }
        return search(bar, depth: 5)   // Leiste → Menü → Einträge → Untermenü → Einträge
    }

    /// Wartet (max. 5 s, im Hintergrund aufrufen), bis der Browser vorne ist.
    static func waitFront(_ bundleID: String) -> pid_t? {
        for _ in 0..<20 {
            if let a = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { $0.isActive }) {
                return a.processIdentifier
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    static func selfTest() {
        precondition(steps(bundleID: "com.apple.Safari", scale: 1.15) == 1)
        precondition(steps(bundleID: "com.google.Chrome", scale: 1.3) == 2)
        precondition(steps(bundleID: "com.google.Chrome", scale: 1.05) == 1, "Auto 1,05 → 110 %")
        precondition(steps(bundleID: "com.google.Chrome", scale: 1.0) == 0)
        precondition(steps(bundleID: "com.google.Chrome", scale: 1.6) == 3)
        precondition(steps(bundleID: "com.apple.Safari", scale: 2.0) == 5)
        precondition(steps(bundleID: "com.google.Chrome", scale: 0.9) == 0)
        print("✓ BrowserZoom")
    }
}

// MARK: - Profil bei Netflix/Prime anklicken

/// Erscheint „Wer schaut gerade?“, wird der Knopf mit dem Namen des PopSofa-Profils gedrückt –
/// über die Bedienungshilfen (Seiteninhalt ist dort als Link/Knopf sichtbar), ohne JavaScript.
// ponytail: hängt am Seitenaufbau von Netflix/Amazon; ändert der sich, bleibt einfach die normale Auswahl stehen.
enum StreamProfile {
    /// Dienste mit mehreren Profilen (Nutzer: Netflix, Prime Video, HBO Max, Disney+).
    static let ids: Set<String> = ["netflix", "prime", "hbomax", "disney"]

    /// Wo es eine eigene „Wer schaut?“-Adresse gibt, öffnet PopSofa sie direkt – dann erscheint die Auswahl immer.
    /// Geprüft 11/2026: Netflix /profiles (zeigt die Auswahl), Prime /profiles („Switch to … profile“).
    /// HBO Max und Disney+: keine stabile Adresse gefunden – dort nur, wenn die Auswahl von selbst kommt.
    static let pickerURL: [String: String] = [
        "netflix": "https://www.netflix.com/profiles",
        "prime": "https://www.primevideo.com/profiles",
    ]

    /// Aktivierte Dienste mit Profilen, in der Reihenfolge der Kacheln.
    static func services(enabled: Set<String>, all: [Service]) -> [Service] {
        all.filter { ids.contains($0.id) && enabled.contains($0.id) }
    }

    /// Passt die Beschriftung zum Profilnamen? Genau gleich (Netflix: „Ralf“) oder als ganze Wörter
    /// darin (Prime: „Switch to Alex profile“) – aber „ralf30acker“ passt nicht zu „Ralf“.
    static func matches(_ label: String, _ want: String) -> Int? {
        let l = norm(label)
        if l == want { return 2 }
        let words = { (s: String) in s.split { !$0.isLetter && !$0.isNumber }.map(String.init) }
        let lw = words(l), ww = words(want)
        guard !ww.isEmpty, lw.count > ww.count else { return nil }
        for i in 0...(lw.count - ww.count) where Array(lw[i..<i + ww.count]) == ww { return 1 }
        return nil
    }

    static func norm(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func pick(bundleID: String, name: String) {
        let want = norm(name)
        guard !want.isEmpty, Input.hasAccessibility(prompt: false) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let pid = BrowserZoom.waitFront(bundleID) else { return }
            let app = AXUIElementCreateApplication(pid)
            // Chrome & Co. liefern den Seiteninhalt erst, wenn eine Bedienungshilfe danach fragt.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            var seen = 0
            for _ in 0..<30 {   // bis 15 s: Seite lädt
                Thread.sleep(forTimeInterval: 0.5)
                guard let win: AXUIElement = BrowserZoom.attr(app, kAXFocusedWindowAttribute)
                        ?? BrowserZoom.attr(app, kAXMainWindowAttribute) else { continue }
                let (hit, n) = find(win, want)
                seen = max(seen, n)
                if let hit {
                    let r = AXUIElementPerformAction(hit, kAXPressAction as CFString)
                    PadLog.write("Profil „\(name)“ angeklickt (\(r == .success ? "ok" : "Fehler \(r.rawValue)"))")
                    return
                }
            }
            PadLog.write("Profil „\(name)“ nicht gefunden – \(seen) Elemente durchsucht")
        }
    }

    /// Breitensuche nach Link/Knopf mit dem Namen – genauer Treffer vor „enthält den Namen“.
    private static func find(_ root: AXUIElement, _ want: String) -> (AXUIElement?, Int) {
        var queue = [root], budget = 6000, best: (AXUIElement, Int)?
        while !queue.isEmpty, budget > 0 {
            let el = queue.removeFirst(); budget -= 1
            let role: String = BrowserZoom.attr(el, kAXRoleAttribute) ?? ""
            if role == "AXLink" || role == kAXButtonRole {
                let score = labels(el).compactMap { matches($0, want) }.max() ?? 0
                if score == 2 { return (el, 6000 - budget) }
                if score == 1, best == nil { best = (el, score) }
                continue                       // in Knöpfe nicht weiter hinabsteigen
            }
            if let kids: [AXUIElement] = BrowserZoom.attr(el, kAXChildrenAttribute) { queue += kids }
        }
        return (best?.0, 6000 - budget)
    }

    /// Titel/Beschreibung des Elements und Texte darin (bis 3 Ebenen tief).
    private static func labels(_ el: AXUIElement, depth: Int = 3) -> [String] {
        var out = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { BrowserZoom.attr(el, $0) as String? }
        if depth > 0, let kids: [AXUIElement] = BrowserZoom.attr(el, kAXChildrenAttribute) {
            for k in kids.prefix(8) { out += labels(k, depth: depth - 1) }
        }
        return out
    }

    static func selfTest() {
        precondition(norm(" alex ") == norm("Alex"))
        precondition(norm("Alexa") != norm("Alex"))
        precondition(norm("Zoë") == norm("zoe"))
        precondition(matches("Ralf", "ralf") == 2, "Netflix: genau")
        precondition(matches("Switch to Alex profile", "alex") == 1, "Prime: im Satz")
        precondition(matches("ralf30acker", "ralf") == nil, "Teilwort zählt nicht")
        precondition(matches("Onkel Latscho", "latscho") == 1)
        precondition(matches("Edit profile", "alex") == nil)
        print("✓ StreamProfile")
    }
}
