# PopSofa im Browser

Zusätzlich zur Mac-App: PopSofa als Web-App für **Fire TV** (Silk-Browser), **Windows-PC** und jeden anderen Browser –
plus eine **Chrome-Erweiterung**, damit der Xbox-Controller auch in Netflix & Co. funktioniert.

- `app/` – die Web-App (HTML/CSS/JS, keine Abhängigkeiten, kein Build-Schritt)
- `extension/` – Chrome-Erweiterung „PopSofa Controller“ (Manifest V3)
- Übersetzungen kommen aus der Mac-App: nach Änderungen an `Sources/PopSofa/L10n.swift` einmal
  `python3 Tools/l10n-web.py` ausführen (erzeugt `app/i18n.js`).

## Was die Web-App kann

- Profile („Wer schaut?“) mit eigener Sprache (Deutsch, Português, English – Oberfläche **und** Beschreibungen),
  Heimatland und Diensten
- Toolbar mit Menüs für Stil (Apple, Pop-Art, Afro, Klar dunkel/hell, Pop hell), Textgröße und Sprache – Stil und
  Sprache schon vor der Profilwahl. Textgrößen rasten auf die Browser-Zoomstufen der Mac-App ein (Groß = 150 %);
  die Chrome-Erweiterung zoomt Netflix & Co. im selben Tab genauso
- Auf jeder Unterseite: „‹ Zurück“ und der Pfad (z. B. PopSofa › Einstellungen › Genres)
- Dienst-Kacheln (öffnen in neuem Tab), Empfehlungen „Beliebt / Neu bei deinen Diensten“, Titelsuche,
  Detailseite mit Trailer (A = Pause/Fortsetzen, stoppt beim Öffnen eines Dienstes) und „Ansehen bei …“
- Neues Profil: Sehtest (Schriftgröße) → Prismen-Check (bei Prismenbrille: Stil „Pop hell“) → Farbsehtest (passt die
  Farben der Oberfläche an) → Genres; alles später unter ⚙ wiederholbar
- Watchlist (Detailseite, eigene Reihe auf der Startseite) und Geschmack lernen: 👍/👎 mit X/Y (Tastatur L/N) auf
  Postern und in den Details; Reihen „Für dich“, „Weil dir … gefallen hat“ sortieren danach
- „Unsere Watchlist“ (Kachel auf der Startseite, ab zwei Profilen): Watchlists aller Profile auf einer Seite, jeder
  Titel einmal mit kleinen Avataren, wer ihn gemerkt hat; „Gemeinsam ausgewählt“ steht oben, Schalter „Nur gemeinsame“
- Bedienung mit Pfeiltasten / Fire-TV-Fernbedienung, Xbox-Controller (A/B/X/Y, Steuerkreuz, Stick) oder Maus
- Daten (Profile, TMDB-Schlüssel) bleiben im jeweiligen Browser – jedes Gerät richtet sich einmal ein.

Nicht dabei (bleibt der Mac-App vorbehalten): Abstandsmessung per Kamera, Kontraststufen der Klar-Stile,
iPhone-Fernbedienung, Reihe „Mal was anderes“. Daten werden nicht mit der Mac-App abgeglichen.

## Starten

Die App braucht nur einen Webserver für statische Dateien.

**Zum Ausprobieren im WLAN** (auf dem Mac, Fire TV und PC im selben Netz):

```bash
python3 Web/serve.py
```

Dann im Browser `http://<IP-des-Macs>:8090` öffnen (IP: Systemeinstellungen › WLAN › Details).

**Dauerhaft** (ohne dass der Mac läuft): den Ordner `Web/app` auf einen statischen Hoster legen, z. B. GitHub Pages
oder Netlify. Mit HTTPS lässt sich PopSofa in Chrome/Edge auch als App installieren (Adressleiste › „Installieren“).

## Fire TV

1. **Silk Browser** (oder „Amazon Silk“) aus dem Appstore installieren und die PopSofa-Adresse öffnen.
2. Lesezeichen setzen, damit sie mit einem Klick wieder da ist.
3. Steuerkreuz = Auswahl, Mitte = Öffnen, Zurück-Taste = zurück. Ein per Bluetooth gekoppelter Xbox-Controller
   funktioniert in PopSofa ebenfalls.

Grenze: Auf Fire TV gibt es keine Chrome-Erweiterungen. Netflix & Co. öffnen sich als Webseite in Silk und werden
dort mit der Fernbedienung bedient – oder besser direkt über die Fire-TV-Apps der Dienste.

## Windows-PC / Chrome / Edge

1. PopSofa-Adresse öffnen, am besten im Vollbild (F11).
2. Erweiterung installieren (einmalig):
   - `chrome://extensions` (Edge: `edge://extensions`) öffnen, **Entwicklermodus** einschalten
   - **Entpackte Erweiterung laden** › Ordner `Web/extension` wählen

### Controller in Netflix & Co. (mit Erweiterung)

| Taste | Aktion |
|---|---|
| Linker Stick | Zeiger bewegen |
| A | Klicken (ohne Zeiger: Enter) |
| B | Vollbild beenden / Esc |
| X oder ≡ | Pause / Weiter |
| Y | Vollbild |
| Steuerkreuz | Pfeiltasten |
| LB / RB | ← / → (bei vielen Playern: spulen) |
| LT / RT | Lautstärke |
| Rechter Stick | Scrollen |
| ⧉ (Ansicht) | Zurück zum PopSofa-Tab |

Profil automatisch wählen: Heißt dein Profil bei Netflix & Co. genauso wie in PopSofa, klickt die Erweiterung es
beim Öffnen an (die ersten 20 Sekunden). Die Erweiterung erkennt den PopSofa-Tab an seinem Titel („PopSofa · Name“)
und braucht deshalb keinen Zugriff auf die Seite, auf der PopSofa liegt.

Grenzen: Chrome reicht den Controller nur an den sichtbaren Tab weiter; manche Player ignorieren simulierte Tasten.
