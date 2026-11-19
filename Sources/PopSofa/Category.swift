import SwiftUI

// MARK: - „Alle anzeigen“: eine Reihe als Raster, lädt weitere TMDB-Seiten nach

struct Category {
    var title: String
    var items: [Title]
    var sources: [RowSource]
    var page = 1
    var loading = false
    var done: Bool
    var sort = Sort.popular

    enum Sort: String, CaseIterable {
        case popular = "Beliebt", rating = "Beste Bewertung", new = "Neueste"   // Anzeige über tr(rawValue)
        var next: Sort { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }

        /// TMDB sortiert /discover selbst; andere Quellen bleiben, wie sie sind.
        func apply(_ s: RowSource) -> RowSource {
            guard s.path.hasPrefix("/discover") else { return s }
            var q = s.query
            let date = s.type == "tv" ? "first_air_date" : "primary_release_date"
            switch self {
            case .popular: q["sort_by"] = "popularity.desc"
            case .rating:
                q["sort_by"] = "vote_average.desc"
                q["vote_count.gte"] = max(Int(q["vote_count.gte"] ?? "") ?? 0, s.type == "tv" ? 150 : 300).description
            case .new:
                q["sort_by"] = "\(date).desc"
                q["\(date).lte"] = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
            }
            return RowSource(path: s.path, query: q, type: s.type)
        }

        /// Für Listen ohne TMDB-Quelle (Merkliste) und zum Nachsortieren.
        func order(_ list: [Title]) -> [Title] {
            switch self {
            case .popular: return list
            case .rating: return list.sorted { $0.quality > $1.quality }
            case .new: return list.sorted { $0.year > $1.year }
            }
        }
    }

    // ponytail: höchstens 10 Seiten (~400 Titel) – reicht zum Stöbern, schont das TMDB-Limit.
    static let maxPage = 10

    /// Neue Titel anhängen: ohne Doppelte und ohne Abgelehnte.
    static func merge(_ old: [Title], _ new: [Title], disliked: Set<String>) -> [Title] {
        var seen = Set(old.map(\.key))
        return old + new.filter { !disliked.contains($0.key) && seen.insert($0.key).inserted }
    }

    static func selfTest() {
        func t(_ id: Int, _ type: String = "movie") -> Title {
            Title(id: id, type: type, name: "\(id)", overview: "", poster: nil, backdrop: nil, genres: [], rating: 0, year: "")
        }
        let m = merge([t(1), t(2)], [t(2), t(3), t(4), t(1, "tv")], disliked: ["movie-4"])
        precondition(m.map(\.key) == ["movie-1", "movie-2", "movie-3", "tv-1"])
        let src = RowSource(path: "/discover/tv", query: ["vote_count.gte": "100", "sort_by": "popularity.desc"], type: "tv")
        let r = Sort.rating.apply(src)
        precondition(r.query["sort_by"] == "vote_average.desc" && r.query["vote_count.gte"] == "150")
        precondition(Sort.new.apply(src).query["sort_by"] == "first_air_date.desc")
        let rec = RowSource(path: "/movie/1/recommendations", query: [:], type: "movie")
        precondition(Sort.rating.apply(rec).query.isEmpty)
    }
}

extension AppState {
    func openCategory(_ row: PosterRow) {
        category = Category(title: row.title, items: row.items, sources: row.sources, done: row.sources.isEmpty)
        categoryIndex = 0
        loadMore()
    }

    /// Sortierung setzen (Auswahlliste über A auf „Sortiert“ oder RB) – lädt von vorn, wo TMDB sortieren kann.
    func setCategorySort(_ s: Category.Sort) {
        // Auch während des Ladens: alte Antworten verwirft `loadMore` über den Sortier-Vergleich.
        guard var c = category, c.sort != s else { return }
        c.loading = false
        c.sort = s
        categoryIndex = 0
        if c.sources.isEmpty {
            c.items = c.sort.order(c.items)
            category = c
        } else {
            c.items = []
            c.page = 0
            c.done = false
            category = c
            loadMore()
        }
    }

    func loadMore() {
        guard var c = category, !c.loading, !c.done, let key = tmdbKey else { return }
        c.loading = true
        c.page += 1
        category = c
        let page = c.page, sources = c.sources.map(c.sort.apply), title = c.title, sort = c.sort
        let api = TMDB(key: key)
        Task {
            var lists: [[Title]] = []
            for s in sources {
                var q = s.query
                q["page"] = String(page)
                lists.append((try? await api.list(s.path, q, type: s.type)) ?? [])
            }
            // Nur übernehmen, wenn noch dieselbe Kategorie offen ist.
            guard var c = category, c.title == title, c.page == page, c.sort == sort else { return }
            let fresh = lists.reduce([]) { interleave($0, $1) }
            let before = c.items.count
            // „Beliebt“ nach Geschmack, sonst die Reihenfolge von TMDB (nach Bewertung/Datum).
            let ordered = sort == .popular ? taste.rank(fresh) : sort.order(fresh)
            c.items = Category.merge(c.items, ordered, disliked: taste.disliked)
            c.loading = false
            c.done = (c.items.count == before && page > 1) || page >= Category.maxPage
            category = c
            if Debug.on { print("category \(title): page=\(page) items=\(c.items.count) done=\(c.done)") }
        }
    }

    var focusedCategoryTitle: Title? {
        guard let c = category, c.items.indices.contains(categoryIndex) else { return nil }
        return c.items[categoryIndex]
    }

    func handleCategory(_ e: PadEvent) {
        guard let c = category else { return }
        // Obere Zeile: „Zurück“ und Sortier-Knopf, per ↑ aus der ersten Posterreihe erreichbar.
        if sortFocus {
            switch e {
            case .left: sortFocus = false; backFocus = true
            case .down: sortFocus = false
            case .a, .rb: chooseCategorySort()
            case .b: category = nil
            default: break
            }
            return
        }
        if backFocus {
            switch e {
            case .right: backFocus = false; sortFocus = true
            default: _ = handleBack(e, close: { category = nil })
            }
            return
        }
        let n = c.items.count, cols = max(categoryColumns, 1)
        if e == .up && categoryIndex < cols { backFocus = true; return }
        switch e {
        case .left: categoryIndex = max(categoryIndex - 1, 0)
        case .right: categoryIndex = min(categoryIndex + 1, max(n - 1, 0))
        case .up: if categoryIndex >= cols { categoryIndex -= cols }
        case .down: categoryIndex = min(categoryIndex + cols, max(n - 1, 0))
        case .a: if let t = focusedCategoryTitle { openDetail(t) }
        case .x: if let t = focusedCategoryTitle { like(t) }
        case .y: if let t = focusedCategoryTitle { dislike(t) }
        case .b: category = nil; return
        case .rb: chooseCategorySort(); return
        default: break
        }
        categoryIndex = min(categoryIndex, max((category?.items.count ?? 1) - 1, 0))
        // Kurz vor dem Ende nachladen.
        if categoryIndex >= n - 2 * cols { loadMore() }
    }
}

struct CategoryOverlay: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let c = state.category {
            ZStack(alignment: .top) {
                ThemedBackground().opacity(0.98).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    BackButton(focused: state.backFocus) { state.category = nil }
                    HStack(alignment: .center, spacing: 16) {
                        Text(c.title).headingFont(34)
                        Text(tr("%@ Titel", c.items.count)).font(.ui(17, weight: .semibold)).dimText(0.6)
                        if c.loading { ProgressView().controlSize(.small) }
                        Spacer()
                        Button { state.chooseCategorySort() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(tr("Sortiert: %@", tr(c.sort.rawValue)))
                            }
                            .font(.ui(17, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(Ink.fg.opacity(state.sortFocus ? 0.35 : 0.12)))
                            .overlay(Capsule().strokeBorder(state.theme.bold ? state.theme.p.accent : Ink.fg, lineWidth: 3)
                                .padding(-4).opacity(state.sortFocus ? 1 : 0))
                            .scaleEffect(state.sortFocus && !Typo.calm ? 1.08 : 1)
                        }
                        .buttonStyle(.plain)
                    }

                    GeometryReader { geo in
                        FocusScroll(axis: .vertical,
                                    target: state.focusedCategoryTitle?.key,
                                    position: 0.4, space: "category", wheel: state.detail == nil) {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Metrics.posterW), spacing: 22),
                                                     count: columns(geo.size.width)), spacing: 30) {
                                ForEach(Array(c.items.enumerated()), id: \.element.key) { i, t in
                                    PosterCard(title: t, focused: i == state.categoryIndex,
                                               liked: state.taste.liked.contains(t.key))
                                        .scrollAnchor(t.key, in: "category")
                                        .onTapGesture { state.categoryIndex = i; state.openDetail(t) }
                                }
                                // Für Maus/Touchpad: das Raster baut alle Poster sofort, daher kein onAppear-Nachladen.
                                if !c.done {
                                    ShowAllCard(focused: false, symbol: "arrow.down.circle",
                                                text: c.loading ? tr("Lädt …") : tr("Mehr\nladen"))
                                        .scrollAnchor("more", in: "category")   // zählt fürs Scrollende mit
                                        .onTapGesture { state.loadMore() }
                                }
                            }
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                        }
                        .onAppear { state.categoryColumns = columns(geo.size.width) }
                        .onChange(of: geo.size.width) { state.categoryColumns = columns($0) }
                    }

                    if let t = state.focusedCategoryTitle { TitleDetail(title: t) }

                    FlowLayout(spacing: 22, lineSpacing: 8, centered: false) {
                        if state.inputMode == .keyboard {
                            KeyboardHints()
                        } else {
                            Hint(glyph: .letter("A", .green), text: tr("Ansehen"))
                            Hint(glyph: .letter("X", .blue), text: tr("Gefällt mir"))
                            Hint(glyph: .letter("Y", .yellow), text: tr("Nicht mein Fall"))
                            Hint(glyph: .letter("RB", .gray), text: tr("Sortieren"))
                            Hint(glyph: .letter("B", .red), text: tr("Zurück"))
                        }
                        // (Quelle steht als letzter Eintrag in der Zeile)
                        Text(tr("Daten: TMDB")).dimText(0.4)
                    }
                    .font(.read(15, weight: .medium))
                    .lineLimit(1)
                    .dimText(0.75)
                }
                .padding(.horizontal, Metrics.side)
                .padding(.top, 36)
                .padding(.bottom, 24)
            }
            .foregroundColor(Ink.fg)
        }
    }

    private func columns(_ width: CGFloat) -> Int {
        max(2, Int((width + 22) / (Metrics.posterW + 22)))
    }
}

/// Letzte Karte jeder Reihe: öffnet die Kategorie-Ansicht.
struct ShowAllCard: View {
    @Environment(\.theme) private var theme
    let focused: Bool
    var symbol = "square.grid.2x2"
    var text = tr("Alle\nanzeigen")

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.ui(36, weight: .semibold))
            Text(text).font(.ui(18, weight: .bold)).multilineTextAlignment(.center)
        }
        .foregroundColor(theme.bold ? Ink.bg : Ink.fg)
        .frame(width: Metrics.posterW, height: Metrics.cardH)
        .themedCard(radius: 14, focused: focused)
        .scaleEffect(focused && !Typo.calm ? 1.12 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: focused)
        .accessibilityLabel(text.replacingOccurrences(of: "\n", with: " "))
    }
}
