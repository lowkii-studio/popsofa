import Foundation
import Security

// MARK: - Titel (Film oder Serie)

struct Title: Codable, Identifiable, Hashable {
    var id: Int
    var type: String            // "movie" oder "tv"
    var name: String
    var overview: String
    var poster: String?
    var backdrop: String?
    var genres: [Int]
    var rating: Double
    var year: String
    var original: String? = nil         // Originaltitel (z. B. „La casa de papel“)
    var votes: Int? = nil               // Anzahl TMDB-Stimmen (fehlt bei alten Merklisten-Einträgen)
    var lang: String? = nil             // Originalsprache (ISO 639-1)

    /// Bewertung, gewichtet mit der Zahl der Stimmen (Bayes-Mittel wie bei der IMDb-Top-250):
    /// 9,5 aus 12 Stimmen zählt weniger als 8,1 aus 20.000.
    var quality: Double {
        guard rating > 0 else { return Self.prior }
        let m = type == "tv" ? 200.0 : 500.0
        let v = Double(votes ?? Int(m))   // unbekannt → halbes Vertrauen
        return (v * rating + m * Self.prior) / (v + m)
    }
    static let prior = 6.8   // ponytail: grober TMDB-Durchschnitt; bei Bedarf aus echten Daten schätzen

    var key: String { "\(type)-\(id)" }
    var posterURL: URL? { poster.flatMap { URL(string: "https://image.tmdb.org/t/p/w342\($0)") } }
    var backdropURL: URL? { backdrop.flatMap { URL(string: "https://image.tmdb.org/t/p/w1280\($0)") } }
}

struct ProviderOption: Identifiable, Hashable {
    let id: Int
    let name: String
    let logo: String?
    let kind: String            // „Im Abo“, „Leihen“, …
    var logoURL: URL? { logo.flatMap { URL(string: "https://image.tmdb.org/t/p/w92\($0)") } }
    var serviceID: String? { Providers.byService.first { $0.value.contains(id) }?.key }
}

struct TitleDetails {
    var runtime: Int?
    var seasons: Int?
    var genres: [String]
    var tagline: String
    var cast: [String]
    var providers: [ProviderOption]
    var link: URL?               // TMDB-Seite mit allen Anbietern
    var trailer: String?         // YouTube-Video-ID

    var trailerURL: URL? { trailer.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") } }

    /// Bester Trailer: YouTube, „Trailer“ vor „Teaser“, Deutsch vor Englisch, offiziell bevorzugt.
    static func pickTrailer(_ videos: [(key: String, site: String, type: String, lang: String?, official: Bool)]) -> String? {
        videos.filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
            .min { a, b in
                func rank(_ v: (key: String, site: String, type: String, lang: String?, official: Bool)) -> Int {
                    (v.type == "Trailer" ? 0 : 4) + (v.lang == "de" ? 0 : 2) + (v.official ? 0 : 1)
                }
                return rank(a) < rank(b)
            }?.key
    }
}

struct PosterRow: Identifiable {
    var id: String
    var title: String
    var items: [Title]
    var sources: [RowSource] = []      // für „Alle anzeigen“ (weitere TMDB-Seiten)
}

/// Eine TMDB-Liste, aus der eine Reihe stammt – für weitere Seiten.
struct RowSource: Sendable {
    let path: String
    let query: [String: String]
    let type: String
}

// MARK: - Genres (TMDB hat getrennte IDs für Filme und Serien)

struct Genre: Identifiable {
    let name: String
    let movie: Int?
    let tv: Int?
    var id: String { name }
    var ids: [Int] { [movie, tv].compactMap { $0 } }

    static let all: [Genre] = [
        Genre(name: "Action", movie: 28, tv: 10759),
        Genre(name: "Abenteuer", movie: 12, tv: 10759),
        Genre(name: "Animation", movie: 16, tv: 16),
        Genre(name: "Komödie", movie: 35, tv: 35),
        Genre(name: "Krimi", movie: 80, tv: 80),
        Genre(name: "Doku", movie: 99, tv: 99),
        Genre(name: "Drama", movie: 18, tv: 18),
        Genre(name: "Familie", movie: 10751, tv: 10751),
        Genre(name: "Fantasy", movie: 14, tv: 10765),
        Genre(name: "Science-Fiction", movie: 878, tv: 10765),
        Genre(name: "Horror", movie: 27, tv: nil),
        Genre(name: "Mystery", movie: 9648, tv: 9648),
        Genre(name: "Thriller", movie: 53, tv: nil),
        Genre(name: "Romantik", movie: 10749, tv: nil),
        Genre(name: "Krieg & Politik", movie: 10752, tv: 10768),
        Genre(name: "Western", movie: 37, tv: 37),
    ]
    static let movieIDs = Set(all.compactMap(\.movie))
    static let tvIDs = Set(all.compactMap(\.tv))
}

// MARK: - Geschmack (bleibt lokal auf dem Mac)

struct Taste: Codable {
    var picked: Set<Int> = []           // Genre-IDs aus der Auswahl
    var weights: [Int: Double] = [:]    // durch 👍/👎 gelernt
    var liked: Set<String> = []
    var disliked: Set<String> = []
    var lastLiked: Title?
    var onboarded = false

    /// Gewählt = eigene Film-Kennung gewählt. Nicht über die Serien-Kennung prüfen: TMDB fasst bei Serien
    /// Genres zusammen (Action & Abenteuer = 10759, Sci-Fi & Fantasy = 10765) – sonst wäre das andere „mitgewählt“.
    func isPicked(_ g: Genre) -> Bool { picked.contains(g.movie ?? g.tv ?? -1) }

    mutating func toggle(_ g: Genre) {
        if isPicked(g) {
            if let m = g.movie { picked.remove(m) }
            // Gemeinsame Serien-Kennung nur entfernen, wenn kein anderes gewähltes Genre sie braucht.
            if let t = g.tv, !Genre.all.contains(where: { $0.id != g.id && $0.tv == t && isPicked($0) }) { picked.remove(t) }
        } else {
            g.ids.forEach { picked.insert($0) }
        }
    }

    mutating func like(_ t: Title) {
        liked.insert(t.key); disliked.remove(t.key)
        for g in t.genres { weights[g, default: 0] += 1 }
        lastLiked = t
    }

    mutating func dislike(_ t: Title) {
        disliked.insert(t.key); liked.remove(t.key)
        for g in t.genres { weights[g, default: 0] -= 1 }
        if lastLiked?.key == t.key { lastLiked = nil }
    }

    func weight(_ g: Int) -> Double { (picked.contains(g) ? 3 : 0) + weights[g, default: 0] }

    // ponytail: Genre-Gewichtung + stimmen-gewichtete Bewertung; bei Bedarf später durch ein echtes Modell ersetzen.
    /// Genre-Vorliebe ist gedeckelt, damit ein Lieblingsgenre nicht alles andere verdrängt.
    func score(_ t: Title) -> Double {
        let affinity = min(max(t.genres.reduce(0) { $0 + weight($1) }, -4), 6)
        return 0.75 * affinity + 3 * (t.quality - 5) / 3
    }

    /// Wie `rank`, aber abwechslungsreich (MMR): Ein Titel, der genre-mäßig den letzten drei ähnelt,
    /// rutscht nach hinten – statt fünf Krimis am Stück.
    func diversify(_ list: [Title]) -> [Title] {
        var pool = rank(list), out: [Title] = []
        func sim(_ a: Title, _ b: Title) -> Double {
            let x = Set(a.genres), y = Set(b.genres)
            return x.isEmpty || y.isEmpty ? 0 : Double(x.intersection(y).count) / Double(x.union(y).count)
        }
        while !pool.isEmpty {
            let recent = out.suffix(3)
            let mmr = { (t: Title) in score(t) - 2 * (recent.map { sim(t, $0) }.max() ?? 0) }
            let i = pool.indices.max { mmr(pool[$0]) < mmr(pool[$1]) }!   // bei Gleichstand der vordere
            out.append(pool.remove(at: i))
        }
        return out
    }

    /// Überraschungen in eine Liste mischen: jeder `every`-te Platz.
    static func sprinkle(_ list: [Title], _ extra: [Title], every: Int = 5) -> [Title] {
        var out: [Title] = [], ex = extra.filter { e in !list.contains { $0.key == e.key } }[...]
        for (i, t) in list.enumerated() {
            out.append(t)
            if (i + 1) % (every - 1) == 0, let e = ex.popFirst() { out.append(e) }
        }
        return out
    }

    func rank(_ list: [Title]) -> [Title] {
        var seen = Set<String>()
        return list.filter { !disliked.contains($0.key) && seen.insert($0.key).inserted }
            .sorted { score($0) > score($1) }
    }

    func topGenres(in domain: Set<Int>, count: Int = 3) -> [Int] {
        domain.map { ($0, weight($0)) }.filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }.prefix(count).map(\.0)
    }

    /// Selbsttest: `PopSofa.app/Contents/MacOS/PopSofa --selftest`
    static func selfTest() {
        do {   // Action wählen darf Abenteuer nicht mitwählen; Abwählen lässt die gemeinsame Serien-Kennung stehen
            var t = Taste()
            let action = Genre.all[0], adventure = Genre.all[1]
            t.toggle(action)
            precondition(t.isPicked(action) && !t.isPicked(adventure), "Action wählt Abenteuer mit")
            t.toggle(adventure); t.toggle(action)
            precondition(!t.isPicked(action) && t.isPicked(adventure) && t.picked.contains(10759), "Serien-Genre fehlt")
        }
        let scifi = Title(id: 1, type: "movie", name: "A", overview: "", genres: [878], rating: 7, year: "")
        let comedy = Title(id: 2, type: "movie", name: "B", overview: "", genres: [35], rating: 9, year: "")
        var t = Taste()
        precondition(t.rank([scifi, comedy]).first == comedy, "ohne Geschmack zählt die Bewertung")
        t.like(scifi); t.like(scifi)
        precondition(t.rank([comedy, scifi]).first == scifi, "👍 hebt das Genre")
        t.dislike(comedy)
        precondition(!t.rank([comedy, scifi]).contains(comedy), "👎 filtert den Titel")
        t.toggle(Genre.all[3])
        precondition(t.topGenres(in: Genre.movieIDs).contains(35), "Genre-Auswahl zählt")
        precondition(t.rank([scifi, scifi]).count == 1, "Duplikate entfernt")
        var few = comedy; few.rating = 9.5; few.votes = 12
        var many = comedy; many.id = 3; many.rating = 8.1; many.votes = 20000
        precondition(many.quality > few.quality, "Stimmen zählen")
        var crime = (0..<4).map { Title(id: 10 + $0, type: "movie", name: "", overview: "", genres: [80], rating: 8, year: "") }
        crime.append(Title(id: 20, type: "movie", name: "", overview: "", genres: [99], rating: 7, year: ""))
        let mixed = Taste().diversify(crime)
        precondition(mixed.firstIndex { $0.id == 20 }! <= 2, "Vielfalt: Doku rutscht nach vorn")
        precondition(Taste.sprinkle(crime, [scifi]).count == 6 && Taste.sprinkle(crime, [scifi])[4] == scifi, "Überraschung auf Platz 5")
        precondition(Providers.matches("ARD Mediathek", "ard") && !Providers.matches("Arte", "ard"), "ARD-Abgleich")
        precondition(Providers.matches("WOW", "=wow") && !Providers.matches("WOW Presents Plus", "=wow"), "WOW exakt")
        precondition(Providers.matches("Netflix basic with Ads", "netflix"), "Netflix-Varianten")
        let vids: [(key: String, site: String, type: String, lang: String?, official: Bool)] = [
            ("teaserDE", "YouTube", "Teaser", "de", true), ("trailerEN", "YouTube", "Trailer", "en", true),
            ("trailerDE", "YouTube", "Trailer", "de", false), ("vimeo", "Vimeo", "Trailer", "de", true)]
        precondition(TitleDetails.pickTrailer(vids) == "trailerDE", "deutscher Trailer zuerst")
        SearchPlan.selfTest()
        FocusScrollMath.selfTest()
        Contrast.selfTest()
        print("Selbsttest OK")
    }
}

// MARK: - Zuordnung TMDB-Anbieter → PopSofa-Kachel

enum Providers {
    // Startwerte; beim ersten Laden ersetzt `learn` sie durch die echten IDs aus TMDB (Abgleich per Name).
    static var byService: [String: [Int]] = [
        "netflix": [8, 1796], "prime": [9, 119, 2100], "disney": [337], "appletv": [350, 2],
        "wow": [30], "rtlplus": [298], "joyn": [304], "ard": [219], "zdf": [537],
        "paramount": [531, 582], "hbomax": [1899, 384], "crunchyroll": [283], "youtube": [188],
    ]
    /// Länder, deren Anbieterliste schon gelernt ist.
    static var learnedRegions = Set<String>()

    // Namensanfänge der TMDB-Anbieter je Kachel; „=“ heißt exakter Name.
    static let nameKeys: [String: [String]] = [
        "netflix": ["netflix"], "prime": ["amazon prime video"], "disney": ["disney plus", "disney+"],
        "appletv": ["apple tv plus", "apple tv+"], "wow": ["=wow"], "rtlplus": ["rtl+", "rtl plus"],
        "joyn": ["joyn"], "ard": ["ard"], "zdf": ["zdf"], "paramount": ["paramount"],
        "hbomax": ["=max", "hbo max"], "crunchyroll": ["crunchyroll"], "youtube": ["youtube"],
        "dazn": ["dazn"],
    ]

    static func matches(_ name: String, _ key: String) -> Bool {
        let n = name.lowercased()
        if key.hasPrefix("=") { return n == key.dropFirst() }
        return n == key || n.hasPrefix(key + " ") || n.hasPrefix(key + "+")
    }

    static func learn(_ catalog: [(id: Int, name: String)]) {
        var map: [String: [Int]] = [:]
        for (sid, keys) in nameKeys {
            let ids = catalog.filter { p in keys.contains { matches(p.name, $0) } }.map(\.id)
            if !ids.isEmpty { map[sid] = Array(Set(ids)).sorted() }
        }
        guard !map.isEmpty else { return }
        byService = map
    }

    // Direkt zur Suche nach dem Titel springen; ohne Eintrag öffnet sich die Startseite.
    static let search: [String: String] = [
        "netflix": "https://www.netflix.com/search?q=",
        "prime": "https://www.primevideo.com/search?phrase=",
        "disney": "https://www.disneyplus.com/search?q=",
        "appletv": "https://tv.apple.com/search?term=",
        "youtube": "https://www.youtube.com/results?search_query=",
        "zdf": "https://www.zdf.de/suche?q=",
        "ard": "https://www.ardmediathek.de/suche/",
        "crunchyroll": "https://www.crunchyroll.com/search?q=",
    ]

    static func ids(for services: Set<String>) -> [Int] {
        services.flatMap { byService[$0] ?? [] }.sorted()
    }

    static func service(for providerIDs: [Int], preferring enabled: Set<String>) -> String? {
        let matches = byService.filter { !Set($0.value).isDisjoint(with: providerIDs) }.map(\.key)
        return matches.first(where: enabled.contains) ?? matches.first
    }

    static func searchURL(service: String, title: String) -> URL? {
        guard let base = search[service],
              let q = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "&?=/+")))
        else { return nil }
        return URL(string: base + q)
    }
}

// MARK: - TMDB-Client

struct TMDB {
    let key: String
    /// Sprache für Titel und Beschreibungen – pro Profil (siehe `AppState.contentLanguage`).
    nonisolated(unsafe) static var language = "de-DE"

    enum Failure: Error { case status(Int) }

    private struct Page: Decodable { let results: [Raw] }
    private struct Raw: Decodable {
        let id: Int
        let mediaType: String?
        let title: String?, name: String?
        let originalTitle: String?, originalName: String?
        let overview: String?
        let posterPath: String?, backdropPath: String?
        let genreIds: [Int]?
        let voteAverage: Double?
        let voteCount: Int?
        let originalLanguage: String?
        let releaseDate: String?, firstAirDate: String?
    }
    private struct ProviderResponse: Decodable {
        struct Region: Decodable {
            let link: String?
            let flatrate: [Entry]?, free: [Entry]?, ads: [Entry]?, rent: [Entry]?, buy: [Entry]?
        }
        struct Entry: Decodable { let providerId: Int; let providerName: String?; let logoPath: String? }
        let results: [String: Region]
    }

    private struct DetailsRaw: Decodable {
        struct Named: Decodable { let name: String }
        struct Credits: Decodable { let cast: [Named] }
        let runtime: Int?
        let numberOfSeasons: Int?
        let episodeRunTime: [Int]?
        let genres: [Named]?
        let tagline: String?
        let credits: Credits?
        let watchProviders: ProviderResponse?
        struct Videos: Decodable {
            struct V: Decodable { let key: String; let site: String; let type: String; let iso6391: String?; let official: Bool? }
            let results: [V]
        }
        let videos: Videos?
        enum CodingKeys: String, CodingKey {
            case runtime, numberOfSeasons, episodeRunTime, genres, tagline, credits, videos
            case watchProviders = "watch/providers"
        }
    }

    private struct ProviderList: Decodable { let results: [ProviderResponse.Entry] }

    /// Alle Anbieter in einem Land (Filme + Serien).
    func providerCatalog(_ region: String) async throws -> [(id: Int, name: String)] {
        async let m: ProviderList = get("/watch/providers/movie", ["watch_region": region])
        async let t: ProviderList = get("/watch/providers/tv", ["watch_region": region])
        return try await (m.results + t.results).map { ($0.providerId, $0.providerName ?? "") }
    }

    /// Details inkl. Anbietern – ein einziger Aufruf. Liste aus dem Heimatland; dazu die eigenen Dienste
    /// aus anderen Ländern (`extra`: Land → erlaubte Anbieter-IDs), z. B. „HBO Max (PT)“.
    func details(_ t: Title, home: String = "DE", extra: [String: Set<Int>] = [:]) async throws -> TitleDetails {
        let lang = String(TMDB.language.prefix(2))
        let r: DetailsRaw = try await get("/\(t.type)/\(t.id)", ["append_to_response": "watch/providers,credits,videos",
                                                                "include_video_language": "\(lang),en,null"])
        let de = r.watchProviders?.results[home]
        var seen = Set<Int>()
        var options: [ProviderOption] = []
        let kinds: [(String, [ProviderResponse.Entry]?)] = [
            ("Im Abo", de?.flatrate), ("Kostenlos", de?.free), ("Mit Werbung", de?.ads),
            ("Leihen", de?.rent), ("Kaufen", de?.buy),
        ]
        // Eigene Dienste aus anderen Ländern zuerst prüfen – im Heimatland zählen sie dann nicht.
        let abroad = extra.values.reduce(Set<Int>()) { $0.union($1) }
        for (region, ids) in extra.sorted(by: { $0.key < $1.key }) {
            let reg = r.watchProviders?.results[region]
            for e in (reg?.flatrate ?? []) + (reg?.free ?? []) + (reg?.ads ?? []) where ids.contains(e.providerId) {
                guard seen.insert(e.providerId).inserted else { continue }
                options.append(ProviderOption(id: e.providerId, name: "\(e.providerName ?? "Anbieter") (\(region))",
                                              logo: e.logoPath, kind: "Im Abo"))
            }
        }
        for (kind, list) in kinds {
            for e in list ?? [] where !abroad.contains(e.providerId) && seen.insert(e.providerId).inserted {
                options.append(ProviderOption(id: e.providerId, name: e.providerName ?? "Anbieter",
                                              logo: e.logoPath, kind: kind))
            }
        }
        return TitleDetails(
            runtime: r.runtime ?? r.episodeRunTime?.first,
            seasons: r.numberOfSeasons,
            genres: (r.genres ?? []).map(\.name),
            tagline: r.tagline ?? "",
            cast: (r.credits?.cast ?? []).prefix(5).map(\.name),
            providers: options,
            link: de?.link.flatMap(URL.init(string:)),
            trailer: TitleDetails.pickTrailer((r.videos?.results ?? []).map {
                ($0.key, $0.site, $0.type, $0.iso6391, $0.official ?? false)
            }))
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        var c = URLComponents(string: "https://api.themoviedb.org/3" + path)!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "language", value: TMDB.language))
        var req = URLRequest(url: c.url!)
        // Neuer „Read Access Token“ (enthält Punkte) per Header, alter API-Key per Parameter.
        if key.contains(".") {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        } else {
            items.append(URLQueryItem(name: "api_key", value: key))
        }
        c.queryItems = items
        req.url = c.url
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.status(code) }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: data)
    }

    func list(_ path: String, _ query: [String: String] = [:], type: String? = nil) async throws -> [Title] {
        let page: Page = try await get(path, query)
        return page.results.compactMap { r in
            let t = r.mediaType ?? type ?? "movie"
            guard t == "movie" || t == "tv", let n = r.title ?? r.name, r.posterPath != nil else { return nil }
            return Title(id: r.id, type: t, name: n, overview: r.overview ?? "",
                         poster: r.posterPath, backdrop: r.backdropPath, genres: r.genreIds ?? [],
                         rating: r.voteAverage ?? 0,
                         year: String((r.releaseDate ?? r.firstAirDate ?? "").prefix(4)),
                         original: r.originalTitle ?? r.originalName, votes: r.voteCount,
                         lang: r.originalLanguage)
        }
    }

    /// Im Abo/kostenlos verfügbare Anbieter je Land.
    func providers(_ t: Title) async throws -> [String: [Int]] {
        let r: ProviderResponse = try await get("/\(t.type)/\(t.id)/watch/providers", [:])
        return r.results.mapValues { ((($0.flatrate ?? []) + ($0.free ?? []) + ($0.ads ?? [])).map(\.providerId)) }
    }
}

// MARK: - Schlüssel im Schlüsselbund

enum Keychain {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.couchkino.tmdb",
        kSecAttrAccount as String: "tmdb",
    ]

    static func get() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ value: String) {
        SecItemDelete(base as CFDictionary)
        var q = base
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}
