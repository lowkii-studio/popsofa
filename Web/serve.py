#!/usr/bin/env python3
# Startet PopSofa im WLAN: python3 Web/serve.py [port]  (Standard 8090)
# Wie `python3 -m http.server`, aber mit „Cache-Control: no-cache“: Browser (auch Fire TV) holen nach
# Änderungen sofort die neuen Dateien – unverändert kommt nur ein kurzes „304“ zurück.
import functools, http.server, os, sys

class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8090
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'app')
http.server.ThreadingHTTPServer(('', port), functools.partial(NoCache, directory=root)).serve_forever()
