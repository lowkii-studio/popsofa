#!/usr/bin/env python3
"""Testet die PopSofa-Fernbedienung ohne iPhone (nur Python-Standardbibliothek).

  python3 Tools/ws_test.py 192.168.1.5 8765 --pin 123456      # koppeln, gibt Token aus
  python3 Tools/ws_test.py 192.168.1.5 8765 --token <TOKEN>   # mit gespeichertem Token anmelden
  python3 Tools/ws_test.py 127.0.0.1 8765 --pin 000000        # falsche PIN (5× → 60 s Sperre)
  ... --send '{"t":"key","k":"volup"}'                        # zusätzlich Befehle senden
"""
import argparse, base64, hashlib, json, os, socket, struct, sys

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def http_get(host, port):
    s = socket.create_connection((host, port), timeout=5)
    s.sendall(f"GET / HTTP/1.1\r\nHost: {host}:{port}\r\n\r\n".encode())
    data = b""
    while chunk := s.recv(65536):
        data += chunk
    s.close()
    head, _, body = data.partition(b"\r\n\r\n")
    return head.split(b"\r\n")[0].decode(), body


def send_frame(s, opcode, payload: bytes):
    mask = os.urandom(4)
    n = len(payload)
    head = bytes([0x80 | opcode])
    head += bytes([0x80 | n]) if n < 126 else bytes([0x80 | 126]) + struct.pack(">H", n)
    s.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))


def recv_exact(s, n):
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("Verbindung geschlossen")
        buf += chunk
    return buf


def recv_frame(s):
    b0, b1 = recv_exact(s, 2)
    n = b1 & 0x7F
    if n == 126:
        n = struct.unpack(">H", recv_exact(s, 2))[0]
    elif n == 127:
        n = struct.unpack(">Q", recv_exact(s, 8))[0]
    assert not b1 & 0x80, "Server-Frames dürfen nicht maskiert sein"
    return b0 & 0x0F, recv_exact(s, n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("host")
    ap.add_argument("port", type=int, nargs="?", default=8765)
    ap.add_argument("--pin")
    ap.add_argument("--token")
    ap.add_argument("--origin", help="Origin-Header (z. B. fremde Seite, um die Ablehnung zu testen)")
    ap.add_argument("--send", action="append", default=[], help="JSON-Nachricht nach der Anmeldung")
    a = ap.parse_args()

    status, body = http_get(a.host, a.port)
    print("GET /:", status, f"({len(body)} Bytes)")
    assert "200" in status and b"PopSofa" in body, "Seite nicht geliefert"

    s = socket.create_connection((a.host, a.port), timeout=5)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (f"GET /ws HTTP/1.1\r\nHost: {a.host}:{a.port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
           f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n")
    if a.origin:
        req += f"Origin: {a.origin}\r\n"
    s.sendall((req + "\r\n").encode())
    head = b""
    while b"\r\n\r\n" not in head:
        head += s.recv(1)
    first = head.split(b"\r\n")[0].decode()
    print("Upgrade:", first)
    if "101" not in first:
        print("→ abgelehnt")
        return 1
    want = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
    assert f"Sec-WebSocket-Accept: {want}".encode() in head, "Sec-WebSocket-Accept falsch"
    print("Handshake OK")

    if a.token:
        hello = {"t": "auth", "token": a.token}
    else:
        hello = {"t": "pair", "pin": a.pin or "", "name": "Testskript"}
    send_frame(s, 1, json.dumps(hello).encode())
    op, data = recv_frame(s)
    reply = json.loads(data)
    print("Antwort:", reply)
    if reply.get("t") != "ok":
        return 2
    op, data = recv_frame(s)
    st = json.loads(data)
    print("Zustand:", st.get("t"), "–", len(st.get("services", [])), "Dienste, Maus-Modus:", st.get("mouse"))

    send_frame(s, 9, b"hallo")
    op, data = recv_frame(s)
    assert op == 10 and data == b"hallo", "kein Pong"
    print("Ping/Pong OK")

    send_frame(s, 1, b'{"t":"gibtsnicht"}')                 # Unbekanntes wird ignoriert
    for m in a.send:
        send_frame(s, 1, m.encode())
        print("gesendet:", m)

    send_frame(s, 8, b"")
    op, _ = recv_frame(s)
    print("Close OK" if op == 8 else f"Close: unerwarteter Opcode {op}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
