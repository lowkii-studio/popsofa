import SwiftUI
import AppKit

/// Pflichttext der TMDB-API-Bedingungen (https://www.themoviedb.org/api-terms-of-use, Abschnitt 3) – bewusst nicht übersetzt.
enum Attribution {
    static let tmdb = "This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB."
    static let providers = "Streaming availability data provided by JustWatch via TMDB."
    /// TMDB-Logo aus dem App-Bundle (nil beim Start ohne Bundle, z. B. `swift run`).
    static let logo: NSImage? = Bundle.main.url(forResource: "tmdb-logo", withExtension: "png").flatMap(NSImage.init(contentsOf:))
}

@main
struct PopSofaApp: App {
    @StateObject private var state = AppState()

    init() {
        Typo.register()
        let args = CommandLine.arguments
        // Test der Profilwahl: `--pick <Browser-Bundle-ID> <Name>` – sucht/klickt im vorderen Fenster, dann Ende.
        if let i = args.firstIndex(of: "--pick"), i + 2 < args.count {
            StreamProfile.pick(bundleID: args[i + 1], name: args[i + 2])
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { exit(0) }
        }
        if args.contains("--selftest") { RemoteProto.selfTest(); Taste.selfTest(); TextSize.selfTest(); Metrics.selfTest(); DistanceCamera.selfTest(); UISound.selfTest(); Category.selfTest(); BrowserZoom.selfTest(); StreamProfile.selfTest(); Profile.selfTest(); DisplayFilter.selfTest(); ColorTestResult.selfTest(); Region.selfTest(); Household.selfTest(); L10n.selfTest(); exit(0) }
        // KI-Suche testen: PopSofa --ai "was Lustiges, kurz"
        if let i = args.firstIndex(of: "--ai"), i + 1 < args.count {
            let text = args[i + 1]
            Task.detached {
                print("KI verfügbar:", MoodAI.available)
                do { print(try await MoodAI.plan(for: text)) } catch { print("Fehler:", error) }
                exit(0)
            }
            RunLoop.main.run()
        }
    }

    var body: some Scene {
        WindowGroup("PopSofa") {
            LauncherView()
                .environmentObject(state)
                .frame(minWidth: 1000, minHeight: 640)
                .onAppear {
                    // Beim Start im Vollbild öffnen – wie ein Fernseher-Home-Bildschirm.
                    DispatchQueue.main.async {
                        if let w = NSApp.windows.first(where: { $0.canBecomeMain }),
                           !w.styleMask.contains(.fullScreen) {
                            w.toggleFullScreen(nil)
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(tr("Über PopSofa")) {
                    let text = tr("Ein Experiment von lowkii studio. Open Source unter MIT-Lizenz.") + "\n\n" + Attribution.tmdb + "\n" + Attribution.providers
                    let credits = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11)])
                    if let logo = Attribution.logo {
                        let a = NSTextAttachment()
                        a.image = logo
                        a.bounds = CGRect(x: 0, y: 0, width: 80, height: 80 * logo.size.height / max(logo.size.width, 1))
                        credits.append(NSAttributedString(string: "\n\n"))
                        credits.append(NSAttributedString(attachment: a))
                    }
                    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            CommandGroup(after: .appSettings) {
                Button(tr("iPhone koppeln …")) { state.sheet = .remote }
            }
        }
    }
}
