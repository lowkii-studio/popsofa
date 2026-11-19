import SwiftUI
import WebKit

/// Eingebauter Browser für Dienste ohne Kopierschutz (YouTube, Mediatheken, eigene Seiten …).
/// Logins bleiben erhalten (Standard-Datenspeicher von WebKit).
struct WebBrowserView: NSViewRepresentable {
    let url: URL
    @EnvironmentObject var state: AppState

    func makeNSView(context: Context) -> CouchWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.preferences.isElementFullscreenEnabled = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        let web = CouchWebView(frame: .zero, configuration: cfg)
        // Wie Safari auftreten, damit die Seiten die volle Desktop-Version liefern.
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        web.allowsBackForwardNavigationGestures = true
        web.pageZoom = Metrics.s   // gleiche Vergrößerung wie die App (Sitzabstand)
        web.uiDelegate = context.coordinator
        web.load(URLRequest(url: url))
        state.webView = web
        DispatchQueue.main.async { web.window?.makeFirstResponder(web) }
        // Runterscrollen blendet die Leiste aus, Hochscrollen wieder ein (wie Safari auf dem iPhone).
        let state = self.state
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { ev in
            let dy = ev.scrollingDeltaY * (ev.hasPreciseScrollingDeltas ? 1 : 10)
            if abs(dy) > abs(ev.scrollingDeltaX), abs(dy) > 4 {
                let show = dy > 0
                if state.webBarVisible != show { withAnimation(.easeInOut(duration: 0.2)) { state.webBarVisible = show } }
            }
            return ev
        }
        return web
    }

    func updateNSView(_ nsView: CouchWebView, context: Context) {}

    static func dismantleNSView(_ nsView: CouchWebView, coordinator: Coordinator) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKUIDelegate {
        var monitor: Any?
        // Links mit target="_blank" im selben Fenster öffnen statt ins Leere.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let u = navigationAction.request.url { webView.load(URLRequest(url: u)) }
            return nil
        }
    }
}

final class CouchWebView: WKWebView {
    /// ⌘[ = zurück, ⌘] = vor (B im Maus-Modus sendet ⌘[). Keycode statt Zeichen, weil QWERTZ dort „ü“ liefert.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            if event.keyCode == 33 { goBack(); return true }
            if event.keyCode == 30 { goForward(); return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}
