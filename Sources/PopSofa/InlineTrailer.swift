import SwiftUI
import WebKit

/// YouTube-Trailer direkt in der Detailansicht. Startet per Autoplay; greift WebKit das nicht,
/// klickt PopSofa einmal selbst in die Mitte des Players.
struct InlineTrailerView: NSViewRepresentable {
    let videoID: String
    var onReady: (Coordinator) -> Void = { _ in }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.preferences.isElementFullscreenEnabled = true
        let script = """
        (function () {
          if (location.host.indexOf('youtube') < 0) return;
          var post = function (m) { try { window.webkit.messageHandlers.trailer.postMessage(m); } catch (e) {} };
          var last = null;
          setInterval(function () {
            // „Werbung überspringen“ klicken, sobald YouTube den Knopf anbietet (blockiert keine Werbung).
            document.querySelectorAll('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern')
              .forEach(function (b) { b.click(); });
            var mp = document.querySelector('#movie_player');
            var s = document.querySelector('.ytp-error') ? 'error'
                  : (mp && mp.getPlayerState) ? String(mp.getPlayerState()) : null;
            s = s === null ? null : s + (document.visibilityState === 'hidden' ? ' hidden' : '');
            if (s !== null && s !== last) { last = s; post('state:' + s); }
          }, 400);
        })();
        """
        cfg.userContentController.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        cfg.userContentController.add(context.coordinator, name: "trailer")

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.web = web
        // Player direkt als Seite laden; der Referer verhindert YouTubes Fehler 153.
        let url = URL(string: "https://www.youtube-nocookie.com/embed/\(videoID)?autoplay=1&playsinline=1&rel=0&modestbranding=1&iv_load_policy=3")!
        var req = URLRequest(url: url)
        req.setValue("https://couchkino.app/", forHTTPHeaderField: "Referer")
        web.load(req)
        onReady(context.coordinator)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.loadHTMLString("", baseURL: nil)   // Ton sofort stoppen
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "trailer")
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var web: WKWebView?
        private(set) var state = "none"        // YouTube: -1 bereit, 1 läuft, 2 Pause, 0 Ende, 5 geladen
        private var kicked = false
        var isPlaying: Bool { state.hasPrefix("1") || state.hasPrefix("3") }

        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String, body.hasPrefix("state:") else { return }
            state = String(body.dropFirst(6))
            if Debug.on { print("trailer:", state) }
            // Bereit, aber nach 1,5 s noch nicht gestartet → einmal selbst anklicken.
            if (state == "-1" || state == "5"), !kicked {
                kicked = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self, !self.isPlaying else { return }
                    self.click()
                }
            }
        }

        /// Pause/Fortsetzen über die Player-API von YouTube; klappt das nicht, Klick in den Player.
        func setPaused(_ paused: Bool) {
            let js = "(function(){var p=document.querySelector('#movie_player');if(!p||!p.pauseVideo)return false;p.\(paused ? "pauseVideo" : "playVideo")();return true})()"
            web?.evaluateJavaScript(js) { [weak self] ok, _ in
                if (ok as? Bool) != true { self?.click() }
            }
        }

        /// Klick in die Mitte des Players – direkt an die Ansicht geschickt, nicht übers System:
        /// keine Freigabe nötig, der Mauszeiger bleibt, wo er ist. WebKit wertet ihn als echten Klick.
        func click() {
            guard let w = web, let win = w.window else { return }
            let p = w.convert(NSPoint(x: w.bounds.midX, y: w.bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: win.windowNumber, context: nil,
                                                 eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
                if type == .leftMouseDown { w.mouseDown(with: e) } else { w.mouseUp(with: e) }
            }
            if Debug.on { print("trailer: clicked") }
        }
    }
}
