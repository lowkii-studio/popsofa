import Foundation
import IOKit.hid

/// Liest die Tasten des Xbox-Controllers direkt vom Gerät (HID).
/// Grund: Ist ein anderes Programm vorne (z. B. Chrome), liefert das GameController-Framework
/// zwar die Sticks, aber keine Tasten mehr an PopSofa. HID-Werte kommen unabhängig davon an.
/// Das Gerät wird nur mitgelesen, nicht exklusiv belegt.
final class HIDButtons {
    static let shared = HIDButtons()

    /// Gedrückte Tasten (HID-Button-Nummern) und D-Pad-Richtung (Hat: 1…8, 0 = neutral).
    private(set) var pressed = Set<Int>()
    private(set) var hat = 0
    private(set) var isOpen = false
    private var manager: IOHIDManager?

    func start() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Nur Microsoft-Gamepads (Xbox-Controller), Usage Page Generic Desktop / Game Pad.
        let match: [String: Any] = [
            kIOHIDVendorIDKey: 0x045E,
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad,
        ]
        IOHIDManagerSetDeviceMatching(m, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(m, { ctx, _, _, value in
            guard let ctx else { return }
            Unmanaged<HIDButtons>.fromOpaque(ctx).takeUnretainedValue().handle(value)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = r == kIOReturnSuccess
        PadLog.write("HID-Tasten: \(isOpen ? "aktiv" : "nicht verfügbar (Fehler \(r))")")
        manager = m
    }

    private func handle(_ value: IOHIDValue) {
        let el = IOHIDValueGetElement(value)
        let page = Int(IOHIDElementGetUsagePage(el)), usage = Int(IOHIDElementGetUsage(el))
        let v = IOHIDValueGetIntegerValue(value)
        if page == kHIDPage_Button {
            if v != 0 {
                if pressed.insert(usage).inserted { PadLog.write("HID-Taste \(usage)") }
            } else {
                pressed.remove(usage)
            }
        } else if page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Hatswitch {
            hat = v
        }
    }

    // Belegung des Xbox-Wireless-Controllers über Bluetooth (Firmware 5.x).
    enum Button {
        static let a = 1, b = 2, x = 4, y = 5, lb = 7, rb = 8, view = 11, menu = 12, l3 = 14, r3 = 15
    }

    func isDown(_ b: Int) -> Bool { pressed.contains(b) }

    /// Verbindung des Xbox-Controllers laut HID („Bluetooth“, „Bluetooth Low Energy“, „USB“); nil = kein HID-Gerät.
    var transport: String? {
        guard let m = manager, let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>, let d = set.first else { return nil }
        return IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String
    }

    /// Hat-Switch (1 = oben, im Uhrzeigersinn bis 8) → oben/unten/links/rechts.
    var dpad: (up: Bool, down: Bool, left: Bool, right: Bool) {
        switch hat {
        case 1: return (true, false, false, false)
        case 2: return (true, false, false, true)
        case 3: return (false, false, false, true)
        case 4: return (false, true, false, true)
        case 5: return (false, true, false, false)
        case 6: return (false, true, true, false)
        case 7: return (false, false, true, false)
        case 8: return (true, false, true, false)
        default: return (false, false, false, false)
        }
    }
}
