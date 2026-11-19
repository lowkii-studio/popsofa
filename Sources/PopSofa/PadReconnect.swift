import Foundation
import CoreBluetooth
import IOBluetooth
import GameController

/// Hilft dem Xbox-Controller beim Wiederverbinden: macOS nimmt die Verbindung nach dem Einschalten
/// manchmal nicht an. PopSofa merkt sich den gekoppelten Controller und stellt eine Verbindungsanfrage
/// bereit – schaltet er sich ein, verbindet macOS ihn darüber, ohne neu koppeln zu müssen.
@MainActor
final class PadReconnect: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager?
    private var timer: Timer?
    private var classicBusy = false
    private let hid = CBUUID(string: "1812")           // Bluetooth-HID-Dienst
    private var onLog: (String) -> Void = { _ in }

    private var savedID: UUID? {
        get { UserDefaults.standard.string(forKey: "padPeripheral").flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "padPeripheral") }
    }
    private var savedAddress: String? {
        get { UserDefaults.standard.string(forKey: "padAddress") }
        set { UserDefaults.standard.set(newValue, forKey: "padAddress") }
    }

    func start(log: @escaping (String) -> Void = { _ in }) {
        onLog = log
        log("PopSofa gestartet")
        central = CBCentralManager(delegate: self, queue: .main)
        let t = Timer(timeInterval: 4, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var padConnected: Bool { GCController.controllers().contains { $0.extendedGamepad != nil } }

    private func tick() {
        rememberPad()
        guard !padConnected else { onLog("Controller aktiv"); return }
        onLog("Kein Controller – warte auf Einschalten (BLE-Kennung: \(savedID == nil ? "nein" : "ja"), Adresse: \(savedAddress == nil ? "nein" : "ja"))")

        // Bluetooth LE (Xbox-Series-Controller mit aktueller Firmware): offene Verbindungsanfrage.
        // Sie läuft nicht ab – sobald der Controller wirbt, verbindet macOS ihn.
        if let c = central, c.state == .poweredOn, let id = savedID,
           let p = c.retrievePeripherals(withIdentifiers: [id]).first, p.state == .disconnected {
            c.connect(p, options: nil)
            onLog("Verbindungsanfrage an \(p.name ?? "Controller")")
        }

        // Klassisches Bluetooth (ältere Firmware): Verbindung aktiv öffnen (blockiert kurz → Hintergrund).
        if let addr = savedAddress, !classicBusy {
            classicBusy = true
            DispatchQueue.global(qos: .utility).async { [weak self] in
                if let dev = IOBluetoothDevice(addressString: addr), !dev.isConnected() {
                    _ = dev.openConnection()
                }
                DispatchQueue.main.async { self?.classicBusy = false }
            }
        }
    }

    /// Solange der Controller verbunden ist: Kennung und Adresse merken.
    private func rememberPad() {
        if let c = central, c.state == .poweredOn,
           let p = c.retrieveConnectedPeripherals(withServices: [hid]).first(where: { Self.isXbox($0.name) }),
           savedID != p.identifier {
            savedID = p.identifier
            onLog("Controller gemerkt (BLE)")
        }
        if savedAddress == nil,
           let dev = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?.first(where: { Self.isXbox($0.name) }) {
            savedAddress = dev.addressString
            onLog("Controller gemerkt (Adresse)")
        }
    }

    private static func isXbox(_ name: String?) -> Bool {
        (name ?? "").localizedCaseInsensitiveContains("xbox")
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in self.tick() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in self.onLog("Bluetooth verbunden: \(peripheral.name ?? "Controller")") }
    }
}

/// Kurzes Protokoll für Verbindungsprobleme: ~/Library/Logs/PopSofa.log (max. ~200 KB).
enum PadLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/PopSofa.log")
    private static var last = ""

    static func write(_ msg: String) {
        if Debug.on { print("pad:", msg) }
        guard msg != last else { return }          // gleiche Meldung nicht alle 4 s wiederholen
        last = msg
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(msg)\n"
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int), size > 200_000 {
            try? FileManager.default.removeItem(at: url)
        }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
