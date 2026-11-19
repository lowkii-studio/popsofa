import SwiftUI

/// Auswahlliste statt Knöpfen, die bei jedem Druck den Wert weiterschalten: zeigt alle Möglichkeiten auf einmal.
/// Controller/Tastatur: ↑↓ wählen, A/↩ übernimmt, B/Esc bricht ab. Maus: Zeile anklicken, daneben klicken schließt.
struct ChoicePrompt {
    struct Option { let id: String; let label: String; var detail: String? = nil }
    var title: String
    var options: [Option]
    var selected: String
    var focus: Int
    var pick: (String) -> Void
}

extension AppState {
    func ask(_ title: String, _ options: [ChoicePrompt.Option], selected: String, pick: @escaping (String) -> Void) {
        choice = ChoicePrompt(title: title, options: options, selected: selected,
                              focus: options.firstIndex { $0.id == selected } ?? 0, pick: pick)
    }

    func choose(_ i: Int) {
        guard let c = choice, c.options.indices.contains(i) else { return }
        choice = nil
        c.pick(c.options[i].id)
    }

    func handleChoice(_ e: PadEvent) {
        guard var c = choice else { return }
        switch e {
        case .up: c.focus = max(c.focus - 1, 0); choice = c
        case .down: c.focus = min(c.focus + 1, c.options.count - 1); choice = c
        case .a: choose(c.focus)
        case .b: choice = nil
        default: break
        }
    }

    // MARK: Auswahlen, die vorher per Knopfdruck weitergeschaltet wurden

    func chooseLanguage() {
        ask(tr("Sprache"), Region.languages.map { .init(id: $0, label: Region.languageName($0)) }, selected: contentLanguage) { l in
            self.contentLanguage = l
            self.persist(); self.resetAvailability(); self.reloadRecommendations()
        }
    }

    func chooseCountry() {
        ask(tr("Streaming-Land"), Region.all.map { .init(id: $0, label: "\(Region.flag($0))  \(Region.name($0))") }, selected: country) { c in
            self.country = c
            self.serviceCountries = self.serviceCountries.filter { $0.value != c }
            self.persist()
        }
    }

    /// Land des Kontos für einen Dienst; erste Zeile = wie das Heimatland.
    func chooseServiceCountry(_ s: Service) {
        guard enabledIDs.contains(s.id), multiCountry else { return }
        // Nur Länder – vorbelegt mit dem bisherigen Streaming-Land.
        let all = Region.all.map { ChoicePrompt.Option(id: $0, label: "\(Region.flag($0))  \(Region.name($0))") }
        ask(tr("Land des Kontos: %@", s.name), all, selected: region(s.id)) { c in
            self.serviceCountries[s.id] = c
            self.persist()
        }
    }

    func chooseReadableStyle() {
        let opts: [ChoicePrompt.Option] = [
            .init(id: "off", label: tr("Aus"), detail: tr("Dein gewählter Stil")),
            .init(id: Theme.clear.rawValue, label: Theme.clear.title, detail: tr("Dunkel, ruhig, gedämpftes Weiß")),
            .init(id: Theme.clearLight.rawValue, label: Theme.clearLight.title, detail: tr("Hell und warm, abends gedimmt")),
            .init(id: Theme.popLight.rawValue, label: Theme.popLight.title, detail: tr("Pop-Art hell, ruhig hinter Text")),
        ]
        ask(tr("Lesbarkeits-Stil"), opts, selected: theme.isClear ? theme.rawValue : "off") { id in
            if let t = Theme(rawValue: id) {
                if !self.theme.isClear { self.themeBeforeClear = self.theme }
                self.setTheme(t)
            } else if self.theme.isClear {
                self.setTheme(self.themeBeforeClear ?? .apple)
            }
        }
    }

    func chooseContrast() {
        ask(tr("Kontrast"), ClearContrast.allCases.map { .init(id: $0.rawValue, label: tr($0.title)) }, selected: clearContrast.rawValue) { id in
            if let c = ClearContrast(rawValue: id) { self.clearContrast = c }
        }
    }

    func chooseCategorySort() {
        guard let c = category else { return }
        ask(tr("Sortierung"), Category.Sort.allCases.map { .init(id: $0.rawValue, label: tr($0.rawValue)) }, selected: c.sort.rawValue) { id in
            if let s = Category.Sort(rawValue: id) { self.setCategorySort(s) }
        }
    }
}

/// Mittiges Auswahlfeld über allem.
struct ChoiceOverlay: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme
    let prompt: ChoicePrompt

    var body: some View {
        ZStack {
            Ink.bg.opacity(0.5).ignoresSafeArea().onTapGesture { state.choice = nil }
            VStack(alignment: .leading, spacing: 6) {
                Text(prompt.title).headingFont(26).padding(.horizontal, 14).padding(.bottom, 6)
                FocusScroll(axis: .vertical, target: "c\(prompt.focus)", position: 0.5, space: "choice", wheel: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(prompt.options.enumerated()), id: \.offset) { i, o in row(i, o) }
                    }
                }
                .frame(height: min(CGFloat(prompt.options.count) * 58 * Metrics.text(19), 560 * Metrics.text(19)))
                FlowLayout(spacing: 18, lineSpacing: 6, centered: false) {
                    Hint(glyph: .symbol("dpad"), text: tr("Auswahl"))
                    Hint(glyph: .letter("A", .green), text: tr("Auswählen"))
                    Hint(glyph: .letter("B", .red), text: tr("Abbrechen"))
                }
                .font(.read(14, weight: .medium))
                .padding(.horizontal, 14).padding(.top, 8)
            }
            .padding(16)
            .frame(width: 520 * Metrics.text(19))
            .themedCard(radius: 22, focused: false, fill: theme.bold ? theme.p.paper : Ink.panel.opacity(0.98))
            .foregroundColor(theme.bold ? Ink.bg : Ink.fg)
        }
        .transition(.opacity)
    }

    private func row(_ i: Int, _ o: ChoicePrompt.Option) -> some View {
        let on = prompt.focus == i, picked = o.id == prompt.selected
        return HStack(spacing: 12) {
            Image(systemName: picked ? "largecircle.fill.circle" : "circle").font(.ui(20, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(o.label).font(.read(19, weight: picked ? .bold : .semibold))
                if let d = o.detail { Text(d).font(.read(14)).opacity(0.8) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(on ? (theme.bold ? theme.p.accent : Ink.fg.opacity(0.16)) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.bold ? Ink.bg : Ink.fg, lineWidth: 3).opacity(on ? 1 : 0))
        .contentShape(Rectangle())
        .onTapGesture { state.choose(i) }
        .scrollAnchor("c\(i)", in: "choice")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }
}
