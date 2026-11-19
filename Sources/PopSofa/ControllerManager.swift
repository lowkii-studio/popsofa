import GameController
import AppKit
import SwiftUI

/// Ereignisse für die Navigation im Launcher.
enum PadEvent { case up, down, left, right, a, b, x, y, lb, rb }

private struct PadState {
    var up = false, down = false, left = false, right = false
    var a = false, b = false, x = false, y = false
    var lb = false, rb = false
    var menu = false, view = false
    var l3 = false, r3 = false
    var lx: Float = 0, ly: Float = 0, rx: Float = 0, ry: Float = 0
    var lt: Float = 0, rt: Float = 0
}

/// Wiederholt gehaltene Richtungen (erst Verzögerung, dann schnelle Wiederholung).
private struct Repeater {
    var held: Int? = nil
    var next = Date.distantPast

    mutating func update(_ dir: Int?, now: Date, fire: (Int) -> Void) {
        guard let d = dir else { held = nil; return }
        if d != held {
            held = d
            next = now.addingTimeInterval(0.38)
            fire(d)
        } else if now >= next {
            next = now.addingTimeInterval(0.11)
            fire(d)
        }
    }
}

@MainActor
final class ControllerManager: ObservableObject {
    @Published private(set) var controllerName: String?
    /// Per Kabel (USB) statt Bluetooth verbunden.
    @Published private(set) var wired = false
    @Published private(set) var mouseMode = false

    var onEvent: ((PadEvent) -> Void)?
    var onToast: ((String) -> Void)?
    var onHome: (() -> Void)?
    /// Rechter Stick in PopSofa: senkrecht scrollen (dy > 0 = nach oben, wie das Mausrad).
    var onScroll: ((CGFloat) -> Void)?
    private let reconnect = PadReconnect()

    private var timer: Timer?
    private var prev = PadState()
    private var lastTick = Date()
    private var navRepeat = Repeater()
    private var arrowRepeat = Repeater()
    private var kbRepeat = Repeater()
    private var volumeRepeat = Repeater()
    private var scrollX: CGFloat = 0
    private var scrollY: CGFloat = 0

    /// Auf true setzen, falls die Scroll-Richtung bei dir verkehrt herum ist.
    private let invertScroll = false

    // MARK: Start

    func start() {
        // Controller-Eingaben auch dann empfangen, wenn der Browser vorne ist.
        GCController.shouldMonitorBackgroundEvents = true

        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
        reconnect.start { msg in PadLog.write(msg) }
        HIDButtons.shared.start()

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func refresh() {
        let c = GCController.controllers().first { $0.extendedGamepad != nil }
        let was = controllerName
        controllerName = c.map { $0.vendorName ?? "Controller" }
        // Per Kabel meldet sich der Xbox-Controller nicht als Bluetooth-HID-Gerät.
        wired = c != nil && !(HIDButtons.shared.transport?.contains("Bluetooth") ?? false)
        if (was == nil) != (controllerName == nil) {
            PadLog.write(controllerName == nil ? "Controller getrennt" : "Controller verbunden: \(controllerName!)")
        }
        if let n = controllerName, was == nil {
            _ = n
            HUD.shared.show(tr("Controller verbunden"), symbol: wired ? "cable.connector" : "dot.radiowaves.left.and.right", duration: 2)
            GCController.stopWirelessControllerDiscovery()
        } else if controllerName == nil {
            // Ohne Controller: nach drahtlosen Controllern suchen (hilft macOS beim Wiederverbinden).
            GCController.startWirelessControllerDiscovery {}
        }
    }

    // MARK: Eingabe lesen

    private func read() -> PadState? {
        guard let g = GCController.controllers().compactMap({ $0.extendedGamepad }).first else { return nil }
        var s = PadState()
        s.up = g.dpad.up.isPressed
        s.down = g.dpad.down.isPressed
        s.left = g.dpad.left.isPressed
        s.right = g.dpad.right.isPressed
        s.a = g.buttonA.isPressed
        s.b = g.buttonB.isPressed
        s.x = g.buttonX.isPressed
        s.y = g.buttonY.isPressed
        s.lb = g.leftShoulder.isPressed
        s.rb = g.rightShoulder.isPressed
        s.menu = g.buttonMenu.isPressed
        s.view = g.buttonOptions?.isPressed ?? false
        s.l3 = g.leftThumbstickButton?.isPressed ?? false
        s.r3 = g.rightThumbstickButton?.isPressed ?? false
        s.lx = g.leftThumbstick.xAxis.value
        s.ly = g.leftThumbstick.yAxis.value
        s.rx = g.rightThumbstick.xAxis.value
        s.ry = g.rightThumbstick.yAxis.value
        s.lt = g.leftTrigger.value
        s.rt = g.rightTrigger.value

        // Im Hintergrund liefert GameController keine Tasten → direkt vom Gerät (HID) ergänzen.
        let h = HIDButtons.shared
        if !NSApp.isActive && h.isOpen {
            typealias B = HIDButtons.Button
            s.a = s.a || h.isDown(B.a); s.b = s.b || h.isDown(B.b)
            s.x = s.x || h.isDown(B.x); s.y = s.y || h.isDown(B.y)
            s.lb = s.lb || h.isDown(B.lb); s.rb = s.rb || h.isDown(B.rb)
            s.menu = s.menu || h.isDown(B.menu); s.view = s.view || h.isDown(B.view)
            s.l3 = s.l3 || h.isDown(B.l3); s.r3 = s.r3 || h.isDown(B.r3)
            let d = h.dpad
            s.up = s.up || d.up; s.down = s.down || d.down; s.left = s.left || d.left; s.right = s.right || d.right
        }
        return s
    }

    private func tick() {
        let now = Date()
        let dt = CGFloat(min(now.timeIntervalSince(lastTick), 0.05))
        lastTick = now

        guard let s = read() else { prev = PadState(); return }

        // Diagnose: Kommt im Hintergrund (z. B. Safari vorne) überhaupt Controller-Eingabe an?
        if !NSApp.isActive, s.a != prev.a || s.menu != prev.menu || (abs(s.lx) > 0.5 && abs(prev.lx) <= 0.5) {
            PadLog.write("Eingabe im Hintergrund: A=\(s.a) ≡=\(s.menu) Stick=\(String(format: "%.1f", s.lx)) · Maus-Modus=\(mouseMode)")
        }

        // Globale Tasten (funktionieren überall)
        if s.menu && !prev.menu { setMouseMode(!mouseMode) }
        if s.view && !prev.view { returnToLauncher() }
        if s.l3 && !prev.l3 { KeyboardController.shared.toggle() }
        // Lautstärke überall: RT lauter, LT leiser (gedrückt halten = weiter regeln).
        // Bei offener Bildschirmtastatur bewegen LT/RT stattdessen den Textcursor (Korrektur mitten im Text).
        let typing = KeyboardController.shared.visible
        volumeRepeat.update(s.rt > 0.5 ? 0 : (s.lt > 0.5 ? 1 : nil), now: now) { d in
            if typing { Input.key(d == 0 ? Input.Code.rightArrow : Input.Code.leftArrow) }
            else { Input.volume(up: d == 0) }
        }

        if !KeyboardController.shared.visible { stickScroll(s, dt: dt) }

        if KeyboardController.shared.visible {
            tickKeyboard(s, now: now)
        } else if mouseMode {
            tickMouse(s, dt: dt, now: now)
        } else if NSApp.isActive {
            tickUI(s, now: now)
        }
        prev = s
    }

    private func direction(_ s: PadState, includeStick: Bool) -> Int? {
        if s.up { return 0 }
        if s.down { return 1 }
        if s.left { return 2 }
        if s.right { return 3 }
        if includeStick && (abs(s.lx) > 0.6 || abs(s.ly) > 0.6) {
            if abs(s.lx) > abs(s.ly) { return s.lx > 0 ? 3 : 2 }
            return s.ly > 0 ? 0 : 1
        }
        return nil
    }

    // MARK: Launcher-Navigation

    private func tickUI(_ s: PadState, now: Date) {
        let events: [PadEvent] = [.up, .down, .left, .right]
        navRepeat.update(direction(s, includeStick: true), now: now) { d in
            self.onEvent?(events[d])
        }
        if s.a && !prev.a { onEvent?(.a) }
        if s.b && !prev.b { onEvent?(.b) }
        if s.x && !prev.x { onEvent?(.x) }
        if s.y && !prev.y { onEvent?(.y) }
        if s.lb && !prev.lb { onEvent?(.lb) }
        if s.rb && !prev.rb { onEvent?(.rb) }
    }

    // MARK: Bildschirmtastatur

    private func tickKeyboard(_ s: PadState, now: Date) {
        let kb = KeyboardController.shared
        kbRepeat.update(direction(s, includeStick: true), now: now) { d in
            switch d {
            case 0: kb.move(dRow: -1, dCol: 0)
            case 1: kb.move(dRow: 1, dCol: 0)
            case 2: kb.move(dRow: 0, dCol: -1)
            default: kb.move(dRow: 0, dCol: 1)
            }
        }
        if s.a && !prev.a { kb.press() }
        if s.b && !prev.b { kb.hide() }
        if s.x && !prev.x { Input.key(Input.Code.delete) }
        if s.y && !prev.y { Input.key(Input.Code.space) }
        if s.lb && !prev.lb { kb.toggleShift() }
        if s.rb && !prev.rb { Input.key(Input.Code.returnKey) }
        if s.r3 && !prev.r3 { kb.dictation.toggle() }
    }

    // MARK: Maus-Modus

    func setMouseMode(_ on: Bool) {
        if on {
            guard Input.hasAccessibility(prompt: true) else {   // zeigt beim ersten Mal den System-Dialog
                // Hinweis über allem (auch über Safari) und die passende Einstellung gleich öffnen.
                HUD.shared.show(tr("Maus-Modus braucht die Freigabe: PopSofa unter Bedienungshilfen einschalten"),
                                symbol: "lock.shield", duration: 6)
                if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(u)
                }
                return
            }
        } else if Mouse.leftDown {
            Mouse.button(down: false)
        }
        guard on != mouseMode else { return }
        PadLog.write("Maus-Modus \(on ? "an" : "aus") · Bedienungshilfen=\(Input.hasAccessibility(prompt: false)) · Events senden erlaubt=\(CGPreflightPostEventAccess()) · vorne: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        if on && !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
        mouseMode = on
        scrollX = 0
        scrollY = 0
        arrowRepeat = Repeater()
        HUD.shared.show(
            tr(on ? "Maus-Modus an   ·   ≡ beenden   ·   ⧉ Launcher   ·   LT/RT Lautstärke" : "Maus-Modus aus"),
            symbol: on ? "cursorarrow.motionlines" : "cursorarrow.slash"
        )
    }

    func returnToLauncher() {
        KeyboardController.shared.hide()
        setMouseMode(false)
        onHome?()
        BrowserZoom.reset()   // solange der Browser noch vorne ist
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    private func curve(_ v: Float) -> CGFloat {
        let dz: Float = 0.14
        guard abs(v) > dz else { return 0 }
        let n = (abs(v) - dz) / (1 - dz)
        return CGFloat(v < 0 ? -n * n : n * n)
    }

    /// Rechter Stick scrollt überall: in PopSofa die Seite (senkrecht), sonst – Browser vorne oder
    /// Maus-Modus – per Mausrad-Ereignis an der Zeigerposition (im Maus-Modus auch seitlich).
    private func stickScroll(_ s: PadState, dt: CGFloat) {
        let sign: CGFloat = invertScroll ? -1 : 1
        let inApp = NSApp.isActive && !mouseMode
        scrollY += curve(s.ry) * 1400 * dt * sign
        scrollX += mouseMode ? -curve(s.rx) * 1400 * dt * sign : 0
        let iy = Int32(scrollY.rounded(.towardZero))
        let ix = Int32(scrollX.rounded(.towardZero))
        guard iy != 0 || ix != 0 else { return }
        scrollY -= CGFloat(iy)
        scrollX -= CGFloat(ix)
        if inApp {
            onScroll?(CGFloat(iy))
        } else if Input.hasAccessibility(prompt: false) {
            Mouse.scroll(dx: ix, dy: iy)
        }
    }

    private func tickMouse(_ s: PadState, dt: CGFloat, now: Date) {
        // Cursor: linker Stick (Tempo über die Stick-Auslenkung; LT/RT regeln die Lautstärke).
        let speed: CGFloat = 1200
        let mx = curve(s.lx), my = curve(s.ly)
        if mx != 0 || my != 0 {
            Mouse.move(dx: mx * speed * dt, dy: -my * speed * dt)
        }

        // Tasten
        if s.a != prev.a { Mouse.button(down: s.a) }
        if s.r3 && !prev.r3 { Mouse.click(right: true) }
        if s.b && !prev.b { Input.key(Input.Code.leftBracket, flags: .maskCommand) }      // Zurück
        if s.x && !prev.x { Input.key(Input.Code.space) }                                  // Play/Pause
        if s.y && !prev.y { Input.key(Input.Code.f) }                                      // Vollbild im Player
        if s.lb && !prev.lb { Input.key(Input.Code.tab, flags: [.maskControl, .maskShift]) } // Tab zurück
        if s.rb && !prev.rb { Input.key(Input.Code.tab, flags: .maskControl) }             // Tab vor

        // D-Pad = Pfeiltasten (vor/zurückspulen, Lautstärke, Menüs)
        let codes: [CGKeyCode] = [Input.Code.upArrow, Input.Code.downArrow,
                                  Input.Code.leftArrow, Input.Code.rightArrow]
        arrowRepeat.update(direction(s, includeStick: false), now: now) { d in
            Input.key(codes[d])
        }
    }
}

// MARK: - Kleines Overlay für Statusmeldungen (über dem Browser sichtbar)

@MainActor
final class HUD {
    static let shared = HUD()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, symbol: String, duration: Double = 3) {
        let host = NSHostingView(rootView: HUDView(text: text, symbol: symbol))
        host.setFrameSize(host.fittingSize)

        let p = panel ?? NSPanel(contentRect: host.frame,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        p.contentView = host
        p.setContentSize(host.frame.size)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .screenSaver
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        if let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: screen.frame.midX - host.frame.width / 2,
                                     y: screen.frame.minY + 90))
        }
        p.orderFrontRegardless()
        panel = p

        hideTask?.cancel()
        hideTask = Task { [weak p] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled { p?.orderOut(nil) }
        }
    }
}

struct HUDView: View {
    let text: String
    let symbol: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.ui(26, weight: .semibold))
            Text(text).font(.ui(22, weight: .semibold)).fixedSize()   // nie kürzen
        }
        .foregroundColor(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(Capsule().fill(Color.black.opacity(0.8)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
        .padding(8)
    }
}
