import CoreGraphics
import Foundation

/// Synthetische Maus-Eingaben – genutzt vom Controller-Maus-Modus und von der iPhone-Fernbedienung.
/// Benötigt die Berechtigung "Bedienungshilfen".
@MainActor
enum Mouse {
    private(set) static var leftDown = false
    private static var lastClickTime = Date.distantPast
    private static var clickCount = 0

    /// Zeiger relativ bewegen (begrenzt auf die Bildschirme). Bei gedrückter Taste wird gezogen.
    static func move(dx: CGFloat, dy: CGFloat) {
        guard var p = CGEvent(source: nil)?.location else { return }
        p.x += dx
        p.y += dy
        p = clamp(p)
        let type: CGEventType = leftDown ? .leftMouseDragged : .mouseMoved
        let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
        e?.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        e?.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        e?.post(tap: .cghidEventTap)
    }

    /// Taste drücken oder loslassen. Schnell aufeinanderfolgende Klicks zählen als Doppelklick.
    static func button(down: Bool, right: Bool = false) {
        guard let p = CGEvent(source: nil)?.location else { return }
        let type: CGEventType
        if right { type = down ? .rightMouseDown : .rightMouseUp }
        else { type = down ? .leftMouseDown : .leftMouseUp }

        if !right {
            if down {
                let now = Date()
                clickCount = now.timeIntervalSince(lastClickTime) < 0.4 ? clickCount + 1 : 1
                lastClickTime = now
            }
            leftDown = down
        }
        let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p,
                        mouseButton: right ? .right : .left)
        e?.setIntegerValueField(.mouseEventClickState, value: Int64(right ? 1 : max(clickCount, 1)))
        e?.post(tap: .cghidEventTap)
    }

    static func click(right: Bool = false) {
        button(down: true, right: right)
        button(down: false, right: right)
    }

    /// Scrollen in Pixeln (dy > 0 = nach oben, dx > 0 = nach links).
    static func scroll(dx: Int32, dy: Int32) {
        guard dx != 0 || dy != 0 else { return }
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                        wheel1: dy, wheel2: dx, wheel3: 0)
        e?.post(tap: .cghidEventTap)
    }

    private static func clamp(_ p: CGPoint) -> CGPoint {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var n: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &n)
        var union = CGRect.null
        for i in 0..<Int(n) { union = union.union(CGDisplayBounds(ids[i])) }
        guard !union.isNull else { return p }
        return CGPoint(x: min(max(p.x, union.minX), union.maxX - 1),
                       y: min(max(p.y, union.minY), union.maxY - 1))
    }
}
