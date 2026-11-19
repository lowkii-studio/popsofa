import Foundation
import Network
import CryptoKit
import AppKit
import Combine
import Darwin
import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Protokoll-Hilfen (rein, ohne Netzwerk testbar)

enum RemoteProto {
    /// Spiegel der Live-Eingabe des iPhones (RemotePage): Cursor-Schritte nach links, Löschungen, Einfügetext.
    static func liveDiff(_ old: [Character], _ new: [Character]) -> (left: Int, deletes: Int, insert: String) {
        var i = 0, j = 0
        while i < old.count, i < new.count, old[i] == new[i] { i += 1 }
        while j < old.count - i, j < new.count - i, old[old.count - 1 - j] == new[new.count - 1 - j] { j += 1 }
        return (j, old.count - j - i, String(new[i..<(new.count - j)]))
    }

    struct Request {
        var method = "", path = "", query: [String: String] = [:], headers: [String: String] = [:]
    }

    static let maxHeader = 8192
    static let maxPayload = 8192

    /// HTTP-Anfrage aus dem Puffer lesen. nil = noch unvollständig; sonst Anfrage + verbrauchte Bytes.
    /// Eine kaputte Anfrage kommt mit leerer Methode zurück (→ 400).
    static func parseRequest(_ buf: Data) -> (Request, Int)? {
        guard let end = buf.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let used = end.upperBound - buf.startIndex
        guard let head = String(data: buf[buf.startIndex..<end.lowerBound], encoding: .utf8) else { return (Request(), used) }
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count == 3, first[2].hasPrefix("HTTP/1.") else { return (Request(), used) }
        var r = Request()
        r.method = String(first[0])
        let target = URLComponents(string: String(first[1]))
        r.path = target?.path ?? ""
        for q in target?.queryItems ?? [] { r.query[q.name] = q.value ?? "" }
        for l in lines {
            guard let c = l.firstIndex(of: ":") else { continue }
            r.headers[l[..<c].trimmingCharacters(in: .whitespaces).lowercased()] =
                l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
        return (r, used)
    }

    static func acceptKey(_ key: String) -> String {
        let d = Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))
        return Data(d).base64EncodedString()
    }

    struct Frame { let opcode: UInt8; let payload: Data }
    enum FrameResult { case need, frame(Frame, Int), bad }

    /// Ein Frame vom Browser lesen (muss maskiert sein, Länge 7 oder 16 Bit, max. `maxPayload`).
    static func parseFrame(_ buf: Data) -> FrameResult {
        let b = [UInt8](buf.prefix(4 + 4 + maxPayload))
        guard b.count >= 2 else { return .need }
        let op = b[0] & 0x0F
        guard b[1] & 0x80 != 0 else { return .bad }            // Client-Frames sind immer maskiert
        var len = Int(b[1] & 0x7F), i = 2
        if len == 126 {
            guard b.count >= 4 else { return .need }
            len = Int(b[2]) << 8 | Int(b[3]); i = 4
        } else if len == 127 {
            return .bad                                          // 64-Bit-Längen brauchen wir nicht
        }
        guard len <= maxPayload else { return .bad }
        guard b.count >= i + 4 + len else { return .need }
        let mask = Array(b[i..<i + 4]); i += 4
        var p = Array(b[i..<i + len])
        for k in p.indices { p[k] ^= mask[k & 3] }
        return .frame(Frame(opcode: op, payload: Data(p)), i + len)
    }

    /// Frame an den Browser (unmaskiert, FIN gesetzt).
    static func frame(_ opcode: UInt8, _ payload: Data) -> Data {
        var d = Data([0x80 | opcode])
        let n = payload.count
        if n < 126 { d.append(UInt8(n)) }
        else if n < 65536 { d.append(contentsOf: [126, UInt8(n >> 8), UInt8(n & 0xFF)]) }
        else { d.append(127); for s in stride(from: 56, through: 0, by: -8) { d.append(UInt8((n >> s) & 0xFF)) } }
        d.append(payload)
        return d
    }

    static func isPrivateV4(_ b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        return b[0] == 10 || b[0] == 127
            || (b[0] == 172 && (16...31).contains(b[1]))
            || (b[0] == 192 && b[1] == 168)
            || (b[0] == 169 && b[1] == 254)
    }

    static func isPrivateV6(_ b: [UInt8]) -> Bool {
        guard b.count == 16 else { return false }
        if b == [UInt8](repeating: 0, count: 15) + [1] { return true }                 // ::1
        if b[0] == 0xFE && (b[1] & 0xC0) == 0x80 { return true }                        // fe80::/10
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF {        // ::ffff:a.b.c.d
            return isPrivateV4(Array(b[12..<16]))
        }
        return false
    }

    /// Nur Geräte aus dem lokalen Netz.
    static func isPrivate(_ ep: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = ep else { return false }
        switch host {
        case .ipv4(let a): return isPrivateV4([UInt8](a.rawValue))
        case .ipv6(let a): return isPrivateV6([UInt8](a.rawValue))
        default: return false
        }
    }

    /// Host-Header muss zu uns passen (Schutz vor DNS-Rebinding): private IP, *.local oder localhost – mit unserem Port.
    static func allowedHost(_ hostHeader: String, port: UInt16) -> Bool {
        guard let c = hostHeader.lastIndex(of: ":"),
              UInt16(hostHeader[hostHeader.index(after: c)...]) == port else { return false }
        let h = hostHeader[..<c].lowercased()
        if h == "localhost" || h == "[::1]" || h.hasSuffix(".local") { return true }
        if let a = IPv4Address(h) { return isPrivateV4([UInt8](a.rawValue)) }
        return false
    }

    /// Vergleich in konstanter Zeit (bei gleicher Länge).
    static func ctEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }

    static func newPin() -> String {
        var rng = SystemRandomNumberGenerator()
        return String(format: "%06d", Int.random(in: 0...999_999, using: &rng))
    }

    /// 256 Bit Zufall, Base64URL.
    static func newToken() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func hash(_ token: String) -> String {
        Data(SHA256.hash(data: Data(token.utf8))).base64EncodedString()
    }

    /// Zahl aus JSON lesen, auf ±limit begrenzt (NaN/fehlend → 0).
    static func num(_ v: Any?, _ limit: Double) -> Double {
        guard let d = (v as? NSNumber)?.doubleValue, d.isFinite else { return 0 }
        return min(max(d, -limit), limit)
    }

    static func selfTest() {
        let d1 = liveDiff(Array("Krimi auf Netflix"), Array("Krimis auf Netflix"))
        precondition(d1.left == 12 && d1.deletes == 0 && d1.insert == "s", "Einfügen mitten im Text: \(d1)")
        let d2 = liveDiff(Array("Haus des Geldes"), Array("Haus der Geldes"))
        precondition(d2.left == 7 && d2.deletes == 1 && d2.insert == "r", "Ersetzen mitten im Text: \(d2)")
        let d3 = liveDiff(Array("abc"), Array("abcd"))
        precondition(d3.left == 0 && d3.deletes == 0 && d3.insert == "d", "Anhängen")
        let raw = Data("GET /ws?pin=123456 HTTP/1.1\r\nHost: 192.168.1.5:8765\r\nUpgrade: websocket\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\nXY".utf8)
        guard let (r, used) = parseRequest(raw) else { preconditionFailure("HTTP nicht gelesen") }
        precondition(r.method == "GET" && r.path == "/ws" && r.query["pin"] == "123456", "Anfragezeile")
        precondition(r.headers["upgrade"] == "websocket" && raw.count - used == 2, "Header")
        precondition(parseRequest(Data("GET / HTTP/1.1\r\nHost: x".utf8)) == nil, "unvollständig")
        // Beispiel aus RFC 6455
        precondition(acceptKey("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", "WebSocket-Accept")

        // Maskierter Text-Frame "Hi" (RFC-Maske) → lesen, und unmaskierte Antwort bauen
        let masked = Data([0x81, 0x82, 0x37, 0xFA, 0x21, 0x3D, 0x7F, 0x93])
        guard case .frame(let f, let n) = parseFrame(masked) else { preconditionFailure("Frame") }
        precondition(f.opcode == 1 && String(data: f.payload, encoding: .utf8) == "Hi" && n == 8, "Frame-Inhalt")
        if case .need = parseFrame(masked.prefix(5)) {} else { preconditionFailure("unvollständiger Frame") }
        if case .bad = parseFrame(Data([0x81, 0x02, 0x48, 0x69])) {} else { preconditionFailure("unmaskiert ablehnen") }
        precondition(frame(1, Data("Hi".utf8)) == Data([0x81, 0x02, 0x48, 0x69]), "Antwort-Frame")
        precondition(frame(1, Data(count: 300)).prefix(4) == Data([0x81, 126, 0x01, 0x2C]), "16-Bit-Länge")

        precondition(isPrivateV4([192, 168, 0, 7]) && isPrivateV4([10, 1, 2, 3]) && isPrivateV4([172, 20, 0, 1]), "privat")
        precondition(!isPrivateV4([172, 32, 0, 1]) && !isPrivateV4([8, 8, 8, 8]), "öffentlich")
        precondition(isPrivateV6([UInt8](repeating: 0, count: 15) + [1]) && isPrivateV6([0xFE, 0x80] + [UInt8](repeating: 0, count: 14)), "IPv6 lokal")
        precondition(!isPrivateV6([0x20, 0x01] + [UInt8](repeating: 0, count: 14)), "IPv6 öffentlich")
        precondition(allowedHost("192.168.1.5:8765", port: 8765) && allowedHost("Alexs-Mac.local:8765", port: 8765), "Host ok")
        precondition(!allowedHost("evil.example:8765", port: 8765) && !allowedHost("192.168.1.5:9999", port: 8765), "Host abgelehnt")
        precondition(ctEqual(Data("123456".utf8), Data("123456".utf8)) && !ctEqual(Data("123456".utf8), Data("123457".utf8)), "Vergleich")
        precondition(newPin().count == 6 && newToken().count == 43 && newToken() != newToken(), "PIN/Token")
        precondition(num(1e9, 400) == 400 && num(Double.nan, 400) == 0 && num("x", 400) == 0, "Zahlen begrenzen")
    }
}

// MARK: - Gekoppelte Geräte

struct RemoteDevice: Codable, Identifiable {
    let id: UUID
    var name: String
    /// SHA-256 des Tokens – das Token selbst wird nie gespeichert.
    let hash: String
    let added: Date
    var lastSeen: Date

    static func load() -> [RemoteDevice] {
        guard let d = UserDefaults.standard.data(forKey: "remoteDevices") else { return [] }
        return (try? JSONDecoder().decode([RemoteDevice].self, from: d)) ?? []
    }
    static func save(_ list: [RemoteDevice]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: "remoteDevices")
    }
}

// MARK: - Server

/// Web-Fernbedienung: kleiner HTTP-/WebSocket-Server im lokalen WLAN (Port 8765…8785).
@MainActor
final class RemoteServer: ObservableObject {
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "remoteEnabled")
    @Published private(set) var port: UInt16?
    @Published private(set) var pin = ""
    @Published private(set) var error: String?
    @Published private(set) var devices = RemoteDevice.load()
    /// Gerade verbundene (angemeldete) Geräte.
    @Published private(set) var online: Set<UUID> = []

    private weak var app: AppState?
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: RemoteClient] = [:]
    private var failures: [String: (count: Int, until: Date)] = [:]
    private var pinTimer: Timer?
    private var stateSub: AnyCancellable?

    func attach(_ app: AppState) {
        self.app = app
        // Bei Änderungen (Dienste, Maus-Modus, Browser) den iPhones den neuen Stand schicken.
        stateSub = app.objectWillChange.merge(with: app.controller.objectWillChange)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.broadcastState() }
        if enabled { start() }
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "remoteEnabled")
        if on { start() } else { stop() }
    }

    /// Adresse fürs iPhone (QR-Code), nil wenn kein WLAN/LAN.
    var pairURL: String? {
        guard let p = port, let ip = Self.localIPv4() else { return nil }
        return "http://\(ip):\(p)/?pin=\(pin)"
    }

    // MARK: Start/Stopp

    private func start(port p: UInt16 = 8765) {
        stop(keepEnabled: true)
        error = nil
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true            // eingeschlafene iPhones schnell als getrennt erkennen
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        let params = NWParameters(tls: nil, tcp: tcp)
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: p), let l = try? NWListener(using: params, on: nwPort) else {
            nextPort(after: p); return
        }
        l.service = NWListener.Service(name: "Popsofa", type: "_popsofa._tcp")
        l.stateUpdateHandler = { [weak self] st in
            Task { @MainActor in self?.listenerChanged(st, port: p) }
        }
        l.newConnectionHandler = { [weak self] c in
            Task { @MainActor in self?.accept(c) }
        }
        l.start(queue: .main)
        listener = l
    }

    private func listenerChanged(_ st: NWListener.State, port p: UInt16) {
        switch st {
        case .ready:
            port = p
            newPin()
            pinTimer?.invalidate()
            let t = Timer(timeInterval: 600, repeats: true) { [weak self] _ in Task { @MainActor in self?.newPin() } }
            RunLoop.main.add(t, forMode: .common)
            pinTimer = t
            if Self.localIPv4() == nil { error = tr("Kein WLAN gefunden. iPhone und Mac müssen im selben WLAN sein.") }
            PadLog.write("Fernbedienung bereit auf Port \(p)")
        case .failed(let e):
            PadLog.write("Fernbedienung: Port \(p) – \(e)")
            nextPort(after: p)
        default:
            break
        }
    }

    private func nextPort(after p: UInt16) {
        if p < 8785 { start(port: p + 1) }
        else { stop(keepEnabled: true); error = tr("Port belegt: 8765–8785 sind alle in Benutzung.") }
    }

    private func stop(keepEnabled: Bool = false) {
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        for c in clients.values { c.close() }
        clients = [:]
        online = []
        port = nil
        pin = ""
        pinTimer?.invalidate()
        pinTimer = nil
        if !keepEnabled { error = nil }
    }

    private func newPin() {
        pin = RemoteProto.newPin()
        if Debug.on { print("remote: pin=\(pin)"); fflush(stdout) }      // nur im Testmodus (--press)
    }

    // MARK: Verbindungen

    private func accept(_ c: NWConnection) {
        guard RemoteProto.isPrivate(c.endpoint), clients.count < 8 else { c.cancel(); return }
        let client = RemoteClient(conn: c, server: self)
        clients[ObjectIdentifier(client)] = client
        client.start()
    }

    func closed(_ c: RemoteClient) {
        clients[ObjectIdentifier(c)] = nil
        updateOnline()
    }

    private func updateOnline() {
        online = Set(clients.values.compactMap(\.deviceID))
    }

    func http(_ r: RemoteProto.Request, from c: RemoteClient) {
        guard r.method == "GET" else { c.respond(r.method.isEmpty ? 400 : 405); return }
        switch r.path {
        case "/", "/index.html":
            c.respond(200, type: "text/html; charset=utf-8", body: Data(RemotePage.html.utf8))
        case "/ws":
            let h = r.headers, host = h["host"] ?? ""
            guard let key = h["sec-websocket-key"], h["upgrade"]?.lowercased() == "websocket",
                  let p = port, RemoteProto.allowedHost(host, port: p) else { c.respond(400); return }
            // Origin muss zur Adresse dieses Servers passen (keine fremden Webseiten).
            if let o = h["origin"], o.lowercased() != "http://\(host)".lowercased() { c.respond(403); return }
            c.upgrade(accept: RemoteProto.acceptKey(key))
        default:
            c.respond(404)
        }
    }

    // MARK: Nachrichten vom iPhone

    func message(_ m: [String: Any], from c: RemoteClient) {
        guard let t = m["t"] as? String else { return }
        guard c.deviceID != nil else {
            // Vor der Anmeldung wird nichts ausgeführt.
            if t == "pair" { pair(m, c) } else if t == "auth" { auth(m, c) }
            return
        }
        guard let app else { return }
        typealias P = RemoteProto
        switch t {
        case "move":
            Mouse.move(dx: P.num(m["dx"], 400) * 1.4, dy: P.num(m["dy"], 400) * 1.4)
        case "click":
            let right = (m["b"] as? String) == "right"
            for _ in 0..<(P.num(m["n"], 2) >= 2 ? 2 : 1) { Mouse.click(right: right) }
        case "drag":
            Mouse.button(down: (m["state"] as? String) == "start")
        case "scroll":
            Mouse.scroll(dx: Int32(P.num(m["dx"], 600)), dy: Int32(P.num(m["dy"], 600)))
        case "key":
            key(m["k"] as? String ?? "", app)
        case "text":
            if let s = m["s"] as? String, !s.isEmpty { Input.type(String(s.prefix(500))) }
        case "submit":
            Input.key(Input.Code.returnKey)
        case "launch":
            guard let id = m["id"] as? String,
                  let s = app.allServices.first(where: { $0.id == id && app.isEnabled($0) }) else { return }
            BrowserZoom.reset()
            NSApp.activate(ignoringOtherApps: true)
            app.detail = nil
            app.searchOpen = false
            app.launch(s)
        case "mode":
            if let on = m["mouse"] as? Bool { app.controller.setMouseMode(on) }
        case "home":
            app.controller.returnToLauncher()
        default:
            break                                   // Unbekanntes ignorieren
        }
    }

    private func key(_ k: String, _ app: AppState) {
        // Im Launcher wie der Controller navigieren.
        let inLauncher = NSApp.isActive && app.webURL == nil && !app.controller.mouseMode && !KeyboardController.shared.visible
        let pad: [String: PadEvent] = ["up": .up, "down": .down, "left": .left, "right": .right, "enter": .a, "back": .b]
        if inLauncher, let e = pad[k] { app.controller.onEvent?(e); return }
        typealias C = Input.Code
        switch k {
        case "up": Input.key(C.upArrow)
        case "down": Input.key(C.downArrow)
        case "left": Input.key(C.leftArrow)
        case "right": Input.key(C.rightArrow)
        case "enter": Input.key(C.returnKey)
        case "back": Input.key(C.leftBracket, flags: .maskCommand)
        case "space": Input.key(C.space)
        case "delete": Input.key(C.delete)
        case "cleft": Input.key(C.leftArrow)       // Textcursor, auch im Launcher (nicht Navigation)
        case "cright": Input.key(C.rightArrow)
        case "fullscreen": Input.key(C.f)
        case "volup": Input.volume(up: true)
        case "voldown": Input.volume(up: false)
        case "mute": Input.mute()
        case "tabnext": Input.key(C.tab, flags: .maskControl)
        case "tabprev": Input.key(C.tab, flags: [.maskControl, .maskShift])
        default: break
        }
    }

    private func pair(_ m: [String: Any], _ c: RemoteClient) {
        let now = Date()
        if let f = failures[c.ip], f.until > now {
            c.send(["t": "err", "code": "locked", "msg": tr("Zu viele falsche Versuche. Bitte 1 Minute warten.")])
            return
        }
        let given = (m["pin"] as? String) ?? ""
        guard !pin.isEmpty, RemoteProto.ctEqual(Data(given.utf8), Data(pin.utf8)) else {
            var f = failures[c.ip] ?? (0, .distantPast)
            f.count += 1
            if f.count >= 5 { f = (0, now.addingTimeInterval(60)) }
            failures[c.ip] = f
            c.send(["t": "err", "code": "pin", "msg": tr("Falsche oder abgelaufene PIN.")])
            return
        }
        failures[c.ip] = nil
        let token = RemoteProto.newToken()
        let raw = (m["name"] as? String) ?? ""
        let name = String(raw.filter { !$0.isNewline && $0.asciiValue.map { $0 >= 32 } ?? true }.prefix(40))
        let dev = RemoteDevice(id: UUID(), name: name.isEmpty ? "iPhone" : name, hash: RemoteProto.hash(token),
                               added: now, lastSeen: now)
        devices.append(dev)
        RemoteDevice.save(devices)
        newPin()                                     // PIN nach erfolgreicher Kopplung erneuern
        login(c, dev.id, token: token)
        HUD.shared.show(tr("%@ gekoppelt", dev.name), symbol: "iphone", duration: 2.5)
    }

    private func auth(_ m: [String: Any], _ c: RemoteClient) {
        let h = Data(RemoteProto.hash((m["token"] as? String) ?? "").utf8)
        var match: Int?
        for (i, d) in devices.enumerated() where RemoteProto.ctEqual(Data(d.hash.utf8), h) { match = i }
        guard let i = match else {
            c.send(["t": "err", "code": "token", "msg": tr("Dieses Gerät ist nicht mehr gekoppelt. Bitte neu koppeln.")])
            return
        }
        devices[i].lastSeen = Date()
        RemoteDevice.save(devices)
        login(c, devices[i].id, token: nil)
    }

    private func login(_ c: RemoteClient, _ id: UUID, token: String?) {
        c.deviceID = id
        var ok: [String: Any] = ["t": "ok"]
        if let token { ok["token"] = token }
        c.send(ok)
        c.sendState(stateJSON())
        updateOnline()
    }

    // MARK: Zustand ans iPhone

    private func stateJSON() -> [String: Any] {
        guard let app else { return ["t": "state"] }
        let t = app.theme
        // Kachelfarben wie auf dem Mac: Verlauf (Apple) oder flache Stil-Farbe mit lesbarer Schrift.
        let services = app.allServices.filter { app.isEnabled($0) }.map { s -> [String: String] in
            if t.bold {
                let hex = t.p.tone(for: s)
                return ["id": s.id, "name": s.name, "c1": hex, "c2": hex, "fg": Pop.textHexOn(hex)]
            }
            return ["id": s.id, "name": s.name, "c1": s.colorTop, "c2": s.colorBottom, "fg": "#FFFFFF"]
        }
        return ["t": "state", "services": services, "mouse": app.controller.mouseMode,
                "browser": app.browser.title, "theme": t.rawValue]
    }

    private func broadcastState() {
        guard !online.isEmpty else { return }
        let s = stateJSON()
        for c in clients.values where c.deviceID != nil { c.sendState(s) }
    }

    // MARK: Geräte verwalten

    func revoke(_ id: UUID) {
        devices.removeAll { $0.id == id }
        RemoteDevice.save(devices)
        for c in clients.values where c.deviceID == id { c.close() }
    }

    func revokeAll() {
        devices = []
        RemoteDevice.save(devices)
        for c in clients.values where c.deviceID != nil { c.close() }
    }

    // MARK: Netzwerk-Adresse

    /// Erste private IPv4-Adresse des Macs (WLAN meist en0).
    nonisolated static func localIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var best: String?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let f = p.pointee
            guard let sa = f.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  (f.ifa_flags & UInt32(IFF_UP)) != 0,
                  (f.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let name = String(cString: f.ifa_name)
            guard name.hasPrefix("en") else { continue }       // WLAN/LAN, nicht VPN/utun
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            guard let a = IPv4Address(ip), RemoteProto.isPrivateV4([UInt8](a.rawValue)), !ip.hasPrefix("169.254.") else { continue }
            if name == "en0" { return ip }
            best = best ?? ip
        }
        return best
    }

    /// Bonjour-Name des Macs, z. B. „Alexs-MacBook.local“.
    nonisolated static var bonjourHost: String {
        let h = ProcessInfo.processInfo.hostName
        return h.hasSuffix(".local") ? h : h + ".local"
    }
}

// MARK: - Eine Verbindung (HTTP, danach evtl. WebSocket)

@MainActor
final class RemoteClient {
    let conn: NWConnection
    let ip: String
    private weak var server: RemoteServer?
    private var buffer = Data()
    private var isWebSocket = false
    private var isClosed = false
    private var lastState = Data()
    var deviceID: UUID?

    init(conn: NWConnection, server: RemoteServer) {
        self.conn = conn
        self.server = server
        if case .hostPort(let h, _) = conn.endpoint { ip = "\(h)" } else { ip = "?" }
    }

    func start() {
        conn.stateUpdateHandler = { [weak self] st in
            switch st {
            case .failed, .cancelled: Task { @MainActor in self?.close() }
            default: break
            }
        }
        conn.start(queue: .main)
        receive()
        // Ohne Anmeldung nicht ewig offen halten.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if let self, self.deviceID == nil { self.close() }
        }
    }

    private func receive() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, done, err in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    self.process()
                }
                if done || err != nil { self.close() } else if !self.isClosed { self.receive() }
            }
        }
    }

    private func consume(_ n: Int) { buffer = buffer.subdata(in: buffer.startIndex + n..<buffer.endIndex) }

    private func process() {
        if !isWebSocket {
            guard let (req, used) = RemoteProto.parseRequest(buffer) else {
                if buffer.count > RemoteProto.maxHeader { respond(431) }
                return
            }
            consume(used)
            server?.http(req, from: self)
        }
        while isWebSocket && !isClosed {
            switch RemoteProto.parseFrame(buffer) {
            case .need: return
            case .bad: close(); return
            case .frame(let f, let n):
                consume(n)
                switch f.opcode {
                case 1:
                    if let o = try? JSONSerialization.jsonObject(with: f.payload) as? [String: Any] {
                        server?.message(o, from: self)
                    }
                case 8:
                    // Close bestätigen, erst danach trennen (sonst geht die Antwort verloren).
                    let c = conn
                    isClosed = true
                    conn.send(content: RemoteProto.frame(8, Data()), completion: .contentProcessed { [weak self] _ in
                        c.cancel()
                        Task { @MainActor in if let self { self.server?.closed(self) } }
                    })
                    return
                case 9: write(RemoteProto.frame(10, f.payload))      // Ping → Pong
                default: break                                          // Pong, Binär, Fortsetzung: ignorieren
                }
            }
        }
    }

    func respond(_ status: Int, type: String = "text/plain; charset=utf-8", body: Data? = nil) {
        let text: [Int: String] = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
                                   405: "Method Not Allowed", 431: "Request Header Fields Too Large"]
        let b = body ?? Data("\(status) \(text[status] ?? "")\n".utf8)
        var head = "HTTP/1.1 \(status) \(text[status] ?? "")\r\nContent-Type: \(type)\r\n"
        head += "Content-Length: \(b.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + b, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close() }
        })
    }

    func upgrade(accept: String) {
        isWebSocket = true
        write(Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n".utf8))
    }

    func send(_ obj: [String: Any]) {
        guard isWebSocket, let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        write(RemoteProto.frame(1, d))
    }

    /// Zustand nur schicken, wenn er sich geändert hat.
    func sendState(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), d != lastState else { return }
        lastState = d
        write(RemoteProto.frame(1, d))
    }

    private func write(_ d: Data) {
        guard !isClosed else { return }
        conn.send(content: d, completion: .idempotent)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        conn.cancel()
        server?.closed(self)
    }
}

// MARK: - QR-Code

func qrImage(_ text: String) -> Image? {
    let f = CIFilter.qrCodeGenerator()
    f.message = Data(text.utf8)
    f.correctionLevel = "M"
    guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
    let rep = NSCIImageRep(ciImage: out)
    let ns = NSImage(size: rep.size)
    ns.addRepresentation(rep)
    return Image(nsImage: ns).interpolation(.none).resizable()
}
