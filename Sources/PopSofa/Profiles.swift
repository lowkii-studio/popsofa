import SwiftUI

/// Ein Mensch auf der Couch: eigener Geschmack, eigene Merkliste, Profilnamen bei den Diensten.
struct Profile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var color: Int
    var taste = Taste()
    var watchlist: [Title] = []
    var streamNames: [String: String] = [:]   // Dienst-ID → Profilname dort (leer = PopSofa-Name)
    var vision: Double? = nil                   // Sehtest-Faktor für „Auto“ (nil = 1,0)
    var distance: Double? = nil                 // zuletzt gemessener Abstand zum TV in mm
    var testedAt: Double? = nil                 // Abstand beim Sehtest in mm (nur Info)
    var services: [String]? = nil               // Dienste dieses Profils (nil = bisherige übernehmen)
    // Darstellung & Barrierefreiheit pro Person (nil = bisherige übernehmen)
    var theme: String? = nil
    var colorVision: String? = nil
    var colorVisionSeverity: Double? = nil
    var clearContrast: String? = nil
    // Länder & Sprache: Heimatland, abweichende Konto-Länder je Dienst, Sprache der Beschreibungen
    var country: String? = nil
    var serviceCountries: [String: String]? = nil
    var language: String? = nil
    var multiCountry: Bool? = nil               // Dienste aus verschiedenen Ländern (Schalter)

    /// Sehtest: Größen der fünf Zeilen (relativ zur Lesegröße) und der Faktor bei dieser Wahl.
    static let eyeSizes: [CGFloat] = [0.85, 1.0, 1.2, 1.45, 1.75]
    static let eyeFactors: [Double] = [0.9, 1.0, 1.2, 1.45, 1.75]
    /// Beispiel-Beschreibungen – jede Zeile anders, damit man nicht vom Wiedererkennen liest.
    static var eyeSamples: [String] { [
        tr("Ein pensionierter Uhrmacher entdeckt in seinem Keller eine Tür, die es gestern noch nicht gab."),
        tr("Zwei Schwestern erben ein Strandhotel in Lissabon – und mit ihm ein Geheimnis aus den Siebzigern."),
        tr("Als der Strom in der ganzen Stadt ausfällt, muss eine Nachtschicht im Zoo improvisieren."),
        tr("Ein junger Koch will das Restaurant seiner Familie retten und kocht gegen die Zeit."),
        tr("Eine Astronautin kehrt zur Erde zurück und findet ihre Heimat völlig verändert vor."),
    ] }

    static let colors = ["#FF5DA2", "#FFD23F", "#2EC4B6", "#5C7AEA", "#E07A3F", "#58A55C", "#B98CFF"]
    var hex: String { Self.colors[color % Self.colors.count] }
    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }

    func streamName(_ service: String) -> String {
        let n = (streamNames[service] ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? name : n
    }

    /// Profile laden; beim ersten Mal werden die bisherigen Daten (taste/watchlist) zum Profil „Ich“.
    static func load(_ d: UserDefaults) -> (profiles: [Profile], active: UUID) {
        if let data = d.data(forKey: "profiles"),
           let list = try? JSONDecoder().decode([Profile].self, from: data), let first = list.first {
            let active = d.string(forKey: "activeProfile").flatMap(UUID.init(uuidString:))
            return (list, list.contains { $0.id == active } ? active! : first.id)
        }
        var me = Profile(name: "Ich", color: 0)
        if let data = d.data(forKey: "taste"), let t = try? JSONDecoder().decode(Taste.self, from: data) { me.taste = t }
        if let data = d.data(forKey: "watchlist"), let w = try? JSONDecoder().decode([Title].self, from: data) { me.watchlist = w }
        return ([me], me.id)
    }

    static func save(_ list: [Profile], active: UUID, _ d: UserDefaults) {
        if let data = try? JSONEncoder().encode(list) { d.set(data, forKey: "profiles") }
        d.set(active.uuidString, forKey: "activeProfile")
    }

    static func selfTest() {
        let d = UserDefaults(suiteName: "popsofa.selftest.\(UUID().uuidString)")!
        var t = Taste(); t.liked = ["movie-1"]
        d.set(try! JSONEncoder().encode(t), forKey: "taste")
        let (list, active) = load(d)
        precondition(list.count == 1 && list[0].name == "Ich" && list[0].taste.liked == ["movie-1"] && active == list[0].id)
        let kid = Profile(name: "Kinder", color: 1)
        save(list + [kid], active: kid.id, d)
        let (again, act2) = load(d)
        precondition(again.count == 2 && act2 == kid.id && again[0].taste.liked == ["movie-1"])
        precondition(Profile(name: "Alex", color: 0, streamNames: ["netflix": " "]).streamName("netflix") == "Alex")
        var dani = Profile(name: "Dani", color: 2); dani.theme = "clearLight"; dani.colorVision = "deutan"; dani.clearContrast = "soft"
        save([dani], active: dani.id, d)
        let back = load(d).profiles[0]
        precondition(back.theme == "clearLight" && back.colorVision == "deutan" && back.clearContrast == "soft", "Darstellung pro Profil")
        print("✓ Profile")
    }
}

// MARK: - „Wer schaut?“

extension AppState {
    var activeProfile: Profile? { profiles.first { $0.id == activeProfileID } }

    func openProfilePicker() {
        profileFocus = profiles.firstIndex { $0.id == activeProfileID } ?? 0
        profilePicker = true
    }

    func handleProfiles(_ e: PadEvent) {
        // Beim Start gibt es nichts, wohin man zurück könnte – erst ein Profil wählen.
        if profileRequired && (e == .up || e == .b) { return }
        if handleBack(e, close: { profilePicker = false }) { return }
        let n = profiles.count + 1   // + „Profil hinzufügen“
        switch e {
        case .up: backFocus = true
        case .left: profileFocus = max(profileFocus - 1, 0)
        case .right: profileFocus = min(profileFocus + 1, n - 1)
        case .a: chooseProfile(profileFocus)
        case .x: if profileFocus < profiles.count { editProfile(profiles[profileFocus].id) }
        case .b: profilePicker = false
        default: break
        }
    }

    func chooseProfile(_ i: Int) {
        if i < profiles.count { switchProfile(profiles[i].id) } else { editProfile(nil) }
    }

    func editProfile(_ id: UUID?) {
        editingProfile = id
        sheet = .profile
    }

    /// Speichert das bearbeitete bzw. neue Profil (aus dem Sheet).
    /// Speichert das bearbeitete bzw. neue Profil. Neu: weiter mit Sehtest und Genres (Einrichtung).
    func saveProfile(name: String, streamNames: [String: String], then next: Sheet? = nil) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { showToast(tr("Bitte einen Namen eingeben")); return }
        if let id = editingProfile, let i = profiles.firstIndex(where: { $0.id == id }) {
            profiles[i].name = n
            profiles[i].streamNames = streamNames
            persist()
            editingField = nil
            sheet = next
        } else {
            let p = Profile(name: n, color: profiles.count, streamNames: streamNames)
            profiles.append(p)
            switchProfile(p.id)
            editingProfile = p.id
            setupFlow = true
            editingField = nil
            formFocus = 0
            sheet = .services
        }
    }

    /// Sehtest-Wahl übernehmen: Faktor ins aktive Profil, Schrift neu berechnen.
    func chooseVision(_ i: Int) {
        guard let idx = profiles.firstIndex(where: { $0.id == activeProfileID }),
              Profile.eyeFactors.indices.contains(i) else { return }
        profiles[idx].vision = Profile.eyeFactors[i]
        profiles[idx].testedAt = Double(currentDistance)
        persist()
        updateScale()
        let pct = Int(((Profile.eyeFactors[i] - 1) * 100).rounded())
        showToast(pct == 0 ? tr("Textgröße passt so") : tr("Text für %@ %@", profiles[idx].name, "\(pct > 0 ? "+" : "")\(pct) %"))
        if setupFlow { startPrismTest() } else { sheet = nil }   // Einrichtung: danach Prismen-Check und Farbtest
    }

    func handleEyeTest(_ e: PadEvent) {
        if handleBack(e, close: { sheet = nil }) { return }
        let n = Profile.eyeSizes.count
        switch e {
        case .up: if formFocus == 0 { backFocus = true } else { formFocus -= 1 }
        case .down: formFocus = min(formFocus + 1, n - 1)
        case .a: chooseVision(formFocus)
        case .b: if setupFlow { startPrismTest() } else { sheet = nil }   // „Später“: Einrichtung geht weiter
        default: break
        }
    }

    func deleteProfile(_ id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        sheet = nil
        profileFocus = 0
        if id == activeProfileID { switchProfile(profiles[0].id, keepPicker: true) } else { persist() }
    }
}

/// Runder Profil-Knopf in der Kopfzeile.
struct ProfileButton: View {
    @EnvironmentObject var state: AppState
    let focused: Bool
    let action: () -> Void

    var body: some View {
        let p = state.activeProfile
        HeaderButton(focused: focused, active: state.profilePicker, help: tr("Profil: %@", p?.name ?? ""), action: action) {
            Text(p?.initial ?? "?")
                .font(.ui(20, weight: .heavy, design: .rounded))
                .foregroundColor(Pop.textOn(p?.hex ?? "#888888"))
                .frame(width: 40 * Metrics.s, height: 40 * Metrics.s)
                .background(Circle().fill(Color(hex: p?.hex ?? "#888888")))
        }
    }
}

struct ProfilePicker: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()
            ThemedBackground().opacity(0.98).ignoresSafeArea()
            VStack(spacing: 32 * Metrics.s) {
                HStack {
                    if !state.profileRequired { BackButton(focused: state.backFocus) { state.profilePicker = false } }
                    Spacer()
                }
                .frame(minHeight: 44 * Metrics.text(18))   // gleiche Höhe mit und ohne Knopf
                .padding(.top, 36)
                Spacer()
                Text(tr("Wer schaut?")).headingFont(46).popTextShadow()
                HStack(alignment: .top, spacing: 24 * Metrics.s) {
                    ForEach(Array(state.profiles.enumerated()), id: \.element.id) { i, p in
                        avatar(i, hex: p.hex, name: p.name) {
                            Text(p.initial).font(.ui(64, weight: .heavy, design: .rounded))
                                .foregroundColor(Pop.textOn(p.hex))
                        }
                        .contextMenu {
                            Button(tr("Bearbeiten")) { state.editProfile(p.id) }
                        }
                    }
                    // Helle Stile: dunkler Kreis mit hellem Plus (sonst dunkles Plus auf dunklem Comic-Schatten).
                    avatar(state.profiles.count, hex: Ink.light ? Pop.inkHexLight : nil, name: tr("Profil hinzufügen")) {
                        Image(systemName: "plus").font(.ui(54, weight: .bold))
                            .foregroundColor(Ink.light ? Color(hex: "#F3E8D6") : Ink.fg)
                    }
                }
                Spacer()
                FlowLayout(spacing: 22, lineSpacing: 8) {
                    if state.inputMode == .keyboard {
                        KeyboardHints()
                    } else {
                        Hint(glyph: .letter("A", .green), text: state.backFocus ? tr("Zurück") : tr("Auswählen"))
                        if !state.backFocus && state.profileFocus < state.profiles.count {
                            Hint(glyph: .letter("X", .blue), text: tr("Bearbeiten"))
                        }
                        if !state.profileRequired { Hint(glyph: .letter("B", .red), text: tr("Schließen")) }
                    }
                }
                .font(.read(15, weight: .medium))
                .dimText(0.75)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, Metrics.side)
        }
    }

    private func avatar<C: View>(_ i: Int, hex: String?, name: String, @ViewBuilder content: () -> C) -> some View {
        let focused = !state.backFocus && state.profileFocus == i
        let size = 140 * (1 + (Metrics.m - 1) * 0.3)   // Kreis wächst kaum – der Name darunter schon
        return VStack(spacing: 16) {
            content()
                .frame(width: size, height: size)
                .background(Circle().fill(hex.map { Color(hex: $0) } ?? Ink.fg.opacity(0.12)))
                .overlay(Circle().strokeBorder(focused ? (theme.bold ? Ink.bg : Ink.fg) : .clear,
                                               lineWidth: theme.bold ? 6 : 4))
                .background(Circle().fill(Ink.bg).offset(x: 7, y: 7).opacity(theme.bold ? 1 : 0))
            Text(name)
                .font(.ui(22, weight: .semibold))
                .foregroundColor(Ink.fg)
                .opacity(focused ? 1 : 0.7)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: max(size + 40, 170 * Metrics.text(22)))   // Name wächst stärker als der Kreis
            // Maus/Tastatur: Bearbeiten sichtbar (am Controller X)
            if state.inputMode == .keyboard, i < state.profiles.count {
                Button { state.profileFocus = i; state.editProfile(state.profiles[i].id) } label: {
                    Label(tr("Bearbeiten"), systemImage: "pencil").font(.ui(15, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Ink.fg.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .foregroundColor(Ink.fg)
            }
        }
        .scaleEffect(focused && !Typo.calm ? 1.1 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: focused)
        .onTapGesture { state.profileFocus = i; state.chooseProfile(i) }
    }
}

/// Mini-Sehtest: fünf Zeilen in steigender Größe – die kleinste bequem lesbare bestimmt den Faktor.
struct EyeTestPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        // Ohne bisherigen Sehtest-Faktor zeigen, sonst misst man doppelt.
        // Sehtest-Faktor rausrechnen (gilt nur bei „Auto“), sonst misst man doppelt.
        let current = CGFloat(state.textSize == .auto ? state.activeProfile?.vision ?? 1 : 1)
        OverlayPage(title: tr("Kurzer Sehtest"),
                    step: state.setupFlow ? tr("Schritt %@ von %@", 3, 6) : nil,
                    intro: tr("Bleib dort sitzen, wo du sonst schaust. Die Zeilen sind Filmbeschreibungen – die kleinste Schrift in PopSofa. Welche ist die kleinste Zeile, die du bequem lesen kannst?"),
                    close: { state.sheet = nil },
                    hints: state.backFocus ? [("A", tr("Zurück"))] : [("dpad", tr("Zeile wählen")), ("A", tr("Diese Zeile")), ("B", tr("Später"))]) {
            VStack(alignment: .leading, spacing: 10 * Metrics.s) {
                ForEach(Array(Profile.eyeSizes.enumerated()), id: \.offset) { i, f in
                    let on = !state.backFocus && state.formFocus == i
                    HStack(spacing: 18) {
                        Text("\(i + 1)").font(.ui(16, weight: .heavy)).frame(width: 30).opacity(0.8)
                        // Genau wie die Filmbeschreibung (kleinste Schrift der App): gleiche Größe, Stärke, Helligkeit.
                        Text(Profile.eyeSamples[i])
                            .font(.read(15 * f / current))
                            .dimText(0.6)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    // Gewählte Zeile nur mit Rahmen markieren: dunkler Grund wie bei der echten Beschreibung,
                    // sonst wäre der Test heller als die App (und im Pop-Stil Weiß auf Papier).
                    .foregroundColor(Ink.fg)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Ink.bg.opacity(on ? 0.45 : 0.2)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: theme.bold ? 4 : 3).opacity(on ? 1 : 0))
                    .frame(maxWidth: 1100 * Metrics.s, alignment: .leading)
                    .onTapGesture { state.formFocus = i; state.chooseVision(i) }
                }
            }
        }
        .onAppear { state.formFocus = 1 }
    }
}

/// Genre-Auswahl als Seite im Stil der App (Schritt 3 der Einrichtung).
struct GenrePage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        let done = Genre.all.count
        OverlayPage(title: tr("Was schaust du gern?"),
                    step: state.setupFlow ? tr("Schritt %@ von %@", 6, 6) : nil,
                    intro: tr("Wähle ein paar Genres. Später lernt PopSofa durch 👍 und 👎 auf den Postern dazu."),
                    close: { state.sheet = nil },
                    hints: state.backFocus ? [("A", tr("Zurück"))]
                        : [("dpad", tr("Auswahl")), ("A", state.genreFocus == done ? tr("Fertig") : tr("An/Aus")), ("X", tr("TMDB-Schlüssel")), ("B", tr("Fertig"))]) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: AppState.genreColumns), spacing: 16) {
                ForEach(Array(Genre.all.enumerated()), id: \.element.id) { i, g in
                    let picked = state.taste.isPicked(g)
                    let on = !state.backFocus && i == state.genreFocus
                    HStack {
                        Text(tr(g.name)).font(.read(19, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer()
                        Image(systemName: picked ? "checkmark.circle.fill" : "circle").font(.ui(22))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8).frame(minHeight: 60 * Metrics.s)
                    .foregroundColor(picked && theme.bold ? Ink.bg : Ink.fg)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(picked ? (theme.bold ? theme.p.accent : Color(hex: "#2E7D32")) : Ink.fg.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.bold ? Ink.bg : .clear, lineWidth: 2))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: 3).padding(-6).opacity(on ? 1 : 0))
                    .scaleEffect(on && !Typo.calm ? 1.04 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: on)
                    .onTapGesture { state.genreFocus = i; state.toggleGenre(g) }
                    .accessibilityLabel("\(tr(g.name)), \(tr(picked ? "ausgewählt" : "nicht ausgewählt"))")
                }
            }
            .frame(maxWidth: 1300 * Metrics.s)
            let on = !state.backFocus && state.genreFocus == done
            Button { state.sheet = nil } label: {
                Text(tr("Fertig")).font(.read(18, weight: .bold))
                    .padding(.horizontal, 30).padding(.vertical, 13)
                    .foregroundColor(Ink.bg)
                    .background(Capsule().fill(theme.bold ? theme.p.accent : Ink.fg))
                    .overlay(Capsule().strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: 3).padding(-6).opacity(on ? 1 : 0))
                    .scaleEffect(on && !Typo.calm ? 1.08 : 1)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Abstand messen: kurze Leiste oben an der Kamera, Auswahl nur, wenn das scheitert

enum DistanceStep: Equatable {
    case counting(Int)          // 3 … 1
    case result(CGFloat)        // gemessen, in mm
    case failed
}

extension AppState {
    /// Laptop: 0,4–1,5 m, Fernseher/Monitor: 1–4 m.
    static var distanceChoices: [CGFloat] {
        TextSize.screenInfo.builtIn ? [400, 500, 650, 800, 1000, 1500] : [1000, 1500, 2000, 2500, 3000, 3500, 4000]
    }

    /// Abstand, mit dem gerade gerechnet wird. Am Fernseher sitzt jedes Profil woanders – dort zählt der des Profils.
    var currentDistance: CGFloat {
        let i = TextSize.screenInfo
        return (!i.builtIn ? activeProfile?.distance.map { CGFloat($0) } : nil)
            ?? TextSize.distance(builtIn: i.builtIn, mmPerPoint: i.mmPerPoint, widthPt: i.widthPt)
    }

    /// Misst automatisch (Leiste mit Countdown). Scheitert es: mit `fallback` gleich die Auswahl,
    /// sonst bietet die Leiste kurz „A = Abstand wählen“ an.
    func measureDistance(fallback: Bool = false) {
        guard DistanceCamera.available else {
            if fallback { openDistanceChoices() }
            return
        }
        distanceRun += 1
        let run = distanceRun
        faceSeen = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { distanceBanner = .counting(3) }
        for n in [2, 1] {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(3 - n)) { [weak self] in
                guard let self, self.distanceRun == run, case .counting = self.distanceBanner else { return }
                self.distanceBanner = .counting(n)
            }
        }
        DistanceCamera.measure(seconds: 3, onFace: { [weak self] seen in
            if self?.distanceRun == run { self?.faceSeen = seen }
        }) { [weak self] mm in
            guard let self, self.distanceRun == run else { return }
            if let mm {
                self.saveDistance(mm)
                self.distanceBanner = .result(mm)
                self.hideBanner(after: 2.5, run: run)
            } else if fallback {
                withAnimation { self.distanceBanner = nil }
                self.openDistanceChoices()
            } else {
                self.distanceBanner = .failed
                self.distancePromptUntil = Date().addingTimeInterval(6)
                self.hideBanner(after: 6, run: run)
            }
        }
    }

    private func hideBanner(after s: Double, run: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { [weak self] in
            guard let self, self.distanceRun == run else { return }
            withAnimation(.easeIn(duration: 0.3)) { self.distanceBanner = nil }
        }
    }

    /// Nach jeder Profilwahl (und beim Start mit nur einem Profil), sobald eine Kamera da ist.
    /// Testläufe (`--press`) messen nicht – sie würden den echten Abstand überschreiben.
    func offerDistance() {
        guard sheet == nil, !Debug.on else { return }
        measureDistance()
    }

    /// Abstand merken: am TV pro Profil, sonst pro Bildschirm; Schrift sofort anpassen.
    func saveDistance(_ mm: CGFloat) {
        let builtIn = TextSize.screenInfo.builtIn
        UserDefaults.standard.set(Double(mm), forKey: TextSize.distanceKey(builtIn: builtIn))
        if !builtIn, let i = profiles.firstIndex(where: { $0.id == activeProfileID }) {
            profiles[i].distance = Double(mm)
            persist()
        }
        updateScale()
    }

    /// Ersatz, wenn die Kamera scheitert: Auswahl 1,5–4 m, danach zurück, wo man war (z. B. Sehtest).
    func openDistanceChoices() {
        distanceRun += 1
        withAnimation { distanceBanner = nil }
        afterDistance = sheet == .distance ? afterDistance : sheet
        let d = currentDistance
        formFocus = Self.distanceChoices.indices.min { abs(Self.distanceChoices[$0] - d) < abs(Self.distanceChoices[$1] - d) } ?? 2
        backFocus = false
        sheet = .distance
    }

    func chooseDistance(_ mm: CGFloat) {
        saveDistance(mm)
        sheet = afterDistance
        showToast(String(format: tr("Abstand %.1f m"), mm / 1000).replacingOccurrences(of: ".", with: ","))
    }

    func closeDistance() { sheet = afterDistance }

    func handleDistance(_ e: PadEvent) {
        if handleBack(e, close: { closeDistance() }) { return }
        let n = Self.distanceChoices.count
        switch e {
        case .up: backFocus = true
        case .left: formFocus = max(formFocus - 1, 0)
        case .right: formFocus = min(formFocus + 1, DistanceCamera.available ? n : n - 1)   // n = „Nochmal mit Kamera“
        case .a:
            if formFocus < n { chooseDistance(Self.distanceChoices[formFocus]) }
            else { closeDistance(); measureDistance() }
        case .b: closeDistance()
        default: break
        }
    }
}

/// Kurze Leiste, die oben mittig – nahe der Kamera – herunterfährt: Countdown, Ergebnis oder Hinweis.
struct DistanceBanner: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme
    let step: DistanceStep

    var body: some View {
        HStack(spacing: 16 * Metrics.s) {
            switch step {
            case .counting(let n):
                Text("\(n)")
                    .font(.ui(34, weight: .heavy, design: .rounded))
                    .frame(width: 54 * Metrics.s, height: 54 * Metrics.s)
                    .background(Circle().fill(theme.bold ? theme.p.accent : Ink.fg))
                    .foregroundColor(Ink.bg)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: n)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Abstand wird gemessen")).font(.read(19, weight: .bold))
                    Label(state.faceSeen ? tr("Gesicht erkannt") : tr("Kurz hierher schauen"),
                          systemImage: state.faceSeen ? "checkmark.circle.fill" : "camera.fill")
                        .font(.read(16, weight: .semibold))
                        .foregroundColor(state.faceSeen ? Color(hex: "#7CDB84") : Ink.fg.opacity(0.85))
                }
            case .result(let mm):
                Image(systemName: "checkmark.circle.fill").font(.ui(34)).foregroundColor(Color(hex: "#7CDB84"))
                Text(String(format: "%.1f m – %@", mm / 1000, state.textSize == .auto ? tr("Schrift angepasst") : tr("Abstand gespeichert"))
                    .replacingOccurrences(of: ".", with: ","))
                    .font(.read(19, weight: .bold))
            case .failed:
                Image(systemName: "camera.metering.unknown").font(.ui(30))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Kein Gesicht erkannt")).font(.read(19, weight: .bold))
                    Text(state.inputMode == .controller ? tr("A = Abstand selbst wählen") : tr("Klicken, um den Abstand zu wählen"))
                        .font(.read(16, weight: .semibold)).opacity(0.85)
                }
            }
        }
        .foregroundColor(Ink.fg)
        .padding(.horizontal, 26 * Metrics.s).padding(.vertical, 14 * Metrics.s)
        .background(Capsule().fill(Ink.bg.opacity(0.85)))
        .overlay(Capsule().strokeBorder(theme.bold ? theme.p.accent : Ink.fg.opacity(0.25), lineWidth: theme.bold ? 3 : 1))
        .shadow(color: Ink.bg.opacity(0.4), radius: 16, y: 6)
        .onTapGesture { if step == .failed { state.openDistanceChoices() } }
        .accessibilityElement(children: .combine)
    }
}

/// Nur wenn die Kamera scheitert oder fehlt: Abstand selbst wählen.
struct DistancePage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        let n = AppState.distanceChoices.count
        OverlayPage(title: tr("Wie weit sitzt du weg?"),
                    intro: DistanceCamera.available
                        ? tr("Die Kamera hat dich nicht erkannt. Wähle ungefähr, wie weit du vom Bildschirm sitzt.")
                        : tr("Keine Kamera gefunden (z. B. MacBook zugeklappt). Wähle ungefähr, wie weit du vom Bildschirm sitzt."),
                    close: { state.closeDistance() },
                    hints: state.backFocus ? [("A", tr("Zurück"))] : [("dpad", tr("Auswahl")), ("A", "OK"), ("B", tr("Abbrechen"))]) {
            // Bricht bei großer Schrift in mehrere Zeilen um, statt Knöpfe zu quetschen.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150 * Metrics.text(20)), spacing: 16, alignment: .leading)],
                      alignment: .leading, spacing: 16) {
                ForEach(Array(AppState.distanceChoices.enumerated()), id: \.offset) { i, mm in
                    pill(mm < 1000 ? "\(Int(mm / 10)) cm" : String(format: "%.1f m", mm / 1000).replacingOccurrences(of: ".", with: ","), i) { state.chooseDistance(mm) }
                }
                if DistanceCamera.available {
                    pill(tr("Nochmal mit Kamera"), n) { state.closeDistance(); state.measureDistance() }
                }
            }
            .padding(.top, 20 * Metrics.s)
        }
    }

    private func pill(_ text: String, _ i: Int, action: @escaping () -> Void) -> some View {
        let on = !state.backFocus && state.formFocus == i
        return Button(action: action) {
            Text(text).font(.read(20, weight: .bold)).lineLimit(1).fixedSize()
                .padding(.horizontal, 26).padding(.vertical, 14)
                .foregroundColor(on ? Ink.bg : Ink.fg)
                .background(Capsule().fill(on ? (theme.bold ? theme.p.accent : Ink.fg) : Ink.fg.opacity(0.12)))
                .overlay(Capsule().strokeBorder(theme.bold ? Ink.bg : Ink.fg.opacity(0.3), lineWidth: 2))
                .overlay(Capsule().strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: 3).padding(-6).opacity(on ? 1 : 0))
                .scaleEffect(on && !Typo.calm ? 1.08 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: on)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Welche Dienste nutzt du? (Einrichtung Schritt 2, später über „Profil bearbeiten“)

extension AppState {
    static let serviceColumns = 4

    func finishServicePicks() {
        resetAvailability()
        persist()
        reloadRecommendations()
        clampFocus()
        if setupFlow {
            sheet = .eyeTest
            measureDistance(fallback: true)   // Sehtest stimmt nur mit echtem Abstand
        } else {
            sheet = nil
        }
    }

    func handleServicePicks(_ e: PadEvent) {
        if handleBack(e, close: { finishServicePicks() }) { return }
        let list = allServices, n = list.count, c = Self.serviceColumns
        if formFocus == n {   // Schalter „Dienste aus verschiedenen Ländern“ – oben, neben dem Streaming-Land
            switch e {
            case .up: backFocus = true
            case .down: formFocus = 0
            case .a: toggleMultiCountry()
            case .y: chooseCountry()
            case .rb: chooseLanguage()
            case .b: finishServicePicks()
            default: break
            }
            return
        }
        if formFocus > n {    // „Weiter“ unter dem Raster
            switch e {
            case .up: formFocus = n - 1
            case .a, .b: finishServicePicks()
            default: break
            }
            return
        }
        switch e {
        case .left: formFocus = max(formFocus - 1, 0)
        case .right: formFocus = min(formFocus + 1, n - 1)
        case .up: if formFocus - c >= 0 { formFocus -= c } else { formFocus = n }
        case .down: formFocus = formFocus + c < n ? formFocus + c : n + 1
        case .a: toggleServicePick(list[formFocus])
        case .x: if multiCountry { chooseServiceCountry(list[formFocus]) }
        case .y: if !multiCountry { chooseCountry() }
        case .rb: chooseLanguage()
        case .b: finishServicePicks()
        default: break
        }
    }

    /// Die meisten haben alle Abos in einem Land – Länder pro Dienst nur auf Wunsch. Aus = alle wieder im Streaming-Land.
    func toggleMultiCountry() {
        multiCountry.toggle()
        serviceCountries = [:]   // an: jeder Dienst startet im bisherigen Streaming-Land; aus: alle wieder dort
        persist()
    }

    /// Nur merken – Empfehlungen werden erst beim Verlassen neu geladen.
    func toggleServicePick(_ s: Service) {
        if enabledIDs.contains(s.id) { enabledIDs.remove(s.id) } else { enabledIDs.insert(s.id) }
    }
}

/// Dienste-Auswahl im Stil der Genre-Seite: Kacheln in Dienstfarbe, Häkchen = nutze ich.
struct ServicePickPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        let list = state.allServices, toggle = list.count, done = list.count + 1
        OverlayPage(title: tr("Welche Dienste nutzt du?"),
                    step: state.setupFlow ? tr("Schritt %@ von %@", 2, 6) : nil,
                    intro: tr("Nur diese erscheinen auf deinem Startbildschirm, und Vorschläge kommen nur von dort."),
                    close: { state.finishServicePicks() },
                    hints: state.backFocus ? [("A", tr("Zurück"))]
                        : [("dpad", tr("Auswahl")), ("A", state.formFocus == done ? tr("Weiter") : tr("An/Aus"))]
                          + (state.multiCountry ? [("X", tr("Land des Kontos"))] : [])
                          + (state.multiCountry ? [] : [("Y", tr("Streaming-Land"))]) + [("RB", tr("Sprache")), ("B", tr("Weiter"))]) {
            // Wo die Abos laufen: ein Land für alle – oder (Schalter an) ein Land pro Dienst an den Kacheln.
            VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 14, lineSpacing: 10, centered: false) {
                    multiCountrySwitch(focused: !state.backFocus && state.formFocus == toggle)
                    if !state.multiCountry {
                        settingChip(tr("Streaming-Land: %@", "\(Region.flag(state.country)) \(Region.name(state.country))") + "  ›", key: "Y") { state.chooseCountry() }
                    }
                    settingChip(tr("Sprache: %@", Region.languageName(state.contentLanguage)) + "  ›", key: "RB") { state.chooseLanguage() }
                }
                Text(tr(state.multiCountry ? "Z. B. HBO Max aus Portugal, Prime aus Deutschland" : "Wo deine Abos laufen – gilt für alle Dienste."))
                    .font(.read(15)).dimText(0.8)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: AppState.serviceColumns), spacing: 16) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, s in tile(i, s) }
            }
            .frame(maxWidth: 1300 * Metrics.s)
            let on = !state.backFocus && state.formFocus == done
            Button { state.finishServicePicks() } label: {
                Text(state.setupFlow ? tr("Weiter") : tr("Fertig")).font(.read(18, weight: .bold))
                    .padding(.horizontal, 30).padding(.vertical, 13)
                    .foregroundColor(Ink.bg)
                    .background(Capsule().fill(theme.bold ? theme.p.accent : Ink.fg))
                    .overlay(Capsule().strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: 3).padding(-6).opacity(on ? 1 : 0))
                    .scaleEffect(on && !Typo.calm ? 1.08 : 1)
            }
            .buttonStyle(.plain)
        }
    }

    /// Schalter (an/aus) – zwei Zustände, daher kein Auswahlfeld nötig.
    private func multiCountrySwitch(focused: Bool) -> some View {
        HStack(spacing: 12) {
            Text(tr("Dienste aus verschiedenen Ländern")).font(.read(17, weight: .semibold))
            Toggle("", isOn: Binding(get: { state.multiCountry }, set: { _ in state.toggleMultiCountry() }))
                .toggleStyle(.switch).labelsHidden().allowsHitTesting(false)   // Zeile selbst schaltet
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(Ink.fg.opacity(focused ? 0.18 : 0.1)))
        .overlay(Capsule()
            .strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: 3).padding(-5).opacity(focused ? 1 : 0))
        .contentShape(Rectangle())
        .onTapGesture { state.formFocus = state.allServices.count; state.toggleMultiCountry() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(state.multiCountry ? tr("An") : tr("Aus"))
    }

    private func settingChip(_ text: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text).font(.read(17, weight: .semibold))
                Text(key).font(.read(12, weight: .heavy)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Ink.fg.opacity(0.15)))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Ink.fg.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func tile(_ i: Int, _ s: Service) -> some View {
        let picked = state.enabledIDs.contains(s.id)
        let on = !state.backFocus && i == state.formFocus
        let hex = theme.bold ? theme.p.tone(for: s) : s.colorTop
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let abroad = state.region(s.id) != state.country
        return HStack(spacing: 8) {
            Text(s.name).font(.read(19, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if picked && state.multiCountry {
                // Land des Kontos: anklickbar, am Controller X
                Text("\(Region.flag(state.region(s.id))) \(state.region(s.id))")
                    .font(.read(15, weight: abroad ? .heavy : .medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(abroad ? 0.3 : 0.12)))
                    .onTapGesture { state.formFocus = i; state.chooseServiceCountry(s) }
                    .accessibilityLabel(tr("Konto aus %@", Region.name(state.region(s.id))))
            }
            Image(systemName: picked ? "checkmark.circle.fill" : "circle").font(.ui(22))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8).frame(minHeight: 64 * Metrics.s)
        // Schriftfarbe nach Kontrast zur Kachelfarbe (schwarz auf hell, weiß auf dunkel)
        .foregroundColor(picked ? Pop.textOn(hex) : .white)
        .background(shape.fill(picked ? Color(hex: hex) : Ink.fg.opacity(0.08)))
        .overlay(shape.strokeBorder(theme.bold ? Ink.bg : Color.clear, lineWidth: 2))
        .overlay(shape.strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: 3).padding(-6).opacity(on ? 1 : 0))
        .opacity(picked ? 1 : 0.75)
        .scaleEffect(on && !Typo.calm ? 1.04 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: on)
        .onTapGesture { state.formFocus = i; state.toggleServicePick(s) }
        .accessibilityLabel("\(s.name), \(tr(picked ? "ausgewählt" : "nicht ausgewählt"))")
    }
}
