import Foundation

/// Länder für Konten: Heimatland pro Profil, auf Wunsch abweichend pro Dienst (z. B. HBO Max aus Portugal).
enum Region {
    static let all = ["DE", "PT", "AT", "CH", "ES", "FR", "IT", "NL", "GB", "US", "BR"]

    static func name(_ c: String) -> String {
        tr(["DE": "Deutschland", "PT": "Portugal", "AT": "Österreich", "CH": "Schweiz", "ES": "Spanien",
         "FR": "Frankreich", "IT": "Italien", "NL": "Niederlande", "GB": "Großbritannien", "US": "USA",
         "BR": "Brasilien"][c] ?? c)
    }

    /// Flagge aus den Regional-Indicator-Zeichen (🇩🇪, 🇵🇹 …).
    static func flag(_ c: String) -> String {
        String(String.UnicodeScalarView(c.uppercased().unicodeScalars.compactMap { Unicode.Scalar(127397 + $0.value) }))
    }

    /// Sprache für Titel und Beschreibungen (TMDB) passend zum Land.
    static func language(_ c: String) -> String {
        ["DE": "de-DE", "AT": "de-AT", "CH": "de-CH", "PT": "pt-PT", "BR": "pt-BR", "ES": "es-ES",
         "FR": "fr-FR", "IT": "it-IT", "NL": "nl-NL", "GB": "en-GB", "US": "en-US"][c] ?? "de-DE"
    }

    static func next(_ c: String) -> String { all[((all.firstIndex(of: c) ?? -1) + 1) % all.count] }

    /// Sprachen für Oberfläche, Titel und Beschreibungen (Oberfläche nur de/pt/en, Rest → Englisch).
    static let languages = ["de", "pt", "en", "es", "fr", "it", "nl"]
    static func languageName(_ l: String) -> String {
        ["de": "Deutsch", "pt": "Português", "en": "English", "es": "Español", "fr": "Français",
         "it": "Italiano", "nl": "Nederlands"][l] ?? l
    }
    /// Sprache passend zum Land (Voreinstellung).
    static func defaultLanguage(_ c: String) -> String { String(language(c).prefix(2)) }
    /// TMDB-Sprachcode: Sprache + Landesvariante, wenn sie passt (pt + BR → pt-BR).
    static func tmdb(language l: String, country c: String) -> String {
        defaultLanguage(c) == l ? language(c) : ["de": "de-DE", "pt": "pt-PT", "en": "en-US", "es": "es-ES",
                                                 "fr": "fr-FR", "it": "it-IT", "nl": "nl-NL"][l] ?? "de-DE"
    }

    /// Anbieter-IDs, die für dieses Profil „bei deinen Diensten“ zählen bzw. angezeigt werden:
    /// - eigene Dienste nur im Land ihres Kontos,
    /// - alles andere (fremde Dienste, für „Läuft bei …“) aus dem Heimatland.
    static func combine(_ results: [String: [Int]], home: String,
                        serviceRegion: [String: String], byService: [String: [Int]]) -> [Int] {
        var out = Set<Int>()
        // Heimatland: alles, außer Dienste, deren Konto in einem anderen Land liegt.
        let elsewhere = Set(serviceRegion.filter { $0.value != home }.flatMap { byService[$0.key] ?? [] })
        for id in results[home] ?? [] where !elsewhere.contains(id) { out.insert(id) }
        // Andere Länder: nur die eigenen Dienste, die dort ihr Konto haben.
        for (sid, r) in serviceRegion where r != home {
            let ids = Set(byService[sid] ?? [])
            for id in results[r] ?? [] where ids.contains(id) { out.insert(id) }
        }
        return out.sorted()
    }

    static func selfTest() {
        let by = ["prime": [9], "hbomax": [1899], "netflix": [8]]
        // A: Prime in DE, HBO aus PT. Titel läuft bei HBO nur in DE → zählt nicht; bei HBO in PT → zählt.
        let mine = ["prime": "DE", "hbomax": "PT"]
        precondition(combine(["DE": [1899]], home: "DE", serviceRegion: mine, byService: by).isEmpty, "HBO DE zählt nicht")
        precondition(combine(["PT": [1899]], home: "DE", serviceRegion: mine, byService: by) == [1899], "HBO PT zählt")
        precondition(combine(["PT": [9]], home: "DE", serviceRegion: mine, byService: by).isEmpty, "Prime PT zählt nicht")
        precondition(combine(["DE": [9, 8]], home: "DE", serviceRegion: mine, byService: by) == [8, 9], "Heimatland zeigt alles andere")
        precondition(flag("PT") == "🇵🇹" && language("PT") == "pt-PT" && next("BR") == "DE")
        print("✓ Länder")
    }
}
