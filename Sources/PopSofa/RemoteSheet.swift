import SwiftUI
import AppKit

/// Inhalt der Seite „iPhone koppeln“: QR-Code, PIN, Adresse, gekoppelte Geräte (Knöpfe liefert `FormPage`).
struct RemoteInfo: View {
    @ObservedObject var remote: RemoteServer

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if remote.enabled {
                // Adresse alle paar Sekunden neu lesen (WLAN-Wechsel).
                TimelineView(.periodic(from: .now, by: 5)) { _ in connection }
            } else {
                Label(tr("Fernbedienung ist aus – unten einschalten."), systemImage: "iphone.slash")
                    .font(.read(18, weight: .semibold))
            }
            if !remote.devices.isEmpty { deviceList }
            Text(tr("Nur in vertrauenswürdigen WLANs verwenden. Beim ersten Start fragt macOS evtl., ob PopSofa eingehende Verbindungen annehmen bzw. auf das lokale Netzwerk zugreifen darf – bitte erlauben."))
                .font(.read(15)).opacity(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 900 * Metrics.s, alignment: .leading)
        }
    }

    @ViewBuilder private var connection: some View {
        if let p = remote.port {
            let ip = RemoteServer.localIPv4()
            HStack(alignment: .top, spacing: 28) {
                Group {
                    if let url = remote.pairURL, let img = qrImage(url) {
                        img.frame(width: 220, height: 220)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "wifi.slash").font(.ui(40))
                            Text(tr("Kein WLAN gefunden")).font(.ui(15, weight: .semibold))
                        }
                        .foregroundColor(Ink.bg.opacity(0.6))
                        .frame(width: 220, height: 220)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18).fill(Ink.fg))

                VStack(alignment: .leading, spacing: 10) {
                    Text("PIN").font(.ui(15, weight: .semibold)).dimText(0.85)
                    Text(spaced(remote.pin))
                        .font(.ui(46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .textSelection(.enabled)
                    Text(tr("Mit der iPhone-Kamera scannen und in Safari öffnen. Tipp: In Safari „Zum Home-Bildschirm“ wählen."))
                        .font(.ui(15)).dimText(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    if let ip {
                        Text("http://\(ip):\(String(p))").font(.ui(15, design: .monospaced)).textSelection(.enabled)
                    }
                    Text(tr("Falls sich die Adresse ändert: %@", "http://\(RemoteServer.bonjourHost):\(String(p))"))
                        .font(.ui(15, design: .monospaced)).dimText(0.85).textSelection(.enabled)
                    Label(remote.online.isEmpty ? tr("Kein iPhone verbunden") : tr("%@ Gerät(e) verbunden", remote.online.count),
                          systemImage: remote.online.isEmpty ? "iphone.slash" : "iphone.radiowaves.left.and.right")
                        .font(.ui(15, weight: .semibold))
                        .foregroundColor(remote.online.isEmpty ? Ink.fg.opacity(0.6) : .green)
                    if let e = remote.error {
                        Label(e, systemImage: "exclamationmark.triangle.fill")
                            .font(.ui(15)).foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(tr("iPhone und Mac müssen im selben WLAN sein.")).font(.ui(15)).dimText(0.85)
                    }
                }
            }
        } else if let e = remote.error {
            Label(e, systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
        } else {
            ProgressView(tr("Starte …"))
        }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Gekoppelte Geräte")).font(.ui(16, weight: .semibold))
            ForEach(remote.devices) { d in
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                    Text(d.name).font(.ui(15, weight: .semibold))
                    Text(tr("gekoppelt am %@", d.added.formatted(date: .abbreviated, time: .shortened)))
                        .font(.ui(15)).dimText(0.85)
                    if remote.online.contains(d.id) {
                        Text("verbunden").font(.ui(15, weight: .semibold)).foregroundColor(.green)
                    }
                    Spacer()
                    Button { remote.revoke(d.id) } label: {
                        Text(tr("Kopplung aufheben")).font(.ui(15, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(Ink.fg.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func spaced(_ pin: String) -> String {
        pin.count == 6 ? "\(pin.prefix(3)) \(pin.suffix(3))" : pin
    }
}

/// iPhone-Symbol in der Kopfzeile: öffnet den Dialog; leuchtet, wenn ein Gerät verbunden ist.
struct RemoteBadge: View {
    @ObservedObject var remote: RemoteServer
    var focused = false
    var open: () -> Void

    var body: some View {
        HeaderButton(focused: focused, active: !remote.online.isEmpty,
                     help: remote.online.isEmpty ? tr("iPhone koppeln") : tr("iPhone verbunden"), action: open) {
            Image(systemName: remote.online.isEmpty ? "iphone" : "iphone.radiowaves.left.and.right")
                .font(.ui(20, weight: .semibold))
        }
    }
}
