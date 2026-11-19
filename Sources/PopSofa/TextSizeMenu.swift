import SwiftUI

/// Runder Knopf in der Kopfzeile – per Controller fokussierbar (von der obersten Kachelreihe nach oben).
struct HeaderButton<Label: View>: View {
    @Environment(\.theme) private var theme
    let focused: Bool
    var active = false
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: 40 * Metrics.s, height: 40 * Metrics.s)   // gleicher Innenraum für alle Symbole
                .foregroundColor(focused && theme.bold ? Ink.bg : (focused || active ? Ink.fg : Ink.fg.opacity(0.7)))
                .frame(width: 48 * Metrics.s, height: 48 * Metrics.s)
                .background(Circle().fill(focused ? (theme.bold ? theme.p.accent : Ink.fg.opacity(0.35))
                                                  : Ink.fg.opacity(active ? 0.18 : 0.08)))
                .overlay(Circle().strokeBorder(focused ? (theme.bold ? Ink.bg : Ink.fg) : .clear,
                                               lineWidth: theme.bold ? 3 : 2))
                .scaleEffect(focused && !Typo.calm ? 1.15 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: focused)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// „Aa“ öffnet das Textgrößen-Menü.
struct TextSizeButton: View {
    @EnvironmentObject var state: AppState
    let focused: Bool
    let action: () -> Void

    var body: some View {
        HeaderButton(focused: focused, active: state.textMenu, help: tr("Textgröße: %@", state.textSizeLabel), action: action) {
            Text("Aa").font(.ui(20, weight: .bold, design: .rounded))
        }
    }
}

/// Auswahlliste wie ein Menü: vier Stufen mit Häkchen und „Aa“-Vorschau, abgetrennt die Kamera-Messung.
struct TextSizeMenu: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("Anzeige & Ton")).font(.ui(15, weight: .semibold)).opacity(0.6)
                .padding(.horizontal, 14).padding(.bottom, 4)
            ForEach(Array(TextSize.allCases.enumerated()), id: \.element) { i, t in
                row(i) {
                    Image(systemName: "checkmark").font(.ui(15, weight: .bold))
                        .opacity(state.textSize == t ? 1 : 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t == .auto ? "Auto" : t.title).font(.ui(18, weight: .semibold))
                        if t == .auto {
                            Text(autoDetail).font(.ui(15)).opacity(0.7)
                        }
                    }
                    Spacer(minLength: 20)
                    Text("Aa").font(.system(size: 20 * t.preview, weight: .bold, design: .rounded))
                }
            }
            Divider().overlay(Ink.fg.opacity(0.2)).padding(.vertical, 6)
            row(TextSize.allCases.count) {
                Image(systemName: "camera.viewfinder").font(.ui(18, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Abstand mit Kamera messen")).font(.ui(18, weight: .semibold))
                    Text(tr("Kamera ca. 3 s an, keine Bilder gespeichert")).font(.ui(15)).opacity(0.7)
                }
            }
            row(TextSize.allCases.count + 1) {
                Image(systemName: "accessibility").font(.ui(18, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Barrierefreiheit …")).font(.ui(18, weight: .semibold))
                    Text(tr("Stil „Klar“, Farbsehen anpassen und testen")).font(.ui(15)).opacity(0.7)
                }
            }
            Divider().overlay(Ink.fg.opacity(0.2)).padding(.vertical, 6)
            row(TextSize.allCases.count + 2) {
                Image(systemName: state.soundsOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.ui(18, weight: .semibold)).frame(width: 26 * Metrics.s)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Bedientöne")).font(.ui(18, weight: .semibold))
                    Text(tr("Leise Klänge passend zum Stil")).font(.ui(15)).opacity(0.7)
                }
                Spacer(minLength: 20)
                Toggle("", isOn: $state.soundsOn).toggleStyle(.switch).labelsHidden()
                    .allowsHitTesting(false)       // Zeile selbst schaltet (auch per Controller)
            }
        }
        .padding(12)
        .frame(width: 400 * Metrics.text(18))   // Breite folgt der Schrift, nicht den Flächen
        .themedCard(radius: 20, focused: false, fill: theme.bold ? theme.p.paper : Ink.panel.opacity(0.97))
        .foregroundColor(theme.bold ? Ink.bg : Ink.fg)
    }

    private var autoDetail: String {
        let d = TextSize.screenInfo
        let measured = (!d.builtIn && state.activeProfile?.distance != nil)
            || UserDefaults.standard.double(forKey: TextSize.distanceKey(builtIn: d.builtIn)) > 0
        let m = state.currentDistance / 1000
        return String(format: tr("nach Bildschirm, %@ %.1f m"), tr(measured ? "gemessen" : "angenommen"), m)
    }

    private func row<C: View>(_ i: Int, @ViewBuilder _ content: () -> C) -> some View {
        let focused = state.textMenuFocus == i
        return HStack(spacing: 12) { content() }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(focused ? (theme.bold ? theme.p.accent : Ink.fg.opacity(0.18)) : .clear))
            .contentShape(Rectangle())
            .onTapGesture { state.chooseTextMenu(i) }
    }
}

/// Pinsel-Knopf ganz links in der Kopfzeile: öffnet die Stil-Auswahl.
struct ThemeButton: View {
    @EnvironmentObject var state: AppState
    let focused: Bool
    let action: () -> Void

    var body: some View {
        HeaderButton(focused: focused, active: state.themeMenu, help: tr("Stil: %@", state.theme.title), action: action) {
            Image(systemName: "paintpalette.fill").font(.ui(20, weight: .semibold))
        }
    }
}

/// Stil-Auswahl als Menü mit Farbvorschau; der Stil wechselt sofort beim Durchgehen.
struct ThemeMenu: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("Stil")).font(.ui(15, weight: .semibold)).opacity(0.6)
                .padding(.horizontal, 14).padding(.bottom, 4)
            ForEach(Theme.allCases, id: \.self) { t in
                let on = state.theme == t
                HStack(spacing: 12) {
                    Image(systemName: "checkmark").font(.ui(15, weight: .bold)).opacity(on ? 1 : 0)
                    Text(t.title).font(.ui(18, weight: .semibold))
                    Spacer(minLength: 20)
                    HStack(spacing: 4) {
                        ForEach(swatch(t), id: \.self) { Circle().fill(Color(hex: $0)).frame(width: 16 * Metrics.s, height: 16 * Metrics.s) }
                    }
                    .padding(4)
                    .background(Capsule().fill(Ink.bg.opacity(0.25)))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(on ? (theme.bold ? theme.p.accent : Ink.fg.opacity(0.18)) : .clear))
                .contentShape(Rectangle())
                .onTapGesture { state.setTheme(t) }
                .accessibilityLabel(tr("Stil %@", t.title) + (on ? ", " + tr("ausgewählt") : ""))
            }
        }
        .padding(12)
        .frame(width: 340 * Metrics.text(18))
        .themedCard(radius: 20, focused: false, fill: theme.bold ? theme.p.paper : Ink.panel.opacity(0.97))
        .foregroundColor(theme.bold ? Ink.bg : Ink.fg)
    }

    private func swatch(_ t: Theme) -> [String] {
        if t == .clear { return ["#1E2024", "#3A3D42", "#C9C6C0", "#EBEAE6"] }
        if t == .clearLight { return ["#E2D6C2", "#C9BBA3", "#5C5A55", "#1A1A1A"] }
        return t.bold ? [t.p.bgHex, t.p.accentHex] + Array(t.p.tiles.prefix(2)) : ["#1C1C1E", "#3A3A3C", "#8E8E93", "#FFFFFF"]
    }
}
