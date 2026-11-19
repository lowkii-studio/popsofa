import SwiftUI

struct LauncherView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AmbientBackground(service: state.posterRow == nil ? state.focusedService : nil,
                                  backdrop: state.focusedTitle?.backdropURL)

                VStack(spacing: 0) {
                    HeaderBar()
                        .padding(.horizontal, Metrics.side)
                        .padding(.top, 30)

                    FocusScroll(axis: .vertical, target: homeTarget, position: 0.38, space: "home",
                                wheel: !state.searchOpen && state.detail == nil && state.webURL == nil && state.category == nil
                                    && state.sheet == nil && !state.profilePicker) {
                          VStack(spacing: 0) {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.fixed(state.tileWidth), spacing: Metrics.gap),
                                               count: state.columns),
                                spacing: Metrics.gap + 22
                            ) {
                                ForEach(Array(state.items.enumerated()), id: \.element.id) { idx, tile in
                                    TileView(tile: tile,
                                             focused: state.posterRow == nil && state.headerFocus == nil && idx == state.focusedIndex,
                                             editMode: state.editMode,
                                             enabled: isEnabled(tile))
                                        .scrollAnchor(tile.id, in: "home")
                                        .onTapGesture {
                                            state.headerFocus = nil
                                            state.focusedIndex = idx
                                            state.activate()
                                        }
                                        .modifier(ServiceDrag(tile: tile, index: idx))
                                }
                            }
                            .padding(.vertical, 44)
                            .frame(maxWidth: .infinity)

                            if !state.editMode && state.hasPosterSection {
                                PosterSection()
                                    .padding(.bottom, 30)
                            }
                          }
                          .frame(maxWidth: .infinity)
                    }

                    if let t = state.focusedTitle { TitleDetail(title: t).padding(.horizontal, Metrics.side) }

                    FooterBar()
                        .padding(.horizontal, Metrics.side)
                        .padding(.bottom, 24)
                }
                // Nie breiter/höher als der Bildschirm – sonst schiebt die Fußzeile die Uhr aus dem Bild.
                .frame(width: geo.size.width, height: geo.size.height)

                if state.searchOpen {
                    SearchOverlay().frame(width: geo.size.width, height: geo.size.height).transition(.opacity)
                }

                if state.textMenu {
                    TextSizeMenu()
                        .padding(.top, 100 * Metrics.s)
                        .padding(.trailing, Metrics.side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .background(Ink.bg.opacity(0.35).onTapGesture { state.textMenu = false })
                        .transition(.opacity)
                }

                if state.themeMenu {
                    ThemeMenu()
                        .padding(.top, 100 * Metrics.s)
                        .padding(.leading, Metrics.side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Ink.bg.opacity(0.35).onTapGesture { state.themeMenu = false })
                        .transition(.opacity)
                }

                if state.oursOpen {
                    OursOverlay().frame(width: geo.size.width, height: geo.size.height).transition(.opacity)
                }

                if state.category != nil {
                    CategoryOverlay().frame(width: geo.size.width, height: geo.size.height).transition(.opacity)
                }

                if state.profilePicker {
                    ProfilePicker().frame(width: geo.size.width, height: geo.size.height).transition(.opacity)
                }

                // Einstellungs-Seiten (Profil, Sehtest, Genres, Dienst, Schlüssel, iPhone) – ganzseitig statt Dialog.
                if let s = state.sheet {
                    SheetPage(sheet: s).frame(width: geo.size.width, height: geo.size.height).clipped().transition(.opacity).zIndex(5)
                }

                if let c = state.choice {
                    ChoiceOverlay(prompt: c).frame(width: geo.size.width, height: geo.size.height).zIndex(7)
                }

                if let t = state.detail {
                    DetailOverlay(title: t).frame(width: geo.size.width, height: geo.size.height).transition(.opacity)
                }

                if let url = state.webURL {
                    // Leiste über der Seite statt darüber gelegt – verdeckt nie Knöpfe der Webseite.
                    VStack(spacing: 0) {
                        if state.webBarVisible {
                            WebBar(host: url.host ?? "")
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        WebBrowserView(url: url).id(url)
                    }
                    .background(Ink.bg)
                    .ignoresSafeArea()
                    .transition(.opacity)
                }

                // Abstandsmessung: kurze Leiste oben mittig, nahe der Kamera.
                if let b = state.distanceBanner, !state.splash {
                    DistanceBanner(step: b)
                        .padding(.top, 18 * Metrics.s)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(8)
                }

                if state.splash {
                    SplashView().transition(.opacity).zIndex(10)
                }

                if let toast = state.toast {
                    VStack {
                        Spacer()
                        Group {
                            if state.theme.bold {
                                // Sprechblase im Comic-Stil
                                Text(toast)
                                    .font(.custom(state.theme.p.font, size: 22 * state.theme.p.fontScale * Metrics.s)).textCase(.uppercase)
                                    .foregroundColor(Ink.bg)
                                    .padding(.horizontal, 28).padding(.vertical, 14)
                                    .background(Capsule().fill(state.theme.p.paper))
                                    .overlay(Capsule().strokeBorder(Ink.bg, lineWidth: 3))
                                    .background(Capsule().fill(Ink.bg).offset(x: 6, y: 6))
                                    .rotationEffect(.degrees(-1.5))
                            } else {
                                Text(toast)
                                    .font(.ui(20, weight: .semibold))
                                    .foregroundColor(Ink.fg)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 16)
                                    .background(Capsule().fill(Ink.bg.opacity(0.75)))
                                    .overlay(Capsule().strokeBorder(Ink.fg.opacity(0.15)))
                            }
                        }
                        .padding(.bottom, 110)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .onAppear {
                state.setColumns(for: geo.size.width)
                DispatchQueue.main.async { state.applyDisplayFilter() }   // Fenster existiert erst jetzt
            }
            .onChange(of: geo.size.width) { w in state.setColumns(for: w) }
            .onChange(of: state.uiScale) { _ in state.setColumns(for: geo.size.width) }
            // Metriken sind statisch – bei neuer Textgröße alles neu aufbauen.
            .id("\(state.uiScale)-\(state.readScale)-\(state.theme.rawValue)-\(state.contentLanguage)")   // Schriftfamilie hängt am Stil, Texte an der Sprache
        }
        .preferredColorScheme(state.theme.isLight ? .light : .dark)
        .environment(\.theme, state.theme)
    }

    /// Wohin die Startseite scrollt: zur fokussierten Poster-Reihe, sonst zur fokussierten Kachel.
    private var homeTarget: String? {
        if let r = state.posterRow { return "row-\(r)" }
        return state.focusedItem?.id
    }

    private func isEnabled(_ tile: Tile) -> Bool {
        if case .service(let s) = tile { return state.isEnabled(s) }
        return true
    }
}

// MARK: - Hintergrund (nimmt die Farben der fokussierten Kachel an)

struct AmbientBackground: View {
    @Environment(\.theme) private var theme
    let service: Service?
    var backdrop: URL? = nil

    var body: some View {
        let base = theme.bold ? theme.p.bg : Color(hex: theme.pageHex)
        ZStack {
            ThemedBackground()
            // Klar: ruhiger, einfarbiger Hintergrund – keine Bilder oder Farbverläufe hinter Text.
            if !theme.isClear, let b = backdrop {
                // Bild füllt, beeinflusst aber nie das Layout (sonst wird alles breiter als der Bildschirm)
                Color.clear.overlay(AsyncImage(url: b) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }).clipped()
                .opacity(0.45)
                .overlay(LinearGradient(colors: [.clear, base],
                                        startPoint: .top, endPoint: .bottom))
                .id(b)
                .transition(.opacity)
            }
            if !theme.isClear, let s = service {
                RadialGradient(colors: [Color(hex: s.colorTop).opacity(0.5), Color.clear],
                               center: .top, startRadius: 20, endRadius: 900)
                RadialGradient(colors: [Color(hex: s.colorBottom).opacity(0.6), Color.clear],
                               center: .bottomTrailing, startRadius: 20, endRadius: 800)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: service?.id)
        .animation(.easeInOut(duration: 0.6), value: backdrop)
    }
}

// MARK: - Kopfzeile

struct HeaderBar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 0..<5: return tr("Gute Nacht")
        case 5..<11: return tr("Guten Morgen")
        case 11..<18: return tr("Guten Tag")
        default: return tr("Guten Abend")
        }
    }

    var body: some View {
        HStack(spacing: 24) {
            if state.editMode {
                BackButton(text: tr("Fertig")) { state.editMode = false; state.clampFocus() }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("PopSofa")
                    .headingFont(theme.bold ? 40 : 36)
                    .foregroundColor(theme.bold ? theme.accentText : Ink.fg)
                    .popTextShadow()
                    .rotationEffect(.degrees(theme.bold ? -2 : 0))
                Text(state.editMode ? tr("Wähle, was auf deinem Home-Bildschirm erscheinen soll") : greeting)
                    .font(.ui(18, weight: .medium))
                    .dimText(0.6)
                    .lineLimit(1)
            }
            ThemeButton(focused: state.headerFocus == 3) {
                state.headerFocus = 3
                state.themeMenu.toggle()
            }
            Spacer(minLength: 16)
            ProfileButton(focused: state.headerFocus == 2) {
                state.headerFocus = 2
                state.openProfilePicker()
            }
            TextSizeButton(focused: state.headerFocus == 0) {
                state.headerFocus = 0
                state.textMenu ? (state.textMenu = false) : state.openTextMenu()
            }
            RemoteBadge(remote: state.remote, focused: state.headerFocus == 1) {
                state.headerFocus = 1
                state.sheet = .remote
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.ui(36, weight: .light))
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .foregroundColor(Ink.fg)
    }
}

/// Aktives Eingabegerät unten links neben den Kürzeln: nur ein Symbol, eckig statt rund wie die Tasten,
/// damit es nicht wie ein Kürzel aussieht. Name per Tooltip (Maus drüber oder antippen).
struct DeviceChip: View {
    @Environment(\.theme) private var theme
    @ObservedObject var controller: ControllerManager
    var keyboard = false
    @State private var tip = false

    private var name: String {
        let base = keyboard ? tr("Tastatur & Maus")
            : controller.controllerName == nil ? tr("Kein Controller verbunden")
            : controller.wired ? tr("Controller per Kabel verbunden") : tr("Controller per Bluetooth verbunden")
        return controller.mouseMode ? base + tr(" · Maus-Modus") : base
    }

    var body: some View {
        let u = Metrics.text(15) * Metrics.read
        let connected = keyboard || controller.controllerName != nil
        HStack(spacing: 6 * u) {
            Image(systemName: keyboard ? "keyboard" : (connected ? "gamecontroller.fill" : "gamecontroller"))
            if !keyboard && connected {
                // Verbindungsart: Funk oder Kabel
                Image(systemName: controller.wired ? "cable.connector" : "dot.radiowaves.left.and.right")
                    .font(.read(11, weight: .bold))
            }
            if controller.mouseMode { Image(systemName: "cursorarrow") }
        }
        .font(.read(15, weight: .bold))
        .foregroundColor(Ink.fg.opacity(connected ? 1 : 0.45))
        .padding(.horizontal, 10 * u)
        .frame(minWidth: 38 * u, minHeight: 28 * u)
        .background(RoundedRectangle(cornerRadius: 7 * u, style: .continuous).fill(Ink.fg.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 7 * u, style: .continuous)
            .strokeBorder(theme.bold ? Ink.fg : Ink.fg.opacity(0.35), style: StrokeStyle(lineWidth: theme.bold ? 2 : 1, dash: [4, 3])))
        .overlay(alignment: .top) {
            if tip {
                Text(name)
                    .font(.ui(14, weight: .semibold)).fixedSize()
                    .foregroundColor(Ink.fg)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Ink.bg.opacity(0.9)))
                    .offset(y: -40 * u)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { tip = h } }
        .onTapGesture {
            withAnimation { tip = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { tip = false } }
        }
        .help(name)
        .accessibilityLabel(tr("Eingabegerät: %@", name))
    }
}

// MARK: - Kachel

struct TileView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme
    let tile: Tile
    let focused: Bool
    let editMode: Bool
    let enabled: Bool
    @State private var hovering = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 24, style: .continuous) }

    var body: some View {
        VStack(spacing: 16) {
            ZStack { content }
                .frame(width: Metrics.tileW, height: Metrics.tileH)
                .clipShape(shape)
                .overlay(
                    shape.fill(LinearGradient(
                        colors: [Ink.fg.opacity(theme.bold ? 0 : (focused ? 0.28 : 0.06)), Color.clear],
                        startPoint: .topLeading, endPoint: .center))
                        .allowsHitTesting(false)
                )
                .overlay(shape.strokeBorder(theme.bold ? Ink.bg : Ink.fg.opacity(focused ? 0.9 : 0.08),
                                            lineWidth: theme.bold ? (focused ? 5 : 3) : (focused ? (Typo.calm ? 5 : 3) : 1)))
                // Pop-Art: harter schwarzer Versatz-Schatten statt weichem Schatten
                .background(shape.fill(Ink.bg).offset(x: focused ? 10 : 6, y: focused ? 10 : 6)
                    .opacity(theme.bold ? 1 : 0))
                .scaleEffect(focused && !Typo.calm ? 1.13 : 1)
                .rotationEffect(.degrees(theme.bold && focused ? -2 : 0))
                .shadow(color: Ink.bg.opacity(theme.bold ? 0 : (focused ? 0.55 : 0.25)),
                        radius: focused ? 34 : 10, y: focused ? 24 : 8)

            // Feste Höhe (2 Zeilen), damit alle Kacheln einer Reihe auf gleicher Höhe stehen.
            Text(caption)
                .font(.ui(18, weight: .medium))
                .dimText(0.75)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: Metrics.tileW, height: 50 * Metrics.text(18), alignment: .top)
                .opacity(focused ? 1 : 0)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: focused)
        .onHover { hovering = $0 }
    }

    private var caption: String {
        switch tile {
        case .service(let s):
            if editMode {
                if state.movingService { return tr("Mit den Pfeilen verschieben – A zum Ablegen") }
                return (enabled ? tr("Sichtbar – A zum Ausblenden") : tr("Ausgeblendet – A zum Anzeigen")) + tr(" · RB verschieben")
            }
            return s.drm == true ? tr("%@ · öffnet in %@", s.host, state.browser.displayName) : s.host
        case .search: return tr("Titel oder Stimmung, z. B. „was Lustiges“")
        case .ours: return tr("%@ Titel", state.household.count)
        case .manage: return tr("Dienste ein- und ausblenden")
        case .add: return tr("Eigene Webseite hinzufügen")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tile {
        case .service(let s):
            ZStack {
                if theme.bold {
                    shape.fill(popColor(for: s))
                    ThemePattern(color: Ink.bg.opacity(0.18), fine: true)
                } else {
                    shape.fill(s.gradient)
                }
                Image(systemName: s.symbol)
                    .font(.ui(92, weight: .bold))
                    .foregroundColor(Ink.fg.opacity(0.16))   // nur Deko
                    .offset(x: 62 * Metrics.s, y: 42 * Metrics.s)
                Text(s.name)
                    .headingFont(30)
                    .foregroundColor(theme == .popLight ? Color(hex: Pop.inkHexLight)   // Etikett: Tinte auf Papier
                                     : theme.bold ? Pop.textOn(popHex(for: s)) : .white)   // Markenflächen sind dunkel genug
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .modifier(NamePlate(on: theme == .popLight))
                    .padding(.horizontal, 20)
                if !editMode && s.drm == true {
                    // Nur Dienste kennzeichnen, die den externen Browser öffnen.
                    HStack(spacing: 5) {
                        Image(systemName: "safari")
                        Text(tr("Öffnet Browser"))
                    }
                    .font(.ui(12, weight: .bold))
                    .foregroundColor(.white)   // liegt auf der Kachelfarbe, nicht auf der Seite
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityLabel(tr("Öffnet im Browser"))
                }
                if editMode && (focused || hovering) && !state.movingService {
                    // ‹ › zum Verschieben – für Maus, Touchpad und iPhone
                    HStack {
                        moveButton("chevron.left", s, -1)
                        Spacer()
                        moveButton("chevron.right", s, 1)
                    }
                    .padding(10)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                if editMode && focused && state.movingService {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.ui(34, weight: .bold))
                        .foregroundColor(Ink.fg)
                        .padding(14)
                        .background(Circle().fill(Ink.bg.opacity(0.55)))
                }
                if editMode {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                                .font(.ui(30))
                                .foregroundColor(enabled ? Color.green : Ink.fg.opacity(0.7))
                                .padding(14)
                        }
                        Spacer()
                    }
                }
            }
            .saturation(editMode && !enabled ? 0 : 1)
            .opacity(editMode && !enabled ? 0.5 : 1)

        case .search:
            utilityTile(symbol: "sparkle.magnifyingglass", title: tr("Suchen"))
        case .ours:
            utilityTile(symbol: "person.2.fill", title: tr("Unsere Watchlist"))
        case .manage:
            utilityTile(symbol: "slider.horizontal.3", title: tr("Dienste verwalten"))
        case .add:
            utilityTile(symbol: "plus", title: tr("Eigener Dienst"))
        }
    }

    private func moveButton(_ symbol: String, _ s: Service, _ delta: Int) -> some View {
        Button {
            if let i = state.allServices.firstIndex(where: { $0.id == s.id }) { state.moveService(s.id, to: i + delta) }
        } label: {
            Image(systemName: symbol)
                .font(.ui(18, weight: .bold))
                .foregroundColor(Ink.fg)
                .frame(width: 40 * Metrics.s, height: 40 * Metrics.s)
                .background(Circle().fill(Ink.bg.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .help(delta < 0 ? tr("Nach vorn") : tr("Nach hinten"))
    }

    /// Feste Comic-Farbe je Dienst (gleiche Farbe bei jedem Start).
    /// Stil-Farbe in Richtung der Marke (YouTube → Comic-Rot, Spotify → Comic-Grün …).
    private func popHex(for s: Service) -> String { theme.p.tone(for: s) }
    private func popColor(for s: Service) -> Color { Color(hex: popHex(for: s)) }

    private func utilityTile(symbol: String, title: String) -> some View {
        ZStack {
            shape.fill(theme.bold ? theme.p.paper : Ink.fg.opacity(0.1))
            VStack(spacing: 12) {
                Image(systemName: symbol).font(.ui(44, weight: .medium))
                Text(title).headingFont(24)
            }
            .foregroundColor(theme.bold ? Ink.bg : Ink.fg)
        }
    }
}

// MARK: - Fußzeile mit Tastenhinweisen

struct FooterBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        // Bedienart (Controller / Tastatur) direkt neben den Tastenhinweisen – dort, wo man nachschaut.
        HStack(spacing: 18) {
            DeviceChip(controller: state.controller, keyboard: state.inputMode == .keyboard)
            // Trennstrich: links das Gerät, rechts die Tastenkürzel
            Capsule().fill(Ink.fg.opacity(0.3)).frame(width: 2, height: 24 * Metrics.text(15) * Metrics.read)
            hints.layoutPriority(1)   // bekommt zuerst den Platz – sonst bricht es schon bei zwei Hinweisen um
        }
        .frame(maxWidth: .infinity)
    }

    private var hints: some View {
        FlowLayout(spacing: 22, lineSpacing: 8) {
            if state.inputMode == .keyboard {
                KeyboardHints()
            } else if state.posterRow != nil && state.showSetupCard {
                Hint(glyph: .letter("A", .green), text: tr("Einrichten"))
                Hint(glyph: .letter("B", .red), text: tr("Zurück"))
            } else if state.themeMenu {
                Hint(glyph: .symbol("dpad"), text: tr("Stil wählen"))
                Hint(glyph: .letter("A", .green), text: tr("Fertig"))
            } else if state.textMenu {
                Hint(glyph: .letter("A", .green), text: tr("Auswählen"))
                Hint(glyph: .letter("B", .red), text: tr("Schließen"))
            } else if state.headerFocus != nil {
                Hint(glyph: .letter("A", .green), text: [tr("Textgröße"), tr("iPhone koppeln"), tr("Profil wechseln"), tr("Stil wählen")][state.headerFocus ?? 0])
                Hint(glyph: .letter("B", .red), text: tr("Zurück"))
            } else if state.posterRow != nil && state.focusedTitle == nil {
                Hint(glyph: .letter("A", .green), text: tr("Alle anzeigen"))
                Hint(glyph: .letter("B", .red), text: tr("Zurück"))
            } else if state.posterRow != nil {
                Hint(glyph: .letter("A", .green), text: tr("Ansehen"))
                Hint(glyph: .letter("X", .blue), text: tr("Gefällt mir"))
                Hint(glyph: .letter("Y", .yellow), text: tr("Nicht mein Fall"))
                Hint(glyph: .letter("RB", .gray), text: tr("Genres"))
                Hint(glyph: .letter("B", .red), text: tr("Zurück"))
                Text(tr("Daten: TMDB")).dimText(0.4)
            } else if state.movingService {
                Hint(glyph: .symbol("dpad"), text: tr("Verschieben"))
                Hint(glyph: .letter("A", .green), text: tr("Ablegen"))
            } else if state.editMode {
                Hint(glyph: .letter("A", .green), text: tr("An/Aus"))
                Hint(glyph: .letter("RB", .gray), text: tr("Verschieben"))
                if case .service(let s)? = state.focusedItem, s.isCustom {
                    Hint(glyph: .letter("Y", .yellow), text: tr("Löschen"))
                }
                Hint(glyph: .letter("LB", .gray), text: tr("Auto-Maus: %@", tr(state.autoMouse ? "An" : "Aus")))
                Hint(glyph: .letter("B", .red), text: tr("Fertig"))
            } else {
                Hint(glyph: .letter("A", .green), text: {
                    if case .service(let s)? = state.focusedItem, s.drm == true { return tr("Öffnen in %@", state.browser.displayName) }
                    return tr("Öffnen")
                }())
                Hint(glyph: .letter("X", .blue), text: tr("Verwalten"))
                Hint(glyph: .letter("Y", .yellow), text: tr("Browser: %@", state.browser.title))
                Hint(glyph: .letter("LT RT", .gray), text: tr("Lautstärke"))
                Hint(glyph: .symbol("line.3.horizontal"), text: tr("Maus"))
                Hint(glyph: .symbol("l.joystick.press.down.fill"), text: tr("Tastatur"))
            }
        }
        .font(.read(15, weight: .medium))
        .lineLimit(1)
        .dimText(0.7)
        // Pop-Art: ruhiger dunkler Streifen hinter den Hinweisen, damit die Rasterpunkte nicht stören.
        .padding(.horizontal, state.theme.bold ? 20 : 0)
        .padding(.vertical, state.theme.bold ? 8 : 0)
        .background(Capsule().fill(Ink.bg.opacity(state.theme.bold ? 0.5 : 0)))
    }
}

struct Hint: View {
    @Environment(\.theme) private var theme
    enum Glyph { case letter(String, Color), symbol(String) }
    let glyph: Glyph
    let text: String

    /// Ruhige Stile: Pastellfarben auf mittlerem Grau – grelle Farben auf Schwarz säumen bei Prismen am stärksten.
    static let calmKeyHex = "#3F3A36"
    static let calmColors = ["A": "#A8D898", "B": "#F2ACA3", "X": "#A6C8F0", "Y": "#F2D58A"]

    /// Farben der Xbox-Tasten, auf dunklem Knopf mit hohem Kontrast (≥ 5:1).
    static func xboxColor(_ l: String) -> Color {
        if Typo.prism { return Color(hex: calmColors[l] ?? "#F2EEE6") }
        switch l {
        case "A": return Color(hex: "#5DC21E")
        case "B": return Color(hex: "#F0524F")
        case "X": return Color(hex: "#3D9BE9")
        case "Y": return Color(hex: "#FFC93C")
        default: return .white   // auf der dunklen Taste immer hell
        }
    }

    /// Wie die echten Knöpfe: dunkle Taste, farbige Beschriftung. Im Pop-Stil mit weißem Rand.
    private var key: some View {
        Group {
            switch glyph {
            case .letter(let l, _):
                Text(l)
                    .font(.read(l.count > 1 ? 12 : 15, weight: .heavy, design: .rounded))
                    .foregroundColor(Self.xboxColor(l))
                    .frame(minWidth: 28 * (Metrics.text(15) * Metrics.read), minHeight: 28 * (Metrics.text(15) * Metrics.read))
                    .padding(.horizontal, l.count > 1 ? 6 * (Metrics.text(15) * Metrics.read) : 0)
            case .symbol(let name):
                Image(systemName: NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "circle.circle")
                    .font(.read(15, weight: .bold))
                    .foregroundColor(.white)   // Tasten bleiben dunkel wie am Controller
                    .frame(width: 28 * (Metrics.text(15) * Metrics.read), height: 28 * (Metrics.text(15) * Metrics.read))
            }
        }
        .background(Capsule().fill(Color(hex: Typo.prism ? Self.calmKeyHex : "#1B1B1B")))
        .overlay(Capsule().strokeBorder(theme.bold ? Color.white : Color.white.opacity(0.25),
                                        lineWidth: theme.bold ? 2 : 1))
    }

    var body: some View {
        HStack(spacing: 10) {
            key
            // Farbe nur im Pop-Stil setzen – sonst erbt der Text die Farbe der Leiste (nil hieße: Systemfarbe).
            if theme.bold {
                Text(text).foregroundColor(Ink.fg).fontWeight(.semibold).popTextShadow()
            } else {
                Text(text)
            }
        }
        .fixedSize()                       // nie kürzen – lieber als Ganzes in die nächste Zeile
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Eigenen Dienst hinzufügen


/// Dienste verwalten: Kachel mit der Maus auf einen anderen Platz ziehen.
struct ServiceDrag: ViewModifier {
    @EnvironmentObject var state: AppState
    let tile: Tile
    let index: Int

    func body(content: Content) -> some View {
        if state.editMode, case .service(let s) = tile {
            content
                .onDrag { NSItemProvider(object: s.id as NSString) }
                .onDrop(of: [.text], delegate: Reorder(state: state, index: index))
        } else {
            content
        }
    }

    /// Schon beim Darüberziehen umsortieren – die Kacheln weichen sichtbar aus.
    struct Reorder: DropDelegate {
        let state: AppState
        let index: Int
        func dropEntered(info: DropInfo) {
            guard let p = info.itemProviders(for: [.text]).first else { return }
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let id = obj as? String else { return }
                DispatchQueue.main.async { withAnimation(.spring(response: 0.3)) { state.moveService(id, to: index) } }
            }
        }
        func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
        func performDrop(info: DropInfo) -> Bool { true }
    }
}

/// Pop hell: Kachelname auf Papier-Etikett mit Tinten-Kontur – nie direkt auf Farbe und Rasterpunkten.
struct NamePlate: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content
                .foregroundColor(Color(hex: Pop.inkHexLight))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: "#FFF7E8")))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(hex: Pop.inkHexLight), lineWidth: 2.5))
        } else {
            content
        }
    }
}
