import SwiftUI
import AppKit

/// Intro (~2 s): Das PopSofa-App-Icon ploppt herein, wackelt wie beim „POP!“ und gibt den Startbildschirm frei.
/// Dazu der Start-Klang des Stils. Jede Eingabe überspringt es.
struct SplashView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.theme) private var theme
    @State private var phase = 0          // 0 = unsichtbar, 1 = hereingeploppt, 2 = „POP!“-Stoß, 3 = Schriftzug
    @State private var ring = false

    private static let icon = NSImage(named: "AppIcon") ?? Bundle.main.image(forResource: "AppIcon")

    var body: some View {
        ZStack {
            ThemedBackground().ignoresSafeArea()

            // Druckwelle hinter dem Icon (Comic-Ring, im Webmuster-Stil gold, sonst Akzent/weiß)
            Circle()
                .strokeBorder(theme.bold ? theme.p.accent : Ink.fg.opacity(0.6), lineWidth: 10 * Metrics.s)
                .frame(width: 300 * Metrics.s, height: 300 * Metrics.s)
                .scaleEffect(ring ? 2.4 : 0.6)
                .opacity(ring ? 0 : 0.9)

            VStack(spacing: 26 * Metrics.s) {
                iconView
                    .frame(width: 300 * Metrics.s, height: 300 * Metrics.s)
                    .shadow(color: Ink.bg.opacity(0.45), radius: 30, y: 18)
                    .scaleEffect(phase == 0 ? 0.15 : (phase == 2 ? 1.12 : 1))
                    .rotationEffect(.degrees(phase == 0 ? -25 : (phase == 2 ? 4 : 0)))
                    .opacity(phase == 0 ? 0 : 1)

                Text("PopSofa")
                    .headingFont(64)
                    .foregroundColor(theme.bold ? theme.accentText : Ink.fg)
                    .popTextShadow()
                    .opacity(phase >= 3 ? 1 : 0)
                    .offset(y: phase >= 3 ? 0 : 16)
            }
        }
        .onAppear(perform: run)
    }

    /// Icon ohne den dunklen Rand der Bilddatei: auf das abgerundete Quadrat zugeschnitten.
    @ViewBuilder private var iconView: some View {
        if let img = Self.icon {
            GeometryReader { g in
                Image(nsImage: img).resizable().interpolation(.high)
                    .frame(width: g.size.width / 0.805, height: g.size.height / 0.805)
                    .position(x: g.size.width / 2, y: g.size.height / 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 300 * Metrics.s * 0.2, style: .continuous))
        } else {
            Image(systemName: "sofa.fill").resizable().scaledToFit().foregroundColor(Ink.fg)
        }
    }

    private func run() {
        UISound.shared.play(.start, theme: theme)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { phase = 1 }
        after(0.42) {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { phase = 2 }
            withAnimation(.easeOut(duration: 0.7)) { ring = true }
        }
        after(0.62) { withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { phase = 3 } }
        after(1.9) { withAnimation(.easeOut(duration: 0.4)) { state.splash = false } }
    }

    private func after(_ s: Double, _ f: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f)
    }
}
