import SwiftUI

// MARK: - Unsere Watchlist: alle Merklisten der Profile zusammen, gemeinsam Gemerktes zuerst

struct HouseholdItem: Identifiable {
    let title: Title
    let who: [Profile]
    var id: String { title.key }
}

enum Household {
    /// Jeder Titel einmal, mit allen Profilen, die ihn gemerkt haben; stabil nach Anzahl (absteigend) sortiert.
    static func merge(_ profiles: [Profile]) -> [HouseholdItem] {
        var order: [String] = [], titles: [String: Title] = [:], who: [String: [Profile]] = [:]
        for p in profiles {
            for t in p.watchlist {
                if titles[t.key] == nil { order.append(t.key); titles[t.key] = t }
                if !(who[t.key]?.contains { $0.id == p.id } ?? false) { who[t.key, default: []].append(p) }
            }
        }
        let items = order.map { HouseholdItem(title: titles[$0]!, who: who[$0] ?? []) }
        return items.enumerated().sorted { ($0.element.who.count, -$0.offset) > ($1.element.who.count, -$1.offset) }.map(\.element)
    }

    static func selfTest() {
        func t(_ id: Int) -> Title { Title(id: id, type: "movie", name: "\(id)", overview: "", poster: nil, backdrop: nil, genres: [], rating: 0, year: "") }
        var a = Profile(name: "Anna", color: 0), b = Profile(name: "Ben", color: 1)
        a.watchlist = [t(1), t(2)]; b.watchlist = [t(3), t(2)]
        let m = merge([a, b])
        precondition(m.map(\.title.id) == [2, 1, 3] && m[0].who.map(\.name) == ["Anna", "Ben"], "Gemeinsames zuerst, sonst Reihenfolge")
        print("✓ Unsere Watchlist")
    }
}

extension AppState {
    /// Alle Profile – das aktive mit seiner aktuellen Merkliste (die Liste im Profil wird erst beim Speichern aktualisiert).
    var household: [HouseholdItem] {
        Household.merge(profiles.map { p in
            var p = p
            if p.id == activeProfileID { p.watchlist = watchlist }
            return p
        })
    }

    /// Reihen der Ansicht: gemeinsam gemerkt, dann einzeln (ausgeblendet bei „Nur gemeinsame“).
    var oursRows: [(title: String, items: [HouseholdItem])] {
        let all = household
        var rows = [(tr("Gemeinsam ausgewählt"), all.filter { $0.who.count >= 2 })]
        if !sharedOnly { rows.append((tr("Einzeln gemerkt"), all.filter { $0.who.count < 2 })) }
        return rows.filter { !$0.1.isEmpty }
    }

    var focusedOurs: HouseholdItem? {
        let rows = oursRows
        guard oursRow >= 0, rows.indices.contains(oursRow), rows[oursRow].items.indices.contains(oursIndex) else { return nil }
        return rows[oursRow].items[oursIndex]
    }

    func openOurs() {
        oursOpen = true
        oursRow = oursRows.isEmpty ? -1 : 0
        oursIndex = 0
    }

    func toggleSharedOnly() {
        sharedOnly.toggle()
        UserDefaults.standard.set(sharedOnly, forKey: "sharedOnly")
        oursIndex = 0
        oursRow = oursRows.isEmpty ? -1 : 0
    }

    /// Oben: Zurück (backFocus) und Schalter (oursRow == -1); darunter die Reihen.
    func handleOurs(_ e: PadEvent) {
        if handleBack(e, close: { oursOpen = false }) { return }
        let rows = oursRows
        if oursRow < 0 {
            switch e {
            case .up, .left: backFocus = true
            case .down: if !rows.isEmpty { oursRow = 0; oursIndex = min(oursIndex, rows[0].items.count - 1) }
            case .a: toggleSharedOnly(); oursRow = -1
            case .b: oursOpen = false
            default: break
            }
            return
        }
        guard rows.indices.contains(oursRow) else { oursRow = -1; return }
        let n = rows[oursRow].items.count
        switch e {
        case .left: oursIndex = max(oursIndex - 1, 0)
        case .right: oursIndex = min(oursIndex + 1, n - 1)
        case .up: if oursRow == 0 { oursRow = -1 } else { oursRow -= 1; oursIndex = min(oursIndex, rows[oursRow].items.count - 1) }
        case .down: if oursRow + 1 < rows.count { oursRow += 1; oursIndex = min(oursIndex, rows[oursRow].items.count - 1) }
        case .a: if let i = focusedOurs { openDetail(i.title) }
        case .x: if let i = focusedOurs { like(i.title) }
        case .y: if let i = focusedOurs { dislike(i.title) }
        case .b: oursOpen = false
        default: break
        }
    }
}

/// Runde Initialen in Profilfarbe – wer den Titel gemerkt hat.
struct WhoBadges: View {
    let who: [Profile]
    var body: some View {
        HStack(spacing: -6) {
            ForEach(who) { p in
                Text(p.initial)
                    .font(.ui(13, weight: .heavy, design: .rounded))
                    .foregroundColor(Pop.textOn(p.hex))
                    .frame(width: 26 * Metrics.text(13), height: 26 * Metrics.text(13))
                    .background(Circle().fill(Color(hex: p.hex)))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            }
        }
        .padding(6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Gemerkt von %@", who.map(\.name).joined(separator: ", ")))
    }
}

struct OursOverlay: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        let rows = state.oursRows
        ZStack(alignment: .topLeading) {
            ThemedBackground().opacity(0.98).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18 * Metrics.s) {
                BackButton(focused: state.backFocus) { state.oursOpen = false }
                HStack(spacing: 18) {
                    Text(tr("Unsere Watchlist")).headingFont(34).popTextShadow()
                    sharedSwitch
                    Spacer()
                }
                if rows.isEmpty {
                    Text(tr(state.sharedOnly && !state.household.isEmpty ? "Noch kein Titel, den mehrere gemerkt haben."
                                                                          : "Noch nichts gemerkt – auf der Detailseite „Auf die Watchlist“."))
                        .font(.read(19)).dimText(0.85).padding(.top, 30)
                    Spacer()
                } else {
                    FocusScroll(axis: .vertical, target: "r\(max(state.oursRow, 0))", position: 0.3, space: "ours", wheel: state.detail == nil) {
                        VStack(alignment: .leading, spacing: 26 * Metrics.s) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(row.title).headingFont(24)
                                    posterRow(r, row.items)
                                }
                                .scrollAnchor("r\(r)", in: "ours")
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    if let i = state.focusedOurs { TitleDetail(title: i.title) }
                }
                FlowLayout(spacing: 22, lineSpacing: 8, centered: false) {
                    if state.inputMode == .keyboard {
                        KeyboardHints()
                    } else {
                        Hint(glyph: .letter("A", .green), text: state.oursRow < 0 ? tr("An/Aus") : tr("Ansehen"))
                        Hint(glyph: .letter("X", .blue), text: tr("Gefällt mir"))
                        Hint(glyph: .letter("Y", .yellow), text: tr("Nicht mein Fall"))
                        Hint(glyph: .letter("B", .red), text: tr("Zurück"))
                    }
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

    /// Zwei Zustände → Schalter.
    private var sharedSwitch: some View {
        let focused = !state.backFocus && state.oursRow < 0
        return HStack(spacing: 10) {
            Text(tr("Nur gemeinsame")).font(.read(17, weight: .semibold))
            Toggle("", isOn: Binding(get: { state.sharedOnly }, set: { _ in state.toggleSharedOnly() }))
                .toggleStyle(.switch).labelsHidden().allowsHitTesting(false)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(Ink.fg.opacity(focused ? 0.18 : 0.1)))
        .overlay(Capsule().strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: 3).padding(-5).opacity(focused ? 1 : 0))
        .contentShape(Rectangle())
        .onTapGesture { state.toggleSharedOnly(); state.oursRow = -1 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(state.sharedOnly ? tr("An") : tr("Aus"))
    }

    private func posterRow(_ r: Int, _ items: [HouseholdItem]) -> some View {
        FocusScroll(axis: .horizontal, target: state.oursRow == r ? items[safe: state.oursIndex]?.id : nil,
                    position: 0.4, space: "ours-\(r)") {
            HStack(spacing: 22) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    PosterCard(title: item.title, focused: state.oursRow == r && state.oursIndex == i,
                               liked: state.taste.liked.contains(item.title.key))
                        .overlay(alignment: .topLeading) { WhoBadges(who: item.who) }
                        .scrollAnchor(item.id, in: "ours-\(r)")
                        .onTapGesture { state.oursRow = r; state.oursIndex = i; state.openDetail(item.title) }
                }
            }
            .padding(.vertical, 20).padding(.horizontal, 12)
        }
        .frame(height: Metrics.cardH * 1.15 + 40)
    }
}
