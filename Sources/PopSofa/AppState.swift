import SwiftUI
import AppKit
import WebKit

enum Sheet: String, Identifiable {
    case add, key, genres, remote, profile, eyeTest, distance, services, access, colorTest, prism
    var id: String { rawValue }
}

enum Tile: Identifiable {
    case search
    case ours           // Unsere Watchlist (ab zwei Profilen)
    case service(Service)
    case manage
    case add

    var id: String {
        switch self {
        case .search: return "_search"
        case .ours: return "_ours"
        case .service(let s): return s.id
        case .manage: return "_manage"
        case .add: return "_add"
        }
    }
}

/// Skalierung nach Rolle statt einfachem Zoom. Basis „Mittel“ = 13"-MacBook-Air aus 65 cm.
///
/// `m` = Modusfaktor (Klein 0,85 · Mittel 1 · Groß 1,5 · Sehr groß 2; Auto stufenlos nach Abstand & Sehtest).
/// Schrift wächst je nach Grundgröße unterschiedlich stark: f = 1 + (m − 1) · d,
///   d = 1 bis 18 pt (Fließtext, Hinweise), fällt linear auf 0,5 bei 48 pt (große Überschriften), darunter bleibt 0,5.
/// Flächen (Kacheln, Poster, Avatare, Abstände) wachsen gedämpft: s = 1 + (m − 1) · 0,6.
///
/// | Rolle (Grundgröße)        | Klein | Mittel | Groß | Sehr groß |
/// |---------------------------|-------|--------|------|-----------|
/// | Fließtext/Hinweis 15–18   | 0,85  | 1      | 1,5  | 2,0       |
/// | Titel 24                  | 0,86  | 1      | 1,45 | 1,90      |
/// | Überschrift 38            | 0,89  | 1      | 1,33 | 1,67      |
/// | Groß-Überschrift ≥ 48     | 0,93  | 1      | 1,25 | 1,50      |
/// | Flächen (Kachel, Avatar)  | 0,91  | 1      | 1,30 | 1,60      |
enum Metrics {
    static var m: CGFloat = 1
    /// Flächenfaktor (aus `m` abgeleitet, siehe oben).
    static var s: CGFloat = 1
    static func box(_ m: CGFloat) -> CGFloat { 1 + (m - 1) * 0.6 }
    /// Wachstumsanteil einer Schrift nach Grundgröße.
    static func damping(_ size: CGFloat) -> CGFloat { min(max(1 - (size - 18) / 30 * 0.5, 0.5), 1) }
    /// Faktor für eine Schrift dieser Grundgröße.
    static func text(_ size: CGFloat, m: CGFloat = m) -> CGFloat { 1 + (m - 1) * damping(size) }

    static func selfTest() {
        func r(_ x: CGFloat) -> CGFloat { (x * 100).rounded() / 100 }
        precondition(r(text(15, m: 2)) == 2 && r(text(38, m: 2)) == 1.67 && r(text(56, m: 2)) == 1.5)
        precondition(r(text(15, m: 0.85)) == 0.85 && r(text(38, m: 1.5)) == 1.33 && r(box(2)) == 1.6)
        precondition(text(30, m: 1) == 1)
    }
    /// Zusatzfaktor nur für Lesetext: Gleicher Sehwinkel reicht für Kacheln, aber kleiner Fließtext
    /// braucht vom Sofa aus mehr (tvOS-Richtwerte liegen deutlich über Desktop-Größen).
    static var read: CGFloat = 1
    /// Kachelbreite füllt die Zeile (siehe `setColumns`), Mindestbreite 240 · s; Höhe im Seitenverhältnis 16:10.
    static var tileW: CGFloat = 240
    static var tileH: CGFloat { tileW * 150 / 240 }
    static var gap: CGFloat { 30 * s }
    static var side: CGFloat { 56 * s }
    static var posterW: CGFloat { 150 * s }
    static var posterH: CGFloat { 225 * s }
    static var posterFooter: CGFloat { 34 * s }
    static var cardH: CGFloat { posterH + posterFooter }   // Poster + Fußzeile (Art, Jahr, Bewertung)
}

/// Textgröße: „Auto“ = normal am eingebauten Display, groß am Fernseher/externen Bildschirm.
enum TextSize: String, CaseIterable {
    case auto, small, normal, large, xlarge

    var title: String { ["auto": "Auto", "small": tr("Klein"), "normal": tr("Mittel"), "large": tr("Groß"), "xlarge": tr("Sehr groß")][rawValue]! }
    /// Beispielgröße fürs Menü („Aa“ in dieser Stufe).
    var preview: CGFloat { fixed ?? 1.15 }

    /// Faktor für feste Stufen; `.auto` rechnet über den Sehwinkel (siehe `autoScale`).
    var fixed: CGFloat? {
        switch self {
        case .auto: return nil
        case .small: return 0.85
        case .normal: return 1
        case .large: return 1.5
        case .xlarge: return 2
        }
    }

    /// Gleicher Sehwinkel wie am 13"-MacBook-Air aus 65 cm (0,198 mm pro Punkt).
    /// Ohne Bildschirmgröße (manche TVs melden keine): 1,0 eingebaut, 1,5 extern.
    static func autoScale(mmPerPoint: CGFloat?, distanceMM: CGFloat, builtIn: Bool) -> CGFloat {
        guard let mm = mmPerPoint, mm > 0.05 else { return builtIn ? 1 : 1.5 }
        let s = (distanceMM / 650) * (0.198 / mm)
        return min(max((s * 20).rounded() / 20, 1), 2)
    }

    /// Hauptbildschirm: eingebaut?, mm pro Punkt (aus der echten Breite), Schlüssel für den gemerkten Abstand.
    static var screenInfo: (builtIn: Bool, mmPerPoint: CGFloat?, widthPt: CGFloat) {
        guard let scr = NSScreen.main ?? NSScreen.screens.first,
              let n = scr.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return (true, nil, 1440) }
        var id = n.uint32Value
        // Gespiegelt (MacBook + TV zeigen dasselbe): macOS meldet nur einen Bildschirm, oft den eingebauten.
        // Dann zählt der externe – gelesen wird vom Sofa aus.
        if CGDisplayIsInMirrorSet(id) != 0, let ext = mirrorPartners(of: id).first(where: { CGDisplayIsBuiltin($0) == 0 }) {
            id = ext
        }
        let mm = CGDisplayScreenSize(id).width
        return (CGDisplayIsBuiltin(id) != 0, mm > 0 ? mm / scr.frame.width : nil, scr.frame.width)
    }

    /// Alle Displays, die dasselbe Bild zeigen wie `id` (gleicher Spiegel-Master).
    static func mirrorPartners(of id: CGDirectDisplayID) -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &n) == .success else { return [] }
        func master(_ d: CGDirectDisplayID) -> CGDirectDisplayID {
            let m = CGDisplayMirrorsDisplay(d)
            return m == kCGNullDirectDisplay ? d : m
        }
        let mine = master(id)
        return ids.prefix(Int(n)).filter { $0 != id && master($0) == mine }
    }

    /// +15 % je Meter über 65 cm, höchstens +35 % (2,4 m → ≈ 1,26).
    static func readBoost(distanceMM d: CGFloat) -> CGFloat {
        min(max(1 + 0.15 * (d - 650) / 1000, 1), 1.35)
    }

    static func distanceKey(builtIn: Bool) -> String { builtIn ? "viewDistance.builtin" : "viewDistance.external" }

    /// Gemessener Abstand in mm, sonst Annahme: 65 cm am MacBook, 70 cm am Schreibtisch-Monitor (< 32"),
    /// 2,4 m am Fernseher.
    static func distance(builtIn: Bool, mmPerPoint: CGFloat?, widthPt: CGFloat) -> CGFloat {
        let v = UserDefaults.standard.double(forKey: distanceKey(builtIn: builtIn))
        if v > 0 { return v }
        if builtIn { return 650 }
        if let mm = mmPerPoint, mm * widthPt < 700 { return 700 }
        return 2400
    }

    static func selfTest() {
        precondition(autoScale(mmPerPoint: 286.0 / 1440, distanceMM: 650, builtIn: true) == 1)       // 13"-Air, 65 cm
        precondition(autoScale(mmPerPoint: 1107.0 / 1920, distanceMM: 2400, builtIn: false) == 1.25) // 50"-TV, 2,4 m
        precondition(autoScale(mmPerPoint: 885.0 / 1920, distanceMM: 2400, builtIn: false) == 1.6)   // 40"-TV, 2,4 m
        precondition(autoScale(mmPerPoint: nil, distanceMM: 2400, builtIn: false) == 1.5)
        precondition(readBoost(distanceMM: 650) == 1 && abs(readBoost(distanceMM: 2400) - 1.2625) < 0.001)
        precondition(readBoost(distanceMM: 6000) == 1.35)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var customServices: [Service] = []
    @Published var enabledIDs: Set<String>
    @Published var focusedIndex = 0
    @Published var editMode = false {
        didSet { if !editMode { movingService = false } }
    }
    @Published var movingService = false
    @Published var serviceOrder: [String] = UserDefaults.standard.stringArray(forKey: "serviceOrder") ?? []
    @Published var browser: BrowserChoice
    private var zoomHintShown = false
    @Published var autoMouse: Bool
    @Published var toast: String?
    @Published var sheet: Sheet? {
        didSet {
            if oldValue == .genres && sheet != .genres { finishGenres(); setupFlow = false }
            if sheet != oldValue, let s = sheet, [.add, .key, .profile, .remote].contains(s) { prepareForm() }
        }
    }
    // Formular-Seiten (Profil, Dienst, Schlüssel, iPhone)
    @Published var form: [String: String] = [:]
    @Published var formFocus = 0
    @Published var editingField: String?          // Feld mit Tastaturfokus
    @Published var setupFlow = false              // neues Profil: Name → Dienste → Sehtest (mit Messung) → Prismen → Farbtest → Genres
    // Abstand messen (Kamera mit Countdown, sonst Auswahl)
    @Published var distanceBanner: DistanceStep?
    @Published var faceSeen = false
    var afterDistance: Sheet?                     // nach der Auswahl zurück dorthin (z. B. Sehtest)
    var distanceRun = 0                           // verwirft alte Messungen
    var distancePromptUntil: Date?                // „Kein Gesicht – A = selbst wählen“ aktiv bis
    @Published var columns = 4

    // Eingebauter Browser
    @Published var webURL: URL? {
        didSet { webBarVisible = true; if webURL != nil { trailerPlaying = false } }   // Trailer verstummt, sobald eine Seite aufgeht
    }
    /// Leiste über dem eingebauten Browser: beim Runterscrollen weg, beim Hochscrollen wieder da.
    @Published var webBarVisible = true
    weak var webView: WKWebView?

    // Empfehlungen
    @Published private(set) var tmdbKey: String?
    @Published private(set) var rows: [PosterRow] = []
    @Published private(set) var recoStatus: String?
    @Published private(set) var recoFailed = false
    @Published var posterRow: Int?
    @Published var posterIndex = 0
    @Published var genreFocus = 0
    @Published private(set) var taste = Taste()
    @Published private(set) var providerCache: [String: [Int]] = [:]
    @Published var detail: Title? {
        didSet { if detail == nil { trailerPlaying = false } }
    }
    @Published private(set) var detailInfo: TitleDetails?
    @Published var detailFocus = 0
    @Published var inputMode: InputMode = .controller
    @Published var theme: Theme = Theme.stored(UserDefaults.standard.string(forKey: "theme") ?? "") ?? .apple {
        didSet { applyDisplayFilter() }
    }
    /// Farbsehschwäche (passt die Farben an) – gespeichert; Simulation nur bis zum Ausschalten.
    @Published var colorVision = ColorVision(rawValue: UserDefaults.standard.string(forKey: "colorVision") ?? "") ?? .normal {
        didSet { UserDefaults.standard.set(colorVision.rawValue, forKey: "colorVision"); applyDisplayFilter(); persist() }
    }
    @Published var simulateVision = false { didSet { applyDisplayFilter() } }
    /// Stärke der Farbsehschwäche aus dem Test: 0,5 = leicht, 1 = stark.
    @Published var colorVisionSeverity: Double = UserDefaults.standard.object(forKey: "colorVisionSeverity") as? Double ?? 1 {
        didSet { UserDefaults.standard.set(colorVisionSeverity, forKey: "colorVisionSeverity"); applyDisplayFilter(); persist() }
    }
    @Published var colorTest = ColorTest()
    // Unsere Watchlist
    @Published var oursOpen = false
    @Published var oursRow = 0                    // -1 = Schalter oben
    @Published var oursIndex = 0
    @Published var sharedOnly = UserDefaults.standard.bool(forKey: "sharedOnly")
    @Published var choice: ChoicePrompt?          // offene Auswahlliste (statt Weiterschalt-Knöpfen)
    // Länder & Sprache (pro Profil)
    @Published var country = "DE" { didSet { TMDB.language = Region.tmdb(language: contentLanguage, country: country) } }
    @Published var serviceCountries: [String: String] = [:]
    @Published var multiCountry = false            // Länder pro Dienst (sonst gilt das Streaming-Land für alle)
    @Published var contentLanguage = "de" { didSet { TMDB.language = Region.tmdb(language: contentLanguage, country: country); L10n.lang = contentLanguage } }
    @Published var clearContrast = ClearContrast(rawValue: UserDefaults.standard.string(forKey: "clearContrast") ?? "") ?? .strong {
        didSet { UserDefaults.standard.set(clearContrast.rawValue, forKey: "clearContrast"); applyDisplayFilter(); persist() }
    }
    var themeBeforeClear: Theme?
    @Published var trailerPlaying = false { didSet { trailerPaused = false } }
    @Published var trailerPaused = false
    @Published var textSize: TextSize = TextSize(rawValue: UserDefaults.standard.string(forKey: "textSize") ?? "") ?? .auto {
        didSet { updateScale() }
    }
    @Published private(set) var uiScale: CGFloat = 1
    @Published var tileWidth: CGFloat = 240
    @Published private(set) var readScale: CGFloat = 1
    @Published private(set) var watchlist: [Title] = []

    // Profile („Wer schaut?“)
    @Published var profiles: [Profile] = []
    @Published private(set) var activeProfileID = UUID()
    @Published var profilePicker = false
    @Published var profileRequired = false        // Start: erst ein Profil wählen, kein Zurück
    @Published var profileFocus = 0
    var editingProfile: UUID?
    weak var inlineTrailer: InlineTrailerView.Coordinator?

    // Kopfzeile: 0 = Textgröße, 1 = iPhone koppeln. Textgrößen-Menü: 0…3 Stufen, 4 = Kamera-Messung.
    @Published var headerFocus: Int?
    /// Zurück-Knopf oben links per Controller angewählt (gilt für die jeweils oberste Ebene).
    @Published var backFocus = false
    @Published var searchOnField = false    // Suche: Eingabefeld angewählt
    @Published var searchFocusRequest = 0   // Suchfeld soll den Tastaturfokus holen
    @Published var sortFocus = false        // „Alle anzeigen“: Sortier-Knopf angewählt
    @Published var textMenu = false
    @Published var textMenuFocus = 0
    @Published var themeMenu = false              // Stil-Auswahl oben links
    /// Start-Animation; jede Eingabe überspringt sie.
    @Published var splash = true { didSet { if oldValue && !splash && !profilePicker { offerDistance() } } }
    @Published var soundsOn = UISound.shared.enabled {
        didSet { UISound.shared.enabled = soundsOn }
    }

    // „Alle anzeigen“
    @Published var category: Category?
    @Published var categoryIndex = 0
    var categoryColumns = 6

    // Suche
    @Published var searchOpen = false
    @Published var searchText = ""
    @Published private(set) var searchResults: [Title] = []
    @Published private(set) var searchStatus: String?
    @Published private(set) var searching = false
    @Published var searchInResults = false
    @Published var searchChip = 0
    @Published var searchIndex = 0
    var searchToken = 0

    func setSearch(results: [Title]?, status: String?, busy: Bool) {
        if let r = results { searchResults = r }
        searchStatus = status
        searching = busy
    }

    let controller = ControllerManager()
    let remote = RemoteServer()
    private var toastToken = 0
    private var loadToken = 0

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "customServices"),
           let list = try? JSONDecoder().decode([Service].self, from: data) {
            customServices = list
        }
        if let ids = d.array(forKey: "enabledIDs") as? [String] {
            enabledIDs = Set(ids)
        } else {
            enabledIDs = Catalog.defaultEnabled
        }
        browser = BrowserChoice(rawValue: d.string(forKey: "browser") ?? "") ?? .system
        // Einmalig wieder einschalten: Der Schalter lag auf LB und wurde leicht versehentlich ausgelöst.
        if d.object(forKey: "autoMouseReset1") == nil {
            d.set(true, forKey: "autoMouse"); d.set(true, forKey: "autoMouseReset1")
        }
        autoMouse = d.object(forKey: "autoMouse") as? Bool ?? true
        let (list, active) = Profile.load(d)
        profiles = list
        activeProfileID = active
        if let p = profiles.first(where: { $0.id == active }) {
            taste = p.taste; watchlist = p.watchlist
            if let sv = p.services { enabledIDs = Set(sv) }   // jedes Profil hat seine eigenen Dienste
            if let t = p.theme.flatMap(Theme.stored) { theme = t }
            if let v = p.colorVision.flatMap(ColorVision.init(rawValue:)) { colorVision = v }
            if let s = p.colorVisionSeverity { colorVisionSeverity = s }
            if let c = p.clearContrast.flatMap(ClearContrast.init(rawValue:)) { clearContrast = c }
            country = p.country ?? "DE"
            serviceCountries = p.serviceCountries ?? [:]
            multiCountry = p.multiCountry ?? !serviceCountries.isEmpty
            contentLanguage = p.language ?? Region.defaultLanguage(country)
        }
        TMDB.language = Region.tmdb(language: contentLanguage, country: country)
        L10n.lang = contentLanguage   // im init greift didSet nicht
        profilePicker = list.count > 1   // nach dem Splash: „Wer schaut?“
        profileRequired = profilePicker
        profileFocus = list.firstIndex { $0.id == active } ?? 0
        tmdbKey = Keychain.get()

        controller.onEvent = { [weak self] e in
            self?.inputMode = .controller
            self?.handle(e)
        }
        controller.onToast = { [weak self] in self?.showToast($0) }
        Typo.update(for: theme)   // Schrift des Stils schon beim ersten Zeichnen
        controller.onHome = { [weak self] in self?.webURL = nil }
        controller.onScroll = { [weak self] dy in
            guard let self else { return }
            self.inputMode = .controller
            // Eingebauter Browser: echtes Mausrad-Ereignis an die Webseite; sonst die PopSofa-Ansicht.
            if self.webURL != nil {
                if Input.hasAccessibility(prompt: false) { Mouse.scroll(dx: 0, dy: Int32(dy)) }
            } else {
                NotificationCenter.default.post(name: .padScroll, object: nil, userInfo: ["dy": dy])
            }
        }
        updateScale()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateScale() }
        }
        // Zurück in PopSofa (⌘⇥, Klick) oder Beenden → Browser-Zoom wieder 100 %.
        for n in [NSApplication.didBecomeActiveNotification, NSApplication.willTerminateNotification] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { BrowserZoom.reset() }
            }
        }
        controller.start()
        remote.attach(self)
        reloadRecommendations()
        startKeyboardInput()
        // Dock-Symbol direkt aus dem App-Paket setzen – sonst zeigt das Dock evtl. ein zwischengespeichertes altes Icon.
        if let icon = Bundle.main.image(forResource: "AppIcon") { NSApp.applicationIconImage = icon }
        Debug.run(self)
    }

    // MARK: Daten

    /// Dienste in deiner Reihenfolge (neue/unbekannte hinten, in Katalog-Reihenfolge).
    var allServices: [Service] {
        let list = Catalog.all + customServices
        let pos = Dictionary(serviceOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return list.enumerated().sorted { a, b in
            (pos[a.element.id] ?? 10_000 + a.offset) < (pos[b.element.id] ?? 10_000 + b.offset)
        }.map(\.element)
    }

    /// Im Bearbeiten-Modus: fokussierten Dienst um `delta` Plätze verschieben.
    func moveService(by delta: Int) {
        guard allServices.indices.contains(focusedIndex) else { return }
        moveService(allServices[focusedIndex].id, to: focusedIndex + delta)
    }

    /// Dienst `id` an Position `target` setzen (Controller, Tastatur, Ziehen mit der Maus, ‹ ›-Knöpfe).
    func moveService(_ id: String, to target: Int) {
        var ids = allServices.map(\.id)
        guard let from = ids.firstIndex(of: id) else { return }
        let to = min(max(target, 0), ids.count - 1)
        guard to != from else { return }
        ids.insert(ids.remove(at: from), at: to)
        serviceOrder = ids
        focusedIndex = to
        persist()
    }

    var items: [Tile] {
        if editMode {
            return allServices.map(Tile.service) + [.add]
        }
        return [.search] + (profiles.count >= 2 ? [.ours] : []) + allServices.filter { enabledIDs.contains($0.id) }.map(Tile.service) + [.manage]
    }

    var focusedItem: Tile? {
        let list = items
        return list.indices.contains(focusedIndex) ? list[focusedIndex] : nil
    }

    var focusedService: Service? {
        if case .service(let s)? = focusedItem { return s }
        return nil
    }

    func persist() {
        let d = UserDefaults.standard
        d.set(Array(enabledIDs), forKey: "enabledIDs")
        if let data = try? JSONEncoder().encode(customServices) { d.set(data, forKey: "customServices") }
        d.set(browser.rawValue, forKey: "browser")
        d.set(autoMouse, forKey: "autoMouse")
        d.set(theme.rawValue, forKey: "theme")
        d.set(serviceOrder, forKey: "serviceOrder")
        if let i = profiles.firstIndex(where: { $0.id == activeProfileID }) {
            profiles[i].taste = taste
            profiles[i].watchlist = watchlist
            profiles[i].services = Array(enabledIDs)
            profiles[i].theme = theme.rawValue
            profiles[i].colorVision = colorVision.rawValue
            profiles[i].colorVisionSeverity = colorVisionSeverity
            profiles[i].clearContrast = clearContrast.rawValue
            profiles[i].country = country
            profiles[i].serviceCountries = serviceCountries
            profiles[i].multiCountry = multiCountry
            profiles[i].language = contentLanguage
        }
        Profile.save(profiles, active: activeProfileID, d)
    }

    /// Profil wechseln: aktuelles sichern, Geschmack + Merkliste des anderen laden, Empfehlungen neu.
    func switchProfile(_ id: UUID, keepPicker: Bool = false) {
        if profiles.contains(where: { $0.id == activeProfileID }) { persist() }
        guard let p = profiles.first(where: { $0.id == id }) else { return }
        activeProfileID = id
        profileRequired = false
        updateScale()
        taste = p.taste
        watchlist = p.watchlist
        if let sv = p.services { enabledIDs = Set(sv) }   // ohne eigene Auswahl: die bisherigen übernehmen
        // Stil und Barrierefreiheit der Person – erst nach Geschmack/Merkliste, weil jede Änderung speichert.
        simulateVision = false
        if let t = p.theme.flatMap(Theme.stored) { theme = t }
        if let v = p.colorVision.flatMap(ColorVision.init(rawValue:)) { colorVision = v }
        if let s = p.colorVisionSeverity { colorVisionSeverity = s }
        if let c = p.clearContrast.flatMap(ClearContrast.init(rawValue:)) { clearContrast = c }
        country = p.country ?? country
        serviceCountries = p.serviceCountries ?? [:]
        multiCountry = p.multiCountry ?? !serviceCountries.isEmpty
        contentLanguage = p.language ?? Region.defaultLanguage(country)
        providerCache = [:]   // Verfügbarkeit hängt an den Ländern der Person
        clampFocus()
        persist()
        profilePicker = keepPicker
        category = nil
        posterRow = nil
        headerFocus = nil
        reloadRecommendations()
        if !taste.onboarded && tmdbKey != nil { sheet = .genres }
        if !keepPicker { showToast(tr("Hallo %@!", p.name)); offerDistance() }
    }

    func updateScale() {
        let i = TextSize.screenInfo
        let d = currentDistance   // am TV pro Profil, sonst pro Bildschirm
        var s = textSize.fixed ?? TextSize.autoScale(mmPerPoint: i.mmPerPoint, distanceMM: d, builtIn: i.builtIn)
        // Sehtest des Profils gilt nur für „Auto“ – manuelle Stufen bleiben, wie gewählt.
        if textSize == .auto, let v = activeProfile?.vision { s = min((s * CGFloat(v) * 20).rounded() / 20, 2.2) }
        // Manuelle Stufen gelten für alles gleich; nur Auto gibt Lesetext den Abstands-Zuschlag.
        let r = textSize == .auto ? TextSize.readBoost(distanceMM: d) : 1
        guard s != uiScale || r != readScale || Metrics.m != s else { return }
        Metrics.m = s
        Metrics.s = Metrics.box(s)
        Metrics.read = r
        uiScale = s
        readScale = r
    }

    // MARK: Kopfzeile

    func handleHeader(_ e: PadEvent, _ h: Int) {
        // Reihenfolge von links: Stil (3, ganz links), Profil (2), Textgröße (0), iPhone (1)
        let order = [3, 2, 0, 1], pos = order.firstIndex(of: h) ?? 1
        switch e {
        case .left: headerFocus = order[max(pos - 1, 0)]
        case .right: headerFocus = order[min(pos + 1, order.count - 1)]
        case .down, .b: headerFocus = nil
        case .a:
            switch h {
            case 0: openTextMenu()
            case 1: sheet = .remote
            case 3: themeMenu = true
            default: openProfilePicker()
            }
        default: break
        }
    }

    func setTheme(_ t: Theme) {
        guard t != theme else { return }
        withAnimation(.easeInOut(duration: 0.35)) { theme = t }
        persist()
    }

    /// Stil-Menü: ↑↓ zeigt den Stil sofort, A oder B schließt.
    func handleThemeMenu(_ e: PadEvent) {
        let all = Theme.allCases, i = all.firstIndex(of: theme) ?? 0
        switch e {
        case .up: setTheme(all[max(i - 1, 0)])
        case .down: setTheme(all[min(i + 1, all.count - 1)])
        case .a, .b: themeMenu = false
        default: break
        }
    }

    func openTextMenu() {
        textMenuFocus = TextSize.allCases.firstIndex(of: textSize) ?? 0
        textMenu = true
    }

    func setTextSize(_ t: TextSize) {
        textSize = t
        UserDefaults.standard.set(t.rawValue, forKey: "textSize")
    }

    func handleTextMenu(_ e: PadEvent) {
        let n = TextSize.allCases.count + 2   // danach: Abstand messen, Barrierefreiheit, Bedientöne
        switch e {
        case .up: textMenuFocus = max(textMenuFocus - 1, 0)
        case .down: textMenuFocus = min(textMenuFocus + 1, n)
        case .a: chooseTextMenu(textMenuFocus)
        case .b: textMenu = false
        default: break
        }
    }

    func chooseTextMenu(_ i: Int) {
        textMenuFocus = i
        if TextSize.allCases.indices.contains(i) {
            setTextSize(TextSize.allCases[i])      // Menü bleibt offen: Wirkung sofort sichtbar
        } else if i == TextSize.allCases.count + 1 {
            textMenu = false
            formFocus = 0
            sheet = .access
        } else if i > TextSize.allCases.count {
            soundsOn.toggle()
            if soundsOn { UISound.shared.play(.select, theme: theme) }
        } else {
            textMenu = false
            setTextSize(.auto)
            measureDistance()
        }
    }

    /// „Auto (groß)“ – zeigt, was Auto gerade gewählt hat.
    var textSizeLabel: String {
        textSize == .auto ? "Auto (\(tr(uiScale >= 1.75 ? "sehr groß" : uiScale >= 1.25 ? "groß" : uiScale < 0.95 ? "klein" : "mittel")))" : textSize.title
    }

    func clampFocus() {
        focusedIndex = min(max(focusedIndex, 0), max(items.count - 1, 0))
    }

    /// Adaptiv: so viele Spalten wie mit Mindestbreite passen, dann füllen die Kacheln die Zeile ganz aus.
    func setColumns(for width: CGFloat) {
        let usable = width - 2 * Metrics.side
        let c = max(2, Int((usable + Metrics.gap) / (240 * Metrics.s + Metrics.gap)))
        let w = min(((usable - CGFloat(c - 1) * Metrics.gap) / CGFloat(c)).rounded(.down), 360 * Metrics.s)
        Metrics.tileW = w
        if c != columns { columns = c }
        if w != tileWidth { tileWidth = w }
    }

    func showToast(_ text: String, seconds: Double = 3.5) {
        toastToken += 1
        let token = toastToken
        withAnimation(.easeOut(duration: 0.25)) { toast = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if token == toastToken { withAnimation(.easeIn(duration: 0.25)) { toast = nil } }
        }
    }

    // MARK: Aktionen

    func isEnabled(_ s: Service) -> Bool { enabledIDs.contains(s.id) }

    func toggle(_ s: Service) {
        if enabledIDs.contains(s.id) { enabledIDs.remove(s.id) } else { enabledIDs.insert(s.id) }
        persist()
        reloadRecommendations()
    }

    func launch(_ s: Service, url override: URL? = nil) {
        guard var url = override ?? URL(string: s.url) else { return }
        trailerPlaying = false   // Netflix & Co. im externen Browser: Trailer im Hintergrund stoppen
        if s.drm == true {
            // Dienst mit Profilen: direkt die „Wer schaut?“-Seite öffnen (erscheint dann immer) und
            // dort das Profil anklicken lassen. Bei Titel-Links (override) bleibt es beim Titel.
            let picker = StreamProfile.pickerURL[s.id].flatMap(URL.init(string:))
            let who = StreamProfile.ids.contains(s.id) ? activeProfile?.streamName(s.id) : nil
            if override == nil, who != nil, let picker { url = picker }
            browser.open(url, reuseHost: s.host, profile: who)
            if uiScale > 1.05, !Input.hasAccessibility(prompt: false), !zoomHintShown {
                zoomHintShown = true
                showToast(tr("Für Browser-Zoom PopSofa in den Bedienungshilfen erlauben"))
            }
        } else { webURL = url }
        if autoMouse && controller.controllerName != nil { controller.setMouseMode(true) }
    }

    private func webBack() {
        if let w = webView, w.canGoBack { w.goBack() } else { webURL = nil }
    }

    func addCustom(name: String, urlString: String) {
        var u = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return }
        if !u.contains("://") { u = "https://" + u }
        guard let parsed = URL(string: u), parsed.host != nil else {
            showToast(tr("Diese Adresse ist ungültig."))
            return
        }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = Catalog.customPalette.randomElement() ?? ("#2E8B9A", "#0B2A30")
        let s = Service(id: "custom-" + UUID().uuidString,
                        name: n.isEmpty ? (parsed.host ?? u) : n,
                        url: u, colorTop: c.0, colorBottom: c.1,
                        symbol: "globe", isCustom: true)
        customServices.append(s)
        enabledIDs.insert(s.id)
        persist()
        if let idx = items.firstIndex(where: { $0.id == s.id }) { focusedIndex = idx }
        sheet = nil
    }

    private func deleteCustom(_ s: Service) {
        customServices.removeAll { $0.id == s.id }
        enabledIDs.remove(s.id)
        persist()
        clampFocus()
        showToast(tr("„%@“ gelöscht", s.name))
    }

    private func cycleBrowser() {
        let installed = BrowserChoice.allCases.filter(\.isInstalled)
        let idx = installed.firstIndex(of: browser) ?? 0
        browser = installed[(idx + 1) % installed.count]
        persist()
        showToast(tr("Browser: %@", browser.title))
    }

    // MARK: Navigation

    private func move(dx: Int, dy: Int) {
        let n = items.count
        guard n > 0 else { return }
        var i = focusedIndex
        if dx != 0 {
            i = min(max(i + dx, 0), n - 1)
        } else if dy != 0 {
            let t = i + dy * columns
            if t >= 0 && t < n {
                i = t
            } else if dy < 0 {
                // Oberste Reihe → Kopfzeile (Textgröße, iPhone).
                headerFocus = 0
                return
            } else if dy > 0 && i / columns < (n - 1) / columns {
                i = n - 1
            } else if dy > 0 && !editMode && hasPosterSection {
                enterPosters(row: 0)
                return
            }
        }
        focusedIndex = i
    }

    func activate() {
        switch focusedItem {
        case .service(let s)?:
            if editMode { toggle(s) } else { launch(s) }
        case .manage?:
            editMode = true
            clampFocus()
        case .add?:
            sheet = .add
        case .search?:
            openSearch()
        case .ours?:
            openOurs()
        case nil:
            break
        }
    }

    /// Jede Eingabe (Controller, Tastatur, iPhone) läuft hier durch – mit passendem Bedienton.
    func handle(_ e: PadEvent) {
        if splash { withAnimation(.easeOut(duration: 0.25)) { splash = false }; return }
        guard webURL == nil else { route(e); return }    // im Browser keine Töne
        // Messung gescheitert: A öffnet die Auswahl, jede andere Eingabe blendet den Hinweis aus.
        if let until = distancePromptUntil {
            distancePromptUntil = nil
            if until > Date() {
                withAnimation { distanceBanner = nil }
                if e == .a && !profilePicker {
                    openDistanceChoices()
                    UISound.shared.play(.select, theme: theme)
                    return
                }
            }
        }
        let before = focusSnapshot
        let opened = (sheet != nil, detail != nil, category != nil || oursOpen, searchOpen, textMenu || themeMenu || profilePicker)
        route(e)
        // Neue Ebene geöffnet oder geschlossen: Fokus beginnt wieder im Inhalt, nicht auf „Zurück“.
        if (sheet != nil, detail != nil, category != nil || oursOpen, searchOpen, textMenu || themeMenu || profilePicker) != opened {
            backFocus = false; sortFocus = false; searchOnField = false
        }
        let kind: UISound.Kind?
        switch e {
        case .up, .down, .left, .right:
            kind = focusSnapshot != before ? .move : nil
        case .a, .x, .y:
            kind = .select
        case .b:
            let now = (sheet != nil, detail != nil, category != nil || oursOpen, searchOpen, textMenu || themeMenu || profilePicker)
            kind = now != opened || focusSnapshot != before ? .back : nil
        case .lb, .rb:
            kind = .select
        }
        if let kind { UISound.shared.play(kind, theme: theme) }
    }

    /// Alles, was sich bei einer Fokus-Bewegung ändern kann.
    private var focusSnapshot: [Int] {
        [focusedIndex, serviceOrder.count == 0 ? 0 : serviceOrder.hashValue, posterRow ?? -1, posterIndex, headerFocus ?? -1, textMenuFocus, Theme.allCases.firstIndex(of: theme) ?? 0, searchIndex, searchChip,
         searchInResults ? 1 : 0, categoryIndex, profileFocus, detailFocus, genreFocus, sheet == nil ? 0 : 1, oursRow, oursIndex, sharedOnly ? 1 : 0]
    }

    private func route(_ e: PadEvent) {
        if choice != nil { handleChoice(e); return }   // offene Auswahlliste hat Vorrang
        switch sheet {
        case .genres?: handleGenres(e); return
        case .eyeTest?: handleEyeTest(e); return
        case .distance?: handleDistance(e); return
        case .services?: handleServicePicks(e); return
        case .access?: handleAccess(e); return
        case .colorTest?: handleColorTest(e); return
        case .prism?: handlePrism(e); return
        case .some: handleForm(e); return
        case nil: break
        }
        if webURL != nil {
            if e == .b { webBack() }
            return
        }
        if profilePicker { handleProfiles(e); return }
        if detail != nil { handleDetail(e); return }
        if oursOpen { handleOurs(e); return }
        if category != nil { handleCategory(e); return }
        if searchOpen { handleSearch(e); return }
        if textMenu { handleTextMenu(e); return }
        if themeMenu { handleThemeMenu(e); return }
        if let h = headerFocus { handleHeader(e, h); return }
        if let r = posterRow { handlePosters(e, row: r); return }
        // Dienst verschieben: Pfeile bewegen die Kachel, A/B/RB legen sie ab.
        if movingService {
            switch e {
            case .left: moveService(by: -1)
            case .right: moveService(by: 1)
            case .up: moveService(by: -columns)
            case .down: moveService(by: columns)
            case .a, .b, .rb: movingService = false
            default: break
            }
            return
        }
        switch e {
        case .up: move(dx: 0, dy: -1)
        case .down: move(dx: 0, dy: 1)
        case .left: move(dx: -1, dy: 0)
        case .right: move(dx: 1, dy: 0)
        case .a: activate()
        case .b:
            if editMode { editMode = false; clampFocus() }
        case .x:
            editMode.toggle()
            clampFocus()
        case .y:
            if editMode, case .service(let s)? = focusedItem, s.isCustom {
                deleteCustom(s)
            } else {
                cycleBrowser()
            }
        case .lb:
            guard editMode else { break }          // nur unter „Dienste verwalten“, nicht versehentlich
            autoMouse.toggle()
            persist()
            showToast(autoMouse ? tr("Maus-Modus startet automatisch nach dem Öffnen") : tr("Maus-Modus startet nicht mehr automatisch"))
        case .rb:
            if !editMode { sheet = tmdbKey == nil ? .key : .genres }
            else if case .service? = focusedItem { movingService = true }
        }
    }

    // MARK: Empfehlungen

    var showSetupCard: Bool { tmdbKey == nil || (recoFailed && rows.isEmpty) }
    var hasPosterSection: Bool { showSetupCard || !rows.isEmpty }

    var focusedTitle: Title? {
        guard let r = posterRow, rows.indices.contains(r), rows[r].items.indices.contains(posterIndex) else { return nil }
        return rows[r].items[posterIndex]
    }

    /// Merkt die Verfügbarkeit eines Titels – zusammengeführt aus den Ländern deiner Konten.
    func cacheProviders(_ key: String, _ byRegion: [String: [Int]]) { providerCache[key] = available(byRegion) }
    func resetAvailability() { providerCache = [:] }

    /// Land des Kontos für einen Dienst (sonst Heimatland des Profils).
    func region(_ service: String) -> String { multiCountry ? serviceCountries[service] ?? country : country }
    /// Eigene Dienste → Land ihres Kontos.
    var myServiceRegions: [String: String] { Dictionary(uniqueKeysWithValues: enabledIDs.map { ($0, region($0)) }) }
    /// Alle Länder, die für dieses Profil abgefragt werden.
    var regionsInUse: Set<String> { Set(myServiceRegions.values).union([country]) }

    func available(_ byRegion: [String: [Int]]) -> [Int] {
        Region.combine(byRegion, home: country, serviceRegion: myServiceRegions, byService: Providers.byService)
    }

    /// Dienst, bei dem der Titel im Abo läuft (nil = unbekannt oder noch nicht geladen).
    func serviceName(for t: Title) -> String? {
        guard let ids = providerCache[t.key] else { return nil }
        guard let sid = Providers.service(for: ids, preferring: enabledIDs) else { return "" }
        return allServices.first { $0.id == sid }?.name
    }

    private func enterPosters(row r: Int) {
        posterRow = r
        clampPoster()
        fetchProviders()
    }

    private func clampPoster() {
        guard let r = posterRow else { return }
        if showSetupCard { posterRow = 0; posterIndex = 0; return }
        if rows.isEmpty { posterRow = nil; return }
        posterRow = min(r, rows.count - 1)
        // Index == items.count ist die Karte „Alle anzeigen“ am Reihenende.
        posterIndex = min(max(posterIndex, 0), rows[posterRow!].items.count)
    }

    private func handlePosters(_ e: PadEvent, row r: Int) {
        if showSetupCard {
            switch e {
            case .a: sheet = .key
            case .up, .b: posterRow = nil
            default: break
            }
            return
        }
        switch e {
        case .left: posterIndex -= 1
        case .right: posterIndex += 1
        case .up: if r == 0 { posterRow = nil; return } else { posterRow = r - 1 }
        case .down: posterRow = min(r + 1, rows.count - 1)
        case .a:
            if let t = focusedTitle { openDetail(t) } else if rows.indices.contains(r) { openCategory(rows[r]) }
        case .x: if let t = focusedTitle { like(t) }
        case .y: if let t = focusedTitle { dislike(t) }
        case .b: posterRow = nil; return
        case .rb: sheet = .genres
        case .lb: break
        }
        clampPoster()
        fetchProviders()
    }

    private func fetchProviders() {
        guard let t = focusedTitle, providerCache[t.key] == nil, let key = tmdbKey else { return }
        Task {
            if let r = try? await TMDB(key: key).providers(t) { cacheProviders(t.key, r) }
        }
    }

    // MARK: Detailansicht

    /// Anbieter: erst deine aktivierten Dienste, dann bekannte, dann der Rest (Abo vor Leihen/Kaufen bleibt erhalten).
    var detailOptions: [ProviderOption] {
        let list = detailInfo?.providers ?? []
        func rank(_ p: ProviderOption) -> Int {
            guard let sid = p.serviceID else { return 2 }
            return enabledIDs.contains(sid) ? 0 : 1
        }
        return list.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    func openDetail(_ t: Title) {
        detail = t
        detailInfo = nil
        detailFocus = 0
        trailerPlaying = false
        guard let key = tmdbKey else { return }
        Task {
            // Eigene Dienste mit Konto in einem anderen Land: dort nachsehen.
            var extra: [String: Set<Int>] = [:]
            for (sid, r) in myServiceRegions where r != country { extra[r, default: []].formUnion(Providers.byService[sid] ?? []) }
            guard let info = try? await TMDB(key: key).details(t, home: country, extra: extra), detail?.key == t.key else { return }
            detailInfo = info
            withAnimation(.easeInOut(duration: 0.4)) { trailerPlaying = info.trailer != nil }   // sofort abspielen
            providerCache[t.key] = info.providers.filter { $0.kind != "Leihen" && $0.kind != "Kaufen" }.map(\.id)
        }
    }

    /// nil = „Alle Anbieter bei TMDB“.
    func choose(_ option: ProviderOption?) {
        guard let t = detail else { return }
        if let o = option, let sid = o.serviceID, let s = allServices.first(where: { $0.id == sid }) {
            launch(s, url: Providers.searchURL(service: sid, title: t.name))
            showToast(tr("„%@“ bei %@", t.name, s.name))
            return
        }
        let fallback = URL(string: "https://www.themoviedb.org/\(t.type)/\(t.id)/watch?locale=DE")
        guard let u = detailInfo?.link ?? fallback else { return }
        webURL = u
        if autoMouse && controller.controllerName != nil { controller.setMouseMode(true) }
        if let o = option { showToast(tr("%@: Link auf der Anbieter-Seite wählen", o.name)) }
    }

    /// Reihe in der Detailansicht: [Trailer?] + Watchlist + Anbieter + „Alle Anbieter“.
    var trailerOffset: Int { detailInfo?.trailer == nil ? 0 : 1 }
    var actionOffset: Int { trailerOffset + 1 }

    func activateDetail(_ i: Int) {
        detailFocus = i
        if i == trailerOffset, let t = detail { toggleWatchlist(t); return }
        if trailerOffset == 1 && i == 0 {
            // A = Start, dann Pause/Fortsetzen; groß auf YouTube mit RB.
            if !trailerPlaying { withAnimation { trailerPlaying = true } }
            else { trailerPaused.toggle(); inlineTrailer?.setPaused(trailerPaused) }
            return
        }
        let opts = detailOptions, j = i - actionOffset
        choose(opts.indices.contains(j) ? opts[j] : nil)
    }

    // MARK: Watchlist (lokal gespeichert)

    func isOnWatchlist(_ t: Title) -> Bool { watchlist.contains { $0.key == t.key } }

    func toggleWatchlist(_ t: Title) {
        if isOnWatchlist(t) {
            watchlist.removeAll { $0.key == t.key }
            showToast(tr("Von der Watchlist entfernt"))
        } else {
            watchlist.insert(t, at: 0)
            showToast(tr("„%@“ auf der Watchlist", t.name))
        }
        persist()
        let hadRow = rows.first?.id == "watchlist"
        rows = withWatchlist(rows.filter { $0.id != "watchlist" })
        let hasRow = rows.first?.id == "watchlist"
        // Fokus bleibt auf derselben Reihe, auch wenn die Watchlist-Reihe oben dazukommt/wegfällt.
        if let r = posterRow, hadRow != hasRow { posterRow = max(r + (hasRow ? 1 : -1), 0) }
        clampPoster()
    }

    /// „Meine Watchlist“ immer als erste Reihe (unabhängig von deinen Diensten).
    func withWatchlist(_ list: [PosterRow]) -> [PosterRow] {
        watchlist.isEmpty ? list : [PosterRow(id: "watchlist", title: tr("Meine Watchlist"), items: watchlist)] + list
    }

    func playTrailer() {
        guard let u = detailInfo?.trailerURL else { return }
        trailerPlaying = false
        webURL = u                                   // läuft im eingebauten Browser, B/⧉ = zurück zu den Details
        if autoMouse && controller.controllerName != nil { controller.setMouseMode(true) }
    }

    /// Gemeinsame Regel für „Zurück“: angewählt → A/B schließt, ↓/→ geht zurück in den Inhalt.
    func handleBack(_ e: PadEvent, close: () -> Void) -> Bool {
        guard backFocus else { return false }
        switch e {
        case .a, .b: backFocus = false; close()
        case .down, .right: backFocus = false
        default: break
        }
        return true
    }

    private func handleDetail(_ e: PadEvent) {
        if handleBack(e, close: { detail = nil }) { return }
        let count = actionOffset + detailOptions.count + 1
        switch e {
        case .up: backFocus = true
        case .left: detailFocus = max(detailFocus - 1, 0)
        case .right: detailFocus = min(detailFocus + 1, count - 1)
        case .a: activateDetail(detailFocus)
        case .x: if let t = detail { like(t) }
        case .y: if let t = detail { dislike(t); detail = nil }
        case .b: detail = nil
        case .rb: if trailerOffset == 1 { playTrailer() }
        default: break
        }
    }

    func like(_ t: Title) {
        taste.like(t)
        persist()
        showToast(tr("Gefällt dir – mehr wie „%@“", t.name))
        reloadRecommendations()
    }

    /// Titel, auf den sich „Gefällt mir“ gerade bezieht (Details, Kategorie, Suche oder Reihe).
    var currentTitle: Title? {
        if let d = detail { return d }
        if category != nil { return focusedCategoryTitle }
        if searchOpen { return searchInResults && searchResults.indices.contains(searchIndex) ? searchResults[searchIndex] : nil }
        return posterRow != nil ? focusedTitle : nil
    }

    func dislike(_ t: Title) {
        if detail?.key == t.key { detail = nil }
        searchResults.removeAll { $0.key == t.key }
        taste.dislike(t)
        persist()
        category?.items.removeAll { $0.key == t.key }
        for i in rows.indices { rows[i].items.removeAll { $0.key == t.key } }
        rows.removeAll { $0.items.isEmpty }
        clampPoster()
        showToast(tr("Ausgeblendet – weniger davon"))
    }

    func saveKey(_ raw: String) {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        Keychain.set(k)
        tmdbKey = k
        recoFailed = false
        sheet = taste.onboarded ? nil : .genres
        reloadRecommendations()
    }

    // Genre-Auswahl (Gitter mit 4 Spalten)
    static let genreColumns = 4

    func toggleGenre(_ g: Genre) { taste.toggle(g) }

    private func handleGenres(_ e: PadEvent) {
        if handleBack(e, close: { sheet = nil }) { return }
        let n = Genre.all.count, c = Self.genreColumns
        if genreFocus >= n {          // „Fertig“-Knopf unter dem Raster
            switch e {
            case .up: genreFocus = n - 1
            case .a, .b: sheet = nil
            default: break
            }
            return
        }
        switch e {
        case .left: genreFocus = max(genreFocus - 1, 0)
        case .right: genreFocus = min(genreFocus + 1, n - 1)
        case .up: if genreFocus - c >= 0 { genreFocus -= c } else { backFocus = true }
        case .down: genreFocus = genreFocus + c < n ? genreFocus + c : n
        case .a: taste.toggle(Genre.all[genreFocus])
        case .b: sheet = nil
        case .x: sheet = .key
        default: break
        }
    }

    private func finishGenres() {
        taste.onboarded = true
        persist()
        reloadRecommendations()
    }

    /// Basis-Filter für /discover, je Land eines: nur Titel, die bei deinen Diensten dort im Abo/kostenlos laufen.
    /// (TMDB kennt pro Abfrage nur ein Land – bei Konten in mehreren Ländern werden die Ergebnisse gemischt.)
    func discoverBases(only services: Set<String>? = nil) -> [[String: String]] {
        let svc = services ?? enabledIDs
        var byRegion: [String: Set<String>] = [:]
        for s in svc { byRegion[region(s), default: []].insert(s) }
        if byRegion.isEmpty { byRegion[country] = [] }
        return byRegion.keys.sorted().map { r in
            ["watch_region": r, "sort_by": "popularity.desc",
             "with_watch_monetization_types": "flatrate|free|ads",
             "with_watch_providers": Providers.ids(for: byRegion[r] ?? []).map(String.init).joined(separator: "|")]
        }
    }

    static func query(_ base: [String: String], _ extra: [String: String]) -> [String: String] {
        base.merging(extra) { $1 }.filter { !$0.value.isEmpty }
    }

    /// Lernt die echten Anbieter-IDs aus TMDB – für alle Länder, die dieses Profil nutzt.
    func ensureProviders(_ api: TMDB) async {
        let need = regionsInUse.union(Providers.learnedRegions)
        guard !need.isSubset(of: Providers.learnedRegions) else { return }
        var all: [(id: Int, name: String)] = []
        for r in need.sorted() { all += (try? await api.providerCatalog(r)) ?? [] }
        guard !all.isEmpty else { return }
        Providers.learn(all)
        Providers.learnedRegions = need
    }

    func reloadRecommendations() {
        guard let key = tmdbKey else { rows = []; return }
        loadToken += 1
        let token = loadToken
        let api = TMDB(key: key)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        let today = fmt.string(from: Date())
        let since = fmt.string(from: Date().addingTimeInterval(-90 * 86400))

        if rows.isEmpty { recoStatus = tr("Lade Empfehlungen …") }
        Task {
            await ensureProviders(api)
            let taste = self.taste
            let bases = discoverBases()
            let mg = taste.topGenres(in: Genre.movieIDs).map(String.init).joined(separator: "|")
            let tg = taste.topGenres(in: Genre.tvIDs).map(String.init).joined(separator: "|")
            // „Weil dir X gefallen hat“: gleiche Genres (UND), aber nur bei deinen Diensten.
            let lg = taste.lastLiked.map { $0.genres.prefix(2).map(String.init).joined(separator: ",") } ?? ""
            // Je Land eine Quelle (Konten in mehreren Ländern) – beim Laden reihum gemischt.
            let src = { (path: String, type: String, extra: [String: String]) in
                bases.map { RowSource(path: path, query: AppState.query($0, extra), type: type) }
            }
            let sFor = src("/discover/movie", "movie", ["with_genres": mg]) + src("/discover/tv", "tv", ["with_genres": tg])
            let sNew = src("/discover/movie", "movie", ["primary_release_date.gte": since, "primary_release_date.lte": today])
                + src("/discover/tv", "tv", ["first_air_date.gte": since, "first_air_date.lte": today])
            let sPop = src("/discover/movie", "movie", ["vote_count.gte": "200"]) + src("/discover/tv", "tv", ["vote_count.gte": "100"])
            let sBecause = taste.lastLiked.map { src("/discover/\($0.type)", $0.type, ["with_genres": lg]) } ?? []
            // „Mal was anderes“: sehr gut bewertet, aber NICHT aus deinen Lieblingsgenres; Seite zufällig,
            // damit die Reihe bei jedem Laden anders ist.
            let surprisePage = String(Int.random(in: 1...3))
            let sSurprise = src("/discover/movie", "movie", ["without_genres": mg.replacingOccurrences(of: "|", with: ","),
                                                             "vote_average.gte": "7.3", "vote_count.gte": "400"])
                + src("/discover/tv", "tv", ["without_genres": tg.replacingOccurrences(of: "|", with: ","),
                                             "vote_average.gte": "7.5", "vote_count.gte": "150"])
            /// Alle Quellen parallel laden, reihum mischen, Doppelte raus.
            @Sendable func fetchAll(_ list: [RowSource], extra: [String: String] = [:], required: Bool = true) async throws -> [Title] {
                let results = try await withThrowingTaskGroup(of: (Int, [Title]).self) { g in
                    for (i, s) in list.enumerated() {
                        g.addTask {
                            let q = s.query.merging(extra) { $1 }
                            if required { return (i, try await api.list(s.path, q, type: s.type)) }
                            return (i, (try? await api.list(s.path, q, type: s.type)) ?? [])
                        }
                    }
                    var out: [(Int, [Title])] = []
                    for try await r in g { out.append(r) }
                    return out.sorted { $0.0 < $1.0 }.map(\.1)
                }
                var seen = Set<String>()
                return results.reduce([]) { AppState.mix($0, $1) }.filter { seen.insert($0.key).inserted }
            }
            do {
                async let fy = fetchAll(sFor)
                async let nw = fetchAll(sNew)
                async let pp = fetchAll(sPop)
                async let sp = fetchAll(sSurprise, extra: ["page": surprisePage], required: false)
                let because = await self.similar(to: taste.lastLiked, api)
                let unseen = { (t: Title) in !taste.liked.contains(t.key) && !taste.disliked.contains(t.key) }
                let surprise = (try await sp).shuffled().filter(unseen)
                let forYouBase = taste.diversify(try await fy).filter(unseen)
                let forYou = Taste.sprinkle(forYouBase, Array(surprise.prefix(4)))
                let fresh = taste.diversify(try await nw)
                let popular = (try await pp).filter { !taste.disliked.contains($0.key) }
                let b = taste.diversify(because).filter { unseen($0) && $0.key != taste.lastLiked?.key }
                let surpriseRow = Array(surprise.dropFirst(4))

                var out: [PosterRow] = []
                if !forYou.isEmpty { out.append(PosterRow(id: "foryou", title: tr("Für dich"), items: forYou, sources: sFor)) }
                if !fresh.isEmpty { out.append(PosterRow(id: "new", title: tr("Neu bei deinen Diensten"), items: fresh, sources: sNew)) }
                if let l = taste.lastLiked, !b.isEmpty {
                    out.append(PosterRow(id: "because", title: tr("Weil dir „%@“ gefallen hat", l.name), items: b, sources: sBecause))
                }
                if surpriseRow.count >= 4 {
                    out.append(PosterRow(id: "surprise", title: tr("Mal was anderes – top bewertet"), items: surpriseRow, sources: sSurprise))
                }
                if !popular.isEmpty {
                    out.append(PosterRow(id: "popular", title: tr("Beliebt bei deinen Diensten"), items: popular, sources: sPop))
                }

                guard token == loadToken else { return }
                rows = withWatchlist(out)
                recoFailed = false
                recoStatus = out.isEmpty ? tr("Keine Treffer – wähle mehr Genres (RB) oder Dienste (X)") : nil
                clampPoster()
                fetchProviders()
            } catch {
                guard token == loadToken else { return }
                recoFailed = true
                if case TMDB.Failure.status(401) = error {
                    recoStatus = tr("TMDB-Schlüssel ungültig – A zum Ändern")
                } else {
                    recoStatus = tr("Empfehlungen nicht erreichbar – A für Schlüssel, später erneut")
                }
                clampPoster()
            }
        }
    }

    /// „Mehr wie dieser“: TMDB-Empfehlungen (aus dem Verhalten echter Zuschauer, nicht nur Genre),
    /// gefiltert auf Titel, die bei deinen Diensten laufen.
    func similar(to t: Title?, _ api: TMDB) async -> [Title] {
        guard let t else { return [] }
        let recs = (try? await api.list("/\(t.type)/\(t.id)/recommendations", [:], type: t.type)) ?? []
        let check = recs.prefix(20).filter { providerCache[$0.key] == nil }
        await withTaskGroup(of: (String, [String: [Int]]?).self) { g in
            for r in check { g.addTask { (r.key, try? await api.providers(r)) } }
            for await (k, ids) in g { if let ids { cacheProviders(k, ids) } }
        }
        let mine = Set(Providers.ids(for: enabledIDs))
        return recs.prefix(20).filter { !mine.isDisjoint(with: providerCache[$0.key] ?? []) }
    }

    nonisolated static func mix(_ a: [Title], _ b: [Title]) -> [Title] {
        var out: [Title] = []
        for i in 0..<max(a.count, b.count) {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
        }
        return out
    }

    func interleave(_ a: [Title], _ b: [Title]) -> [Title] {
        var out: [Title] = []
        for i in 0..<max(a.count, b.count) {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
        }
        return out
    }
}
