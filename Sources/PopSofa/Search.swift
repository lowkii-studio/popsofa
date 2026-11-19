import SwiftUI
import FoundationModels

// MARK: - Suchplan: was die Suche an TMDB schickt

struct SearchPlan {
    var mediaType = "any"          // movie, tv, any
    var genres: [Genre] = []
    var maxRuntime = 0             // Minuten, 0 = egal
    var minYear = 0
    var titleQuery = ""            // konkreter Titel/Person → Textsuche
    var language: String?          // Originalsprache (ISO 639-1, z. B. "pt")
    var country: String?           // Herkunftsland (z. B. "BR" für brasilianisch)
    var summary = ""

    static func titleSearch(_ text: String) -> SearchPlan {
        SearchPlan(titleQuery: text, summary: tr("Titelsuche „%@“", text))
    }

    // ponytail: Stichwort-Liste als Ersatz, wenn Apple Intelligence fehlt; versteht nur diese Wörter (de/en/pt).
    private static let moodWords: [(String, [String])] = [
        ("Komödie", ["lustig", "witzig", "komödie", "lachen", "humor", "leicht", "funny", "comedy", "engraçad", "comédia"]),
        ("Thriller", ["spannend", "thriller", "nervenkitzel", "packend", "gripping", "suspense", "emocionante"]),
        ("Horror", ["grusel", "horror", "angst", "unheimlich", "creepy", "scary", "assustador", "terror"]),
        ("Krimi", ["krimi", "mord", "detektiv", "verbrechen", "crime", "detective", "murder", "policial"]),
        ("Doku", ["doku", "dokumentation", "natur", "wahre geschichte", "documentar", "true story"]),
        ("Familie", ["familie", "kinder", "family", "família", "kids", "crianças"]),
        ("Animation", ["animation", "anime", "zeichentrick", "cartoon", "animação"]),
        ("Romantik", ["romantisch", "liebe", "romanze", "date", "romantic", "romance", "romântic", "amor"]),
        ("Science-Fiction", ["sci-fi", "science", "weltraum", "zukunft", "aliens", "space", "ficção científica", "espaço"]),
        ("Fantasy", ["fantasy", "magie", "drachen", "magic", "dragon", "fantasia", "magia"]),
        ("Action", ["action", "explosion", "de ação"]),
        ("Abenteuer", ["abenteuer", "adventure", "aventura"]),
        ("Drama", ["drama", "traurig", "emotional", "berührend", "sad", "triste"]),
        ("Krieg & Politik", ["krieg", "politik", "politic", "guerra", "política"]),
        ("Mystery", ["mystery", "rätsel", "mysteriös", "mistério"]),
        ("Western", ["western", "faroeste"]),
    ]

    /// Erkennt Stimmung, Art, Länge und „neu“ aus deutschen Stichwörtern; sonst Titelsuche.
    static func heuristic(_ text: String) -> SearchPlan {
        let t = text.lowercased()
        var p = SearchPlan()
        p.genres = moodWords.filter { $0.1.contains(where: t.contains) }
            .compactMap { name in Genre.all.first { $0.name == name.0 } }
        p.mediaType = mediaCue(t)
        if let m = t.range(of: #"(unter|under|menos de) (\d+) ?(min|minuten|std|stunden|hour|hora)"#, options: .regularExpression) {
            let parts = t[m].split(separator: " ")
            let n = Int(parts.first { $0.contains(where: \.isNumber) }?.filter(\.isNumber) ?? "") ?? 0
            p.maxRuntime = t[m].contains("st") || t[m].contains("h") ? n * 60 : n
        } else if lengthCue(t) && !t.contains(where: \.isNumber) { p.maxRuntime = 95 }
        if newCue(t) { p.minYear = Calendar.current.component(.year, from: Date()) - 2 }
        let understood = !p.genres.isEmpty || p.mediaType != "any" || p.maxRuntime > 0 || p.minYear > 0
        guard understood else { return titleSearch(text) }
        p.summary = p.describe()
        return p
    }

    /// Film/Serie nur, wenn es im Text steht (de/en/pt).
    static func mediaCue(_ t: String) -> String {
        if ["serie", "series", "série", "staffel", "show", "bingen", "durchschauen"].contains(where: t.contains) { return "tv" }
        if ["film", "movie"].contains(where: t.contains) { return "movie" }
        return "any"
    }
    static func isOnlyType(_ text: String) -> Bool {
        let filler: Set<String> = ["film", "filme", "filmen", "serie", "serien", "movie", "movies", "series", "série",
                                   "séries", "show", "shows", "ein", "eine", "einen", "a", "an", "um", "uma", "alle", "all",
                                   "etwas", "something", "algo"]
        let words = text.lowercased().split(separator: " ").map(String.init)
        return !words.isEmpty && words.allSatisfy(filler.contains)
    }
    static func newCue(_ t: String) -> Bool {
        ["neu", "aktuell", "new", "novo", "nova", "recente"].contains(where: t.contains)
    }
    static func lengthCue(_ t: String) -> Bool {
        t.contains(where: \.isNumber) || ["kurz", "short", "curto"].contains(where: t.contains)
    }

    func describe() -> String {
        var bits = genres.map { tr($0.name) }
        bits.append(mediaType == "tv" ? tr("Serien") : mediaType == "movie" ? tr("Filme") : tr("Filme & Serien"))
        if maxRuntime > 0 { bits.append(tr("bis %@ Min.", maxRuntime)) }
        if minYear > 0 { bits.append(tr("ab %@", minYear)) }
        if let l = language { bits.append(tr("Originalsprache %@", Self.languageName(l, country))) }
        return bits.joined(separator: " · ")
    }

    static func languageName(_ code: String, _ country: String? = nil) -> String {
        let de = Locale(identifier: L10n.ui)   // Sprachnamen in der Oberflächensprache
        let n = de.localizedString(forLanguageCode: code) ?? code
        guard let c = country, let cn = de.localizedString(forRegionCode: c) else { return n.capitalized }
        return "\(n.capitalized) (\(cn))"
    }

    /// Sprachwörter (de/en/pt) → Sprache + ggf. Land. Deutsche Adjektive in allen Endungen.
    private static let languageWords: [(words: [String], lang: String, country: String?)] = {
        func adj(_ stems: String...) -> [String] { stems.flatMap { st in ["", "e", "en", "er", "es"].map { st + $0 } } }
        return [
            (adj("brasilianisch") + ["brazilian", "brasileiro", "brasileira", "brasileiros", "brasileiras", "brasilien", "brasil", "brazil"], "pt", "BR"),
            (["portugal"], "pt", "PT"),
            (adj("portugiesisch") + ["portuguese", "português", "portugues", "portuguesa", "portugiesisch-sprachig"], "pt", nil),
            (adj("spanisch") + ["spanish", "español", "espanhol", "spanischsprachig"], "es", nil),
            (adj("französisch") + ["french", "francês", "français"], "fr", nil),
            (adj("italienisch") + ["italian", "italiano"], "it", nil),
            (adj("englisch") + ["english", "inglês", "englischsprachig"], "en", nil),
            (adj("japanisch") + ["japanese", "japonês"], "ja", nil),
            (adj("koreanisch") + ["korean", "coreano", "k-drama", "kdrama"], "ko", nil),
            (adj("türkisch") + ["turkish", "turco"], "tr", nil),
            (adj("schwedisch") + ["swedish"], "sv", nil),
            (adj("dänisch") + ["danish"], "da", nil),
            (adj("norwegisch") + ["norwegian"], "no", nil),
            (adj("polnisch") + ["polish"], "pl", nil),
            (adj("niederländisch", "holländisch") + ["dutch"], "nl", nil),
            (adj("indisch") + ["hindi", "bollywood"], "hi", nil),
            (adj("deutsch") + ["german", "alemão", "deutschsprachig"], "de", nil),
        ]
    }()
    /// Wörter rund um eine Sprachangabe, die mit ihr wegfallen („auf Portugiesisch“, „in Originalsprache“).
    private static let languageGlue: Set<String> = ["auf", "in", "im", "mit", "em", "no", "na", "originalsprache",
        "originalton", "o-ton", "omu", "ton", "sprache", "original", "language", "língua", "idioma", "audio", "áudio"]

    /// „Komödie auf Portugiesisch“, „brasilianische Serie“ → ("pt", "BR"?) + Resttext.
    static func extractLanguage(_ text: String) -> (lang: String?, country: String?, rest: String) {
        var words = text.split(separator: " ").map(String.init)
        let clean = { (w: String) in w.lowercased().trimmingCharacters(in: .punctuationCharacters.subtracting(["-"])) }
        guard let i = words.firstIndex(where: { w in languageWords.contains { $0.words.contains(clean(w)) } }),
              let hit = languageWords.first(where: { $0.words.contains(clean(words[i])) }) else {
            return (nil, nil, text)
        }
        var removed: Set<Int> = [i]
        var b = i - 1
        while b >= 0, languageGlue.contains(clean(words[b])) { removed.insert(b); b -= 1 }
        var f = i + 1
        while f < words.count, languageGlue.contains(clean(words[f])) { removed.insert(f); f += 1 }
        words = words.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
        return (hit.lang, hit.country, words.joined(separator: " "))
    }

    /// Dienstnamen in der Eingabe („Krimi auf Netflix“, „Film von HBO oder Prime“) → Dienste + Resttext.
    static let serviceWords: [String: [String]] = [
        "netflix": ["netflix"], "prime": ["prime video", "amazon prime", "prime", "amazon"],
        "disney": ["disney+", "disney plus", "disney"], "appletv": ["apple tv+", "apple tv", "appletv"],
        "wow": ["wow", "sky"], "rtlplus": ["rtl+", "rtl plus", "rtlplus"], "joyn": ["joyn"],
        "ard": ["ard"], "zdf": ["zdf"], "paramount": ["paramount+", "paramount plus", "paramount"],
        "hbomax": ["hbo max", "hbo"], "crunchyroll": ["crunchyroll"], "dazn": ["dazn"], "youtube": ["youtube"],
    ]
    /// Füllwörter rund um Dienstnamen (de/en/pt), die mit dem Namen wegfallen.
    private static let glue: Set<String> = ["auf", "bei", "von", "im", "in", "oder", "und", "on", "from", "at",
                                            "or", "and", "no", "na", "em", "ou", "e", ","]

    static func extractServices(_ text: String) -> (services: Set<String>, rest: String) {
        var words = text.replacingOccurrences(of: ",", with: " , ").split(separator: " ").map(String.init)
        var found = Set<String>()
        var removed = Set<Int>()
        var i = 0
        while i < words.count {
            var hit: (String, Int)?
            for (sid, aliases) in serviceWords {
                for a in aliases {
                    let parts = a.split(separator: " ").map(String.init)
                    guard i + parts.count <= words.count else { continue }
                    let slice = words[i..<i + parts.count].map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters.subtracting(["+"])) }
                    if slice == parts, parts.count > (hit?.1 ?? 0) { hit = (sid, parts.count) }
                }
            }
            if let (sid, n) = hit {
                found.insert(sid)
                for k in i..<i + n { removed.insert(k) }
                // Füllwörter direkt davor und danach mitnehmen
                var b = i - 1
                while b >= 0, glue.contains(words[b].lowercased()) { removed.insert(b); b -= 1 }
                var f = i + n
                while f < words.count, glue.contains(words[f].lowercased()) { removed.insert(f); f += 1 }
                i += n
            } else { i += 1 }
        }
        words = words.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
        return (found, words.joined(separator: " ").trimmingCharacters(in: .whitespaces))
    }

    static func selfTest() {
        let s1 = extractServices("Krimi auf Netflix")
        precondition(s1.services == ["netflix"] && s1.rest == "Krimi", "Dienst erkannt: \(s1)")
        let s2 = extractServices("Film von HBO oder Prime Video")
        precondition(s2.services == ["hbomax", "prime"] && s2.rest == "Film", "zwei Dienste: \(s2)")
        precondition(extractServices("Mad Max").services.isEmpty, "„Max“ im Titel ist kein Dienst")
        precondition(extractServices("La casa de papel").rest == "La casa de papel", "Titel bleibt")
        let l1 = extractLanguage("Komödie auf Portugiesisch")
        precondition(l1.lang == "pt" && l1.country == nil && l1.rest == "Komödie", "Sprache: \(l1)")
        let l2 = extractLanguage("brasilianische Serie")
        precondition(l2.lang == "pt" && l2.country == "BR" && l2.rest == "Serie", "Brasilien: \(l2)")
        let l3 = extractLanguage("Filme in Originalsprache Spanisch")
        precondition(l3.lang == "es" && l3.rest == "Filme", "Originalsprache: \(l3)")
        precondition(extractLanguage("Deutschland 83").lang == nil && extractLanguage("Cidade de Deus").lang == nil, "Titel bleibt Titel")
        precondition(languageName("pt", "BR") == "Portugiesisch (Brasilien)")
        let a = heuristic("Etwas Lustiges für heute Abend")
        precondition(a.genres.map(\.name) == ["Komödie"] && a.titleQuery.isEmpty, "lustig → Komödie")
        let b = heuristic("Spannende Serie unter 2 Stunden")
        precondition(b.mediaType == "tv" && b.maxRuntime == 120 && b.genres.map(\.name) == ["Thriller"], "Serie/Laufzeit")
        precondition(heuristic("Kurzer Film unter 90 Minuten").maxRuntime == 90, "Minuten")
        precondition(heuristic("Breaking Bad").titleQuery == "Breaking Bad", "Titel → Textsuche")
        precondition(isOnlyType("Film") && isOnlyType("eine Serie") && !isOnlyType("Film noir"))
        precondition(mediaCue("a funny movie") == "movie" && mediaCue("uma série") == "tv" && mediaCue("krimi") == "any")
    }
}

// MARK: - Apple Intelligence (läuft lokal auf dem Mac, kostenlos)

@available(macOS 26.0, *)
@Generable
struct MoodQuery {
    @Guide(description: "movie, tv oder any")
    var mediaType: String
    @Guide(description: "1 bis 3 passende Genres, nur exakt aus der erlaubten Liste")
    var genres: [String]
    @Guide(description: "Maximale Laufzeit in Minuten (bei Serien pro Folge), 0 wenn egal")
    var maxRuntime: Int
    @Guide(description: "Frühestes Erscheinungsjahr, 0 wenn egal")
    var minYear: Int
    @Guide(description: "Nur wenn ein konkreter Titel, eine Filmreihe oder eine Person gesucht wird: genau dieser Name. Sonst leer.")
    var titleQuery: String
    @Guide(description: "Sehr kurze deutsche Beschreibung der Suche, höchstens 8 Wörter")
    var summary: String
}

enum MoodAI {
    static var available: Bool {
        if #available(macOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        return false
    }

    /// Modell schon beim Öffnen der Suche laden – sonst dauert die erste Anfrage mehrere Sekunden.
    static func prewarm() {
        guard #available(macOS 26.0, *), available else { return }
        LanguageModelSession().prewarm()
    }

    /// Höchstens `timeout` Sekunden auf das Modell warten (beim ersten Laden kann es dauern), sonst nil → Stichwörter.
    static func plan(for text: String, timeout: Double) async -> SearchPlan? {
        await withTaskGroup(of: SearchPlan?.self) { g in
            g.addTask { try? await plan(for: text) }
            g.addTask { try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9)); return nil }
            let first = await g.next() ?? nil
            g.cancelAll()
            return first
        }
    }

    static func plan(for text: String) async throws -> SearchPlan {
        guard #available(macOS 26.0, *) else { return .titleSearch(text) }
        let names = Genre.all.map(\.name).joined(separator: ", ")
        let session = LanguageModelSession(instructions: """
            Du hilfst, auf dem Sofa einen Film oder eine Serie für den Moment zu finden.
            Übersetze den Wunsch in Suchfilter. Erlaubte Genres: \(names).
            Wörter wie „lustig“ → Komödie, „spannend“ → Thriller, „gruselig“ → Horror,
            „kurz“ → maxRuntime 95, „neu“ → minYear \(Calendar.current.component(.year, from: Date()) - 2).
            titleQuery nur füllen, wenn ein Name genannt wird. Titel können in jeder Sprache sein
            (Englisch, Portugiesisch, Spanisch …) – dann titleQuery = genau dieser Titel, keine Genres.
            """)
        let q = try await session.respond(to: text, generating: MoodQuery.self).content
        let genres = q.genres.compactMap { g in Genre.all.first { $0.name.lowercased() == g.lowercased() } }
        // Das Modell erfindet gern Filter („ab 2024“, „Serie“) – nur übernehmen, was im Text angelegt ist.
        let t = text.lowercased()
        var p = SearchPlan(mediaType: SearchPlan.mediaCue(t),
                           genres: genres,
                           maxRuntime: SearchPlan.lengthCue(t) ? max(0, q.maxRuntime) : 0,
                           minYear: SearchPlan.newCue(t) || t.contains(where: \.isNumber) ? max(0, q.minYear) : 0,
                           titleQuery: q.titleQuery.trimmingCharacters(in: .whitespaces))
        p.summary = p.describe()
        return p
    }
}

// MARK: - Suche im AppState

extension AppState {
    static var searchChips: [String] { [
        tr("Etwas Lustiges für heute Abend"),
        tr("Spannende Serie zum Durchschauen"),
        tr("Kurzer Film unter 90 Minuten"),
        tr("Gute Doku über die Natur"),
        tr("Etwas auf Portugiesisch"),
        tr("Gemütlich mit der Familie"),
        tr("Gruselig, aber nicht zu brutal"),
    ] }
    static let searchColumns = 6

    func openSearch() {
        MoodAI.prewarm()
        searchOpen = true
        searchInResults = false
    }

    func runSearch(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let key = tmdbKey else { sheet = .key; return }
        searchText = text
        searchToken += 1
        let token = searchToken
        let api = TMDB(key: key)
        setSearch(results: nil, status: MoodAI.available ? tr("✨ Apple Intelligence denkt nach …") : tr("Suche …"), busy: true)

        Task {
            await ensureProviders(api)
            // „… auf Netflix / bei HBO“: nur in diesen Diensten suchen (deren ganzer Katalog).
            let (named, rest0) = SearchPlan.extractServices(text)
            // „… auf Portugiesisch“: Originalsprache als Filter.
            let (lang, country, rest) = SearchPlan.extractLanguage(rest0)
            let names = named.compactMap { id in allServices.first { $0.id == id }?.name }.sorted()
            var plan = rest.isEmpty ? SearchPlan(summary: tr("Alles")) : SearchPlan.heuristic(rest)
            // Nur „Film“/„Serie“ übrig („Film von HBO“): kein Modell, sonst erfindet es Genres.
            let onlyType = SearchPlan.isOnlyType(rest)
            if onlyType { plan = SearchPlan(mediaType: SearchPlan.mediaCue(rest.lowercased())); plan.summary = plan.describe() }
            var ai = false
            if !rest.isEmpty, !onlyType, MoodAI.available, let p = await MoodAI.plan(for: rest, timeout: 3) { plan = p; ai = true }
            if let lang {
                plan.language = lang
                plan.country = country
                if rest.isEmpty || plan.titleQuery.isEmpty { plan.summary = plan.describe() }
            }
            // Nichts als Stimmung erkannt → als Titel suchen (in jeder Sprache).
            let mood = !plan.genres.isEmpty || plan.mediaType != "any" || plan.maxRuntime > 0 || plan.minYear > 0
            if !rest.isEmpty, plan.titleQuery.isEmpty, !mood { plan.titleQuery = rest }

            var found: [Title] = []
            var status = plan.summary
            do {
                if !plan.titleQuery.isEmpty {
                    found = try await searchTitles(api, plan.titleQuery, in: named)
                    if let lang { found = found.filter { $0.lang == lang } }
                    let mine = named.isEmpty ? found.filter { onMyServices($0, enabledIDs) }.count : found.count
                    status = tr("Titel „%@“", plan.titleQuery) + (names.isEmpty ? tr(" · %@ bei deinen Diensten", mine) : tr(" · bei %@", names.joined(separator: tr(" oder "))))
                } else {
                    let only = named.isEmpty ? enabledIDs : named
                    found = try await discover(api, plan, services: only)
                    if found.isEmpty && named.isEmpty { found = try await discover(api, plan, services: nil) }
                    if !names.isEmpty { status += tr(" · bei %@", names.joined(separator: tr(" oder "))) }
                }
            } catch {
                guard token == searchToken else { return }
                setSearch(results: [], status: tr("Suche fehlgeschlagen – Internet/TMDB-Schlüssel prüfen"), busy: false)
                return
            }
            guard token == searchToken else { return }
            if found.isEmpty {
                status = names.isEmpty ? tr("Nichts gefunden – anders formulieren?") : tr("Nichts bei %@ gefunden", names.joined(separator: tr(" oder ")))
            } else if ai { status = "✨ " + status }
            setSearch(results: found, status: status, busy: false)
            searchInResults = !found.isEmpty
            searchIndex = 0
        }
    }

    private func onMyServices(_ t: Title, _ services: Set<String>) -> Bool {
        guard let ids = providerCache[t.key] else { return false }
        let mine = Set(Providers.ids(for: services))
        return !mine.isDisjoint(with: ids)
    }

    /// Titelsuche in der ganzen TMDB-Datenbank – TMDB vergleicht mit Original-, übersetzten und
    /// alternativen Titeln, daher klappt „Money Heist“, „La casa de papel“ und „Haus des Geldes“.
    /// Mit genannten Diensten: nur Titel, die dort laufen. Sonst: deine Dienste zuerst.
    private func searchTitles(_ api: TMDB, _ query: String, in named: Set<String>) async throws -> [Title] {
        async let p1 = api.list("/search/multi", ["query": query, "page": "1"])
        async let p2 = api.list("/search/multi", ["query": query, "page": "2"])
        var all = try await p1
        all += (try? await p2) ?? []
        var seen = Set<String>()
        all = all.filter { seen.insert($0.key).inserted }
        // ponytail: Verfügbarkeit nur für die ersten 30 Treffer – reicht für eine Titelsuche.
        let check = Array(all.prefix(30)).filter { providerCache[$0.key] == nil }
        await withTaskGroup(of: (String, [String: [Int]]?).self) { g in
            for t in check { g.addTask { (t.key, try? await api.providers(t)) } }
            for await (k, ids) in g { if let ids { cacheProviders(k, ids) } }
        }
        if !named.isEmpty { return all.filter { onMyServices($0, named) } }
        let mine = all.filter { onMyServices($0, enabledIDs) }
        return mine + all.filter { !onMyServices($0, enabledIDs) }
    }

    private func discover(_ api: TMDB, _ plan: SearchPlan, services: Set<String>?) async throws -> [Title] {
        // Mit Diensten: je Land ihres Kontos eine Abfrage; ohne: ganzer Katalog im Heimatland.
        var bases = discoverBases(only: services)
        if services == nil { bases = bases.filter { $0["watch_region"] == country }.map { $0.merging(["with_watch_providers": ""]) { $1 } } }
        if bases.isEmpty { bases = discoverBases(only: []) }
        // Bei 1–2 Genres alle verlangen („lustiger Krimi“), bei mehr reicht eins davon.
        func genres(_ ids: [Int]) -> String { ids.map(String.init).joined(separator: ids.count <= 2 ? "," : "|") }
        // Sprach-Suchen („auf Portugiesisch“): auch wenig bewertete Titel – sonst fehlen viele Serien aus kleineren Märkten.
        var common = ["vote_count.gte": plan.language != nil ? "3" : "30"]
        if let l = plan.language { common["with_original_language"] = l }
        if let c = plan.country { common["with_origin_country"] = c }
        if plan.maxRuntime > 0 { common["with_runtime.lte"] = String(plan.maxRuntime) }

        var movies: [Title] = [], shows: [Title] = []
        if plan.mediaType != "tv" {
            var q = common
            q["with_genres"] = genres(plan.genres.compactMap(\.movie))
            if plan.minYear > 0 { q["primary_release_date.gte"] = "\(plan.minYear)-01-01" }
            for base in bases { movies = interleave(movies, try await twoPages(api, "/discover/movie", AppState.query(base, q), type: "movie")) }
        }
        if plan.mediaType != "movie" {
            var q = common
            q["with_genres"] = genres(Array(Set(plan.genres.compactMap(\.tv))))
            if plan.minYear > 0 { q["first_air_date.gte"] = "\(plan.minYear)-01-01" }
            for base in bases { shows = interleave(shows, try await twoPages(api, "/discover/tv", AppState.query(base, q), type: "tv")) }
        }
        return taste.rank(interleave(movies, shows))
    }

    /// Zwei Seiten (40 Titel) statt einer – mehr Auswahl aus dem Katalog.
    private func twoPages(_ api: TMDB, _ path: String, _ q: [String: String], type: String) async throws -> [Title] {
        let q2 = q.merging(["page": "2"]) { $1 }
        async let a = api.list(path, q, type: type)
        async let b = api.list(path, q2, type: type)
        return try await a + ((try? await b) ?? [])
    }

    func handleSearch(_ e: PadEvent) {
        let n = searchResults.count, c = AppState.searchColumns
        if handleBack(e, close: { searchOpen = false }) {
            if !backFocus && searchOpen && (e == .down || e == .right) { searchOnField = true }
            return
        }
        // Eingabefeld: A öffnet die Bildschirmtastatur, ↑ zu „Zurück“, ↓ zu den Vorschlägen.
        if searchOnField {
            switch e {
            case .up: searchOnField = false; backFocus = true
            case .down: searchOnField = false
            case .a:
                searchFocusRequest += 1
                KeyboardController.shared.show()
            case .x: runSearch(searchText)
            case .b: searchOpen = false
            default: break
            }
            return
        }
        if !searchInResults {
            switch e {
            case .up: searchOnField = true
            case .left: searchChip = max(searchChip - 1, 0)
            case .right: searchChip = min(searchChip + 1, AppState.searchChips.count - 1)
            case .down: if n > 0 { searchInResults = true; searchIndex = min(searchIndex, n - 1) }
            case .a: runSearch(AppState.searchChips[searchChip])
            case .x: runSearch(searchText)
            case .b: searchOpen = false
            default: break
            }
            return
        }
        switch e {
        case .left: searchIndex = max(searchIndex - 1, 0)
        case .right: searchIndex = min(searchIndex + 1, n - 1)
        case .up: if searchIndex < c { searchInResults = false } else { searchIndex -= c }
        case .down: searchIndex = min(searchIndex + c, n - 1)
        case .a: if searchResults.indices.contains(searchIndex) { openDetail(searchResults[searchIndex]) }
        case .b: searchInResults = false
        default: break
        }
    }
}

// MARK: - Suchbildschirm

struct SearchOverlay: View {
    @EnvironmentObject var state: AppState
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            ThemedBackground().opacity(0.98).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                BackButton(focused: state.backFocus) { state.searchOpen = false }
                HStack(spacing: 14) {
                    Image(systemName: "sparkle.magnifyingglass").font(.ui(26, weight: .semibold))
                    TextField(tr("Was möchtest du schauen? z. B. „spannender Thriller unter 2 Stunden“"),
                              text: $state.searchText)
                        .textFieldStyle(.plain)
                        .font(.ui(24, weight: .medium))
                        .focused($fieldFocused)
                        .onSubmit { state.runSearch(state.searchText) }
                    if state.searching { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 22).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Ink.fg.opacity(state.searchOnField ? 0.2 : 0.1)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(state.theme.bold ? state.theme.p.accent : Ink.fg, lineWidth: 3)
                    .opacity(state.searchOnField ? 1 : 0))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(AppState.searchChips.enumerated()), id: \.offset) { i, chip in
                            let focused = !state.searchInResults && i == state.searchChip
                            Text(chip)
                                .font(.ui(16, weight: .semibold))
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(Capsule().fill(Ink.fg.opacity(focused ? 0.9 : 0.1)))
                                .foregroundColor(focused ? Ink.bg : Ink.fg)
                                .scaleEffect(focused && !Typo.calm ? 1.06 : 1)
                                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: focused)
                                .onTapGesture { state.searchChip = i; state.runSearch(chip) }
                        }
                    }
                    .padding(.vertical, 8).padding(.horizontal, 4)
                }

                if let s = state.searchStatus {
                    Text(s).font(.ui(16, weight: .medium)).dimText(0.65)
                }

                FocusScroll(axis: .vertical,
                            target: state.searchResults.indices.contains(state.searchIndex) && state.searchInResults
                                ? state.searchResults[state.searchIndex].key : nil,
                            position: 0.4, space: "search", wheel: state.detail == nil) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Metrics.posterW), spacing: 22),
                                                 count: AppState.searchColumns), spacing: 26) {
                            ForEach(Array(state.searchResults.enumerated()), id: \.element.key) { i, t in
                                PosterCard(title: t, focused: state.searchInResults && i == state.searchIndex,
                                           liked: state.taste.liked.contains(t.key))
                                    .scrollAnchor(t.key, in: "search")
                                    .onTapGesture { state.searchIndex = i; state.openDetail(t) }
                            }
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                }

                FlowLayout(spacing: 22, lineSpacing: 8, centered: false) {
                    if state.inputMode == .keyboard {
                        KeyboardHints()
                    } else {
                        Hint(glyph: .symbol("l.joystick.press.down.fill"), text: tr("Tastatur & 🎤 Sprache"))
                        Hint(glyph: .letter("A", .green), text: state.backFocus ? tr("Zurück")
                             : state.searchOnField ? tr("Tippen") : state.searchInResults ? tr("Details") : tr("Vorschlag suchen"))
                        if !state.searchInResults && !state.backFocus { Hint(glyph: .letter("X", .blue), text: tr("Eingabe suchen")) }
                        Hint(glyph: .letter("B", .red), text: tr("Zurück"))
                    }
                    // (Quelle steht als letzter Eintrag in der Zeile)
                    Text(MoodAI.available ? tr("✨ Apple Intelligence · Daten: TMDB") : tr("Daten: TMDB"))
                        .dimText(0.4)
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
        .onAppear { fieldFocused = true }
        .onChange(of: state.searchFocusRequest) { _ in fieldFocused = true }
    }
}
