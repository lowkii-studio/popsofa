import SwiftUI

// MARK: - Empfehlungs-Reihen unter den Kacheln

struct PosterSection: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if state.showSetupCard {
                SetupCard(focused: state.posterRow == 0, status: state.recoStatus,
                          hasKey: state.tmdbKey != nil)
                    .scrollAnchor("row-0", in: "home")
                    .onTapGesture { state.sheet = .key }
            } else {
                ForEach(Array(state.rows.enumerated()), id: \.element.id) { r, row in
                    PosterRowView(row: row, rowIndex: r,
                                  focusedIndex: state.posterRow == r ? state.posterIndex : nil)
                        .scrollAnchor("row-\(r)", in: "home")
                }
            }
        }
        .padding(.horizontal, Metrics.side)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PosterRowView: View {
    @EnvironmentObject var state: AppState
    let row: PosterRow
    let rowIndex: Int
    let focusedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(row.title)
                .headingFont(22)
                .dimText(focusedIndex == nil ? 0.6 : 1)
            FocusScroll(axis: .horizontal,
                        target: focusedIndex.map { row.items.indices.contains($0) ? row.items[$0].key : "all-\(row.id)" },
                        position: 0.4, space: "row-\(row.id)") {
                    HStack(spacing: 22) {
                        ForEach(Array(row.items.enumerated()), id: \.element.key) { i, t in
                            PosterCard(title: t, focused: i == focusedIndex,
                                       liked: state.taste.liked.contains(t.key))
                                .scrollAnchor(t.key, in: "row-\(row.id)")
                                .onTapGesture {
                                    state.posterRow = rowIndex
                                    state.posterIndex = i
                                    state.openDetail(t)
                                }
                        }
                        ShowAllCard(focused: focusedIndex == row.items.count)
                            .scrollAnchor("all-\(row.id)", in: "row-\(row.id)")
                            .onTapGesture {
                                state.posterRow = rowIndex
                                state.posterIndex = row.items.count
                                state.openCategory(row)
                            }
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 14)
            }
            .frame(height: Metrics.cardH + 48)
        }
    }
}

struct PosterCard: View {
    /// Film und Serie in unterschiedlichen Farbtönen, je Stil passend.
    static func chipHex(series: Bool, theme: Theme) -> String {
        switch theme {
        case .apple: return series ? "#BF5AF2" : "#0A84FF"     // Systemfarben Lila / Blau
        case .pop: return series ? "#FF5DA2" : "#FFD23F"       // Comic-Pink / Comic-Gelb
        case .afro: return series ? "#1E7A46" : "#F4B63F"      // Kente-Grün / Kente-Gold
        case .popLight: return series ? "#FF5DA2" : "#FFD23F"  // Comic-Pink / Comic-Gelb (Tinte darauf)
        case .clear, .clearLight: return series ? "#C5B3E6" : "#A9D1F5"     // ruhige Pastelltöne, schwarze Schrift
        }
    }


    @Environment(\.theme) private var theme
    @EnvironmentObject private var state: AppState
    let title: Title
    let focused: Bool
    let liked: Bool
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    /// Fußzeile unter dem Bild: Film/Serie, Jahr, Bewertung – verdeckt nichts vom Poster.
    private var footer: some View {
        let chip = Self.chipHex(series: title.type == "tv", theme: theme)
        let bg = theme.bold ? theme.p.paper : Color(hex: Ink.light ? "#F1E6D3" : "#15151C")
        return HStack(spacing: 6 * Metrics.s) {
            Text(title.type == "tv" ? "SERIE" : "FILM")
                .font(.ui(11, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundColor(Pop.textOn(chip))
                .padding(.horizontal, 6 * Metrics.s).padding(.vertical, 2 * Metrics.s)
                .background(Capsule().fill(Color(hex: chip)))
                .overlay(Capsule().strokeBorder(theme.bold ? Ink.bg : .clear, lineWidth: 1.5))
                .fixedSize()            // Film/Serie nie kürzen – lieber Jahr/Bewertung verkleinern
                .layoutPriority(1)
            Spacer(minLength: 2)
            if !title.year.isEmpty { Text(title.year) }
            if title.rating > 0 { Text(String(format: "★%.1f", title.rating)) }
        }
        .font(.ui(13, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundColor(theme.bold ? Ink.bg : Ink.fg)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 8 * Metrics.s)
        .frame(width: Metrics.posterW, height: Metrics.posterFooter)
        .background(bg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title.type == "tv" ? tr("Serie") : tr("Film"), title.year,
                             title.rating > 0 ? String(format: tr("Bewertung %.1f"), title.rating) : ""]
                                .filter { !$0.isEmpty }.joined(separator: ", "))
    }

    var body: some View {
        VStack(spacing: 0) {
            AsyncImage(url: title.posterURL) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Ink.fg.opacity(0.08)
                    Text(title.name).font(.ui(16, weight: .semibold))
                        .multilineTextAlignment(.center).padding(10)
                }
            }
            .frame(width: Metrics.posterW, height: Metrics.posterH)
            .clipped()
            footer
        }
        .clipShape(shape)
        .overlay(alignment: .topTrailing) {
            if liked {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.ui(16, weight: .bold))
                    .padding(8)
                    .background(Circle().fill(Ink.bg.opacity(0.6)))
                    .padding(8)
            }
        }
        .overlay(shape.strokeBorder(theme.bold ? (focused ? theme.p.accent : Ink.bg) : Ink.fg.opacity(focused ? 0.9 : 0.06),
                                    lineWidth: theme.bold ? (focused ? 6 : 3) : (focused ? 3 : 1)))
        .background(shape.fill(Ink.bg).offset(x: focused ? 9 : 5, y: focused ? 9 : 5).opacity(theme.bold ? 1 : 0))
        .scaleEffect(focused && !Typo.calm ? 1.12 : 1)
        .rotationEffect(.degrees(theme.bold && focused ? 1.5 : 0))
        .shadow(color: Ink.bg.opacity(theme.bold ? 0 : (focused ? 0.6 : 0.2)), radius: focused ? 26 : 8, y: focused ? 18 : 6)
        .foregroundColor(Ink.fg)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: focused)
        // Rechtsklick (Maus/Touchpad): bewerten und merken
        .contextMenu {
            Button { state.like(title) } label: { Label(tr("Gefällt mir"), systemImage: "hand.thumbsup") }
            Button { state.dislike(title) } label: { Label(tr("Nicht mein Fall"), systemImage: "hand.thumbsdown") }
            Divider()
            Button { state.toggleWatchlist(title) } label: {
                Label(state.isOnWatchlist(title) ? tr("Von der Watchlist entfernen") : tr("Auf die Watchlist"),
                      systemImage: state.isOnWatchlist(title) ? "minus.circle" : "plus.circle")
            }
        }
    }
}

struct TitleDetail: View {
    @EnvironmentObject var state: AppState
    let title: Title

    private var meta: String {
        var parts = [title.type == "tv" ? tr("Serie") : tr("Film")]
        if !title.year.isEmpty { parts.append(title.year) }
        if title.rating > 0 { parts.append(String(format: "★ %.1f", title.rating)) }
        if let l = title.lang, l != L10n.lang { parts.append(tr("O-Ton %@", SearchPlan.languageName(l))) }
        switch state.serviceName(for: title) {
        case nil: break
        case ""?: parts.append(tr("Nicht in deinen Diensten"))
        case let n?: parts.append(tr("Läuft bei %@", n))
        }
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.name).headingFont(26).lineLimit(1)
            Text(meta).font(.read(16, weight: .semibold)).dimText(0.75)
            if !title.overview.isEmpty {
                Text(title.overview).font(.read(15)).lineLimit(2)
                    .dimText(0.6)
            }
        }
        .foregroundColor(Ink.fg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }
}

struct SetupCard: View {
    @Environment(\.theme) private var theme
    let focused: Bool
    let status: String?
    let hasKey: Bool

    var body: some View {
        HStack(spacing: 24) {
            Image(systemName: "sparkles.tv").font(.ui(44, weight: .medium))
            VStack(alignment: .leading, spacing: 6) {
                Text(hasKey ? tr("Empfehlungen") : tr("Empfehlungen einrichten"))
                    .headingFont(26)
                Text(status ?? tr("Neue Filme & Serien nach deinem Geschmack – mit kostenlosem TMDB-Schlüssel."))
                    .font(.ui(17)).dimText(0.65)
            }
            Spacer()
        }
        .foregroundColor(Ink.fg)
        .padding(28)
        .frame(maxWidth: 820 * Metrics.s)
        .themedCard(radius: 24, focused: focused, fill: theme.bold ? theme.p.card : Ink.fg.opacity(0.1))
        .padding(.vertical, 20)
    }
}

// MARK: - TMDB-Schlüssel eingeben


// MARK: - Genres wählen


// MARK: - Detailansicht

struct DetailOverlay: View {
    @EnvironmentObject var state: AppState
    let title: Title

    private var meta: String {
        var parts = [title.type == "tv" ? tr("Serie") : tr("Film")]
        if !title.year.isEmpty { parts.append(title.year) }
        if let s = state.detailInfo?.seasons { parts.append(s == 1 ? tr("1 Staffel") : tr("%@ Staffeln", s)) }
        if let m = state.detailInfo?.runtime, m > 0 {
            parts.append(m >= 60 ? tr("%@ Std. %@ Min.", m / 60, m % 60) : tr("%@ Min.", m))
        }
        if title.rating > 0 { parts.append(String(format: "★ %.1f", title.rating)) }
        if let l = title.lang, l != L10n.lang { parts.append(tr("O-Ton %@", SearchPlan.languageName(l))) }
        return parts.joined(separator: "  ·  ")
    }

    private var base: Color { state.theme.bold ? state.theme.p.bg : Color(hex: state.theme.pageHex) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ThemedBackground()
            // Bild füllt, beeinflusst aber nie das Layout (sonst wird alles breiter als der Bildschirm)
                Color.clear.overlay(AsyncImage(url: title.backdropURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }).clipped()
            .opacity(Typo.prism ? 0 : 0.55)   // Lesbarkeits-Stile: kein Bild hinter Text
            .overlay(LinearGradient(colors: [base, base.opacity(0.6), .clear],
                                    startPoint: .leading, endPoint: .trailing))
            .overlay(LinearGradient(colors: [.clear, base], startPoint: .center, endPoint: .bottom))
            if state.theme.bold { ThemePattern(color: state.theme.p.dots.opacity(0.3)) }

            VStack(alignment: .leading, spacing: 0) {
                // Eigene Zeile oben links – überlagert keine Inhalte (wie in Suche und Kategorie).
                BackButton(focused: state.backFocus) { state.detail = nil }
                    .padding(.top, 36)
                    .padding(.leading, -10)
                Spacer(minLength: 20)
                HStack(alignment: .top, spacing: 40) {
                    if state.trailerPlaying, let id = state.detailInfo?.trailer {
                        // 16:9 in Posterhöhe
                        InlineTrailerView(videoID: id) { state.inlineTrailer = $0 }
                            .frame(width: Metrics.posterH * 1.4 * 16 / 9, height: Metrics.posterH * 1.4)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Ink.bg.opacity(0.5), radius: 24, y: 14)
                            .transition(.opacity)
                    } else {
                        PosterCard(title: title, focused: false, liked: state.taste.liked.contains(title.key))
                            .scaleEffect(1.4, anchor: .topLeading)
                            .frame(width: Metrics.posterW * 1.4, height: Metrics.cardH * 1.4, alignment: .topLeading)
                    }
                    info
                }
                Spacer(minLength: 30)
                providers
                Spacer(minLength: 24)
                footer
            }
            .padding(.horizontal, Metrics.side + 10)
            .padding(.bottom, 28)
        }
        .foregroundColor(Ink.fg)
        .ignoresSafeArea()
    }

    /// Bewerten per Maus (Controller: X/Y, Tastatur: L/N).
    private func rateButton(_ symbol: String, _ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: on ? symbol + ".fill" : symbol)
                Text(text)
            }
            .font(.read(16, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Ink.fg.opacity(on ? 0.3 : 0.12)))
            .foregroundColor(Ink.fg)
        }
        .buttonStyle(.plain)
        .help(text)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.name).headingFont(42).lineLimit(2)
                .foregroundColor(state.theme.bold ? state.theme.accentText : Ink.fg).popTextShadow()
                .minimumScaleFactor(0.7)
            Text(meta).font(.read(18, weight: .semibold)).dimText(0.8)
            HStack(spacing: 10) {
                rateButton("hand.thumbsup", tr("Gefällt mir"), on: state.taste.liked.contains(title.key)) { state.like(title) }
                rateButton("hand.thumbsdown", tr("Nicht mein Fall"), on: false) { state.dislike(title) }
            }
            if let g = state.detailInfo?.genres, !g.isEmpty {
                Text(g.joined(separator: " · ")).font(.read(18)).dimText(0.6)
            }
            if let tl = state.detailInfo?.tagline, !tl.isEmpty {
                Text(tl).font(.read(20, weight: .medium)).italic()
            }
            Text(title.overview.isEmpty ? tr("Keine Beschreibung verfügbar.") : title.overview)
                .font(.read(17)).lineSpacing(3).lineLimit(Metrics.m * Metrics.read > 1.2 ? 4 : 6)
                .dimText(0.85)
                .frame(maxWidth: 900 * Metrics.text(17), alignment: .leading)
            if let c = state.detailInfo?.cast, !c.isEmpty {
                Text(tr("Mit ") + c.joined(separator: ", ")).font(.read(17)).dimText(0.6).lineLimit(2)
            }
        }
    }

    private var providers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Ansehen bei")).headingFont(24)
            if state.detailInfo == nil {
                Text(tr("Lade Anbieter …")).dimText(0.6).padding(.vertical, 30)
            } else {
                FocusScroll(axis: .horizontal, target: "p\(state.detailFocus)", position: 0.4, space: "providers") {
                        HStack(spacing: 20) {
                            let opts = state.detailOptions
                            let o0 = state.actionOffset
                            let wl = state.trailerOffset
                            if wl == 1 {
                                TrailerButton(focused: state.detailFocus == 0, playing: state.trailerPlaying, paused: state.trailerPaused)
                                    .scrollAnchor("p0", in: "providers")
                                    .onTapGesture { state.activateDetail(0) }
                            }
                            WatchlistButton(focused: state.detailFocus == wl, added: state.isOnWatchlist(title))
                                .scrollAnchor("p\(wl)", in: "providers")
                                .onTapGesture { state.activateDetail(wl) }
                            if opts.isEmpty {
                                Text(tr("In %@ gerade nicht im Stream.", Region.name(state.country)))
                                    .dimText(0.6)
                            }
                            ForEach(Array(opts.enumerated()), id: \.element.id) { i, o in
                                ProviderButton(option: o, focused: i + o0 == state.detailFocus,
                                               subscribed: o.serviceID.map(state.enabledIDs.contains) ?? false)
                                    .scrollAnchor("p\(i + o0)", in: "providers")
                                    .onTapGesture { state.activateDetail(i + o0) }
                            }
                            ProviderButton(option: nil, focused: state.detailFocus == opts.count + o0, subscribed: false)
                                .scrollAnchor("p\(opts.count + o0)", in: "providers")
                                .onTapGesture { state.activateDetail(opts.count + o0) }
                        }
                        .padding(.vertical, 24)
                        .padding(.horizontal, 12)
                }
                .frame(height: 128 * Metrics.s)
            }
        }
    }

    private var footer: some View {
        FlowLayout(spacing: 28, lineSpacing: 8, centered: false) {
            if state.inputMode == .keyboard {
                KeyboardHints()
            } else {
                Hint(glyph: .letter("A", .green), text: tr("Ansehen"))
                Hint(glyph: .letter("X", .blue), text: state.taste.liked.contains(title.key) ? tr("Gefällt dir") : tr("Gefällt mir"))
                Hint(glyph: .letter("Y", .yellow), text: tr("Nicht mein Fall"))
                if state.trailerOffset == 1 { Hint(glyph: .letter("RB", .gray), text: tr("Vollbild auf YouTube")) }
                Hint(glyph: .letter("B", .red), text: tr("Zurück"))
            }
            Text(tr("Daten: TMDB · Anbieter: JustWatch")).dimText(0.4)
        }
        .font(.read(17, weight: .medium))
        .lineLimit(1)
        .dimText(0.75)
    }
}

struct ProviderButton: View {
    let option: ProviderOption?          // nil = alle Anbieter bei TMDB
    let focused: Bool
    let subscribed: Bool
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let o = option {
                    AsyncImage(url: o.logoURL) { img in img.resizable() } placeholder: { Ink.fg.opacity(0.1) }
                } else {
                    Image(systemName: "ellipsis").font(.ui(24, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Ink.fg.opacity(0.15))
                }
            }
            .frame(width: 52 * Metrics.s, height: 52 * Metrics.s)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(option?.name ?? tr("Alle Anbieter")).font(.ui(18, weight: .semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    if subscribed { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
                    Text(option.map { subscribed ? tr("%@ · deine Dienste", tr($0.kind)) : tr($0.kind) } ?? tr("bei TMDB"))
                }
                .font(.ui(15)).opacity(0.7)
            }
        }
        .padding(.leading, 12).padding(.trailing, 22).padding(.vertical, 12)
        .themedCard(focused: focused)
    }
}

struct TrailerButton: View {
    let focused: Bool
    let playing: Bool
    var paused = false
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: playing && !paused ? "pause.fill" : "play.fill")
                .font(.ui(22, weight: .bold))
                .frame(width: 52 * Metrics.s, height: 52 * Metrics.s)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.red.opacity(0.85)))
            VStack(alignment: .leading, spacing: 3) {
                Text(!playing ? "Trailer" : paused ? tr("Fortsetzen") : tr("Pause")).font(.ui(18, weight: .semibold))
                Text(playing ? tr("RB: Vollbild auf YouTube") : "YouTube").font(.ui(15)).opacity(0.7)
            }
        }
        .padding(.leading, 12).padding(.trailing, 22).padding(.vertical, 12)
        .themedCard(focused: focused)
    }
}

struct WatchlistButton: View {
    let focused: Bool
    let added: Bool
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: added ? "checkmark" : "plus")
                .font(.ui(22, weight: .bold))
                .frame(width: 52 * Metrics.s, height: 52 * Metrics.s)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(added ? Color.green.opacity(0.75) : Ink.fg.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(added ? tr("Auf der Watchlist") : "Watchlist").font(.ui(18, weight: .semibold))
                Text(added ? tr("Entfernen") : tr("Für später merken"))
                    .font(.ui(15)).opacity(0.7)
            }
        }
        .padding(.leading, 12).padding(.trailing, 22).padding(.vertical, 12)
        .themedCard(focused: focused)
    }
}
