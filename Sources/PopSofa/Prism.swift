import SwiftUI

// MARK: - Prismen-Check: Prismengläser zerlegen helle Kanten auf dunklem Grund in farbige Säume.
// Wer das sieht (oder Prismen trägt), bekommt den hellen Stil „Pop hell (Prismen)“ – dunkle Schrift auf hellem Grund.

extension AppState {
    func startPrismTest() {
        formFocus = 0
        backFocus = false
        sheet = .prism
    }

    func handlePrism(_ e: PadEvent) {
        if handleBack(e, close: { choosePrism(false) }) { return }
        switch e {
        case .left, .right: formFocus = formFocus == 0 ? 1 : 0
        case .up: backFocus = true
        case .a: choosePrism(formFocus == 0)
        case .b: choosePrism(false)   // „Später“: nichts ändern
        default: break
        }
    }

    /// Ja → heller Stil; danach in der Einrichtung weiter zum Farbtest, sonst zurück zur Barrierefreiheit.
    func choosePrism(_ yes: Bool) {
        if yes && theme != .popLight {
            themeBeforeClear = theme
            setTheme(.popLight)
            showToast(tr("Stil: %@", Theme.popLight.title))
        }
        if setupFlow { startColorTest() } else { sheet = .access }
    }
}

struct PrismPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        OverlayPage(title: tr("Prismen-Check"),
                    step: state.setupFlow ? tr("Schritt %@ von %@", 4, 6) : nil,
                    intro: tr("Trägst du eine Brille mit Prismen? Prismengläser zeigen an hellen Kanten auf dunklem Grund oft rote und blaue Säume. Schau dir beide Felder an."),
                    close: { state.choosePrism(false) },
                    hints: state.backFocus ? [("A", tr("Zurück"))] : [("dpad", tr("Auswahl")), ("A", tr("Auswählen")), ("B", tr("Später"))]) {
            VStack(alignment: .leading, spacing: 26 * Metrics.s) {
                HStack(spacing: 24 * Metrics.s) {
                    sample(bg: .black, fg: .white)
                    sample(bg: Color(hex: Pop.popLight.bgHex), fg: Color(hex: Pop.inkHexLight))
                }
                Text(tr("Siehst du links farbige Ränder oder Doppelkanten – oder liest du rechts entspannter?"))
                    .font(.read(20, weight: .semibold))
                HStack(spacing: 18) {
                    pill(tr("Ja – helles Design nehmen"), 0) { state.choosePrism(true) }
                    pill(tr("Nein – so lassen"), 1) { state.choosePrism(false) }
                }
            }
        }
    }

    /// Feine Linien und Schrift – an genau solchen Kanten entstehen Prismen-Säume.
    private func sample(bg: Color, fg: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PopSofa").font(.system(size: 44 * Metrics.s, weight: .heavy))
            Text(tr("Zwei Schwestern erben ein Strandhotel in Lissabon – und mit ihm ein Geheimnis aus den Siebzigern."))
                .font(.system(size: 20 * Metrics.s, weight: .medium)).lineLimit(3)
            HStack(spacing: 8) { ForEach(0..<9, id: \.self) { _ in Rectangle().frame(width: 2, height: 40 * Metrics.s) } }
        }
        .foregroundColor(fg)
        .padding(24 * Metrics.s)
        .frame(maxWidth: 520 * Metrics.s, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(bg))
    }

    private func pill(_ text: String, _ i: Int, action: @escaping () -> Void) -> some View {
        let on = !state.backFocus && state.formFocus == i
        return Button(action: action) {
            Text(text).font(.read(20, weight: .bold)).lineLimit(1).fixedSize()
                .padding(.horizontal, 26).padding(.vertical, 14)
                .foregroundColor(on ? Ink.bg : Ink.fg)
                .background(Capsule().fill(on ? (theme.bold ? theme.p.accent : Ink.fg) : Ink.fg.opacity(0.12)))
                .overlay(Capsule().strokeBorder(theme.bold ? theme.p.accent : Ink.fg, lineWidth: 3).padding(-6).opacity(on ? 1 : 0))
        }
        .buttonStyle(.plain)
    }
}
