#!/bin/bash
# Baut PopSofa.app aus dem Swift-Package (Swift-Target: PopSofa).
# Voraussetzung: Xcode oder die Command Line Tools  (xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

APP="PopSofa.app"

# Die Command Line Tools enthalten kein SwiftUIMacros-Plugin (@State bricht) → Xcode nutzen, falls vorhanden.
if [ -d /Applications/Xcode.app ] && [ -z "${DEVELOPER_DIR:-}" ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "▸ Baue PopSofa (Release) …"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/PopSofa"

echo "▸ Erzeuge App-Bundle …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PopSofa"
# Schrift für den Stil „Klar“ (Atkinson Hyperlegible Next, SIL OFL 1.1 – Lizenz liegt daneben)
cp -R Resources/Fonts "$APP/Contents/Resources/"
# TMDB-Logo (Pflicht laut TMDB-API-Bedingungen, Abschnitt 3)
cp Resources/tmdb-logo.png "$APP/Contents/Resources/"

# App-Icon: groß (Dock, Finder) = Sessel aus Resources/AppIcon.png,
# klein (16/32 px: Listen, Menüs, Tabs) = nur Sprechblase aus Resources/AppIconSmall.png.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
SMALL=Resources/AppIconSmall.png
[ -f "$SMALL" ] || SMALL=Resources/AppIcon.png
icon() { sips -z "$1" "$1" "$2" --out "$ICONSET/$3" >/dev/null; }
icon 16 "$SMALL" icon_16x16.png
icon 32 "$SMALL" icon_16x16@2x.png
icon 32 "$SMALL" icon_32x32.png
icon 64 Resources/AppIcon.png icon_32x32@2x.png
for s in 128 256 512; do
    icon $s Resources/AppIcon.png "icon_${s}x${s}.png"
    icon $((s*2)) Resources/AppIcon.png "icon_${s}x${s}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PopSofa</string>
    <key>CFBundleDisplayName</key><string>PopSofa</string>
    <key>CFBundleIdentifier</key><string>local.couchkino.app</string>
    <key>CFBundleExecutable</key><string>PopSofa</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>PopSofa nutzt das Mikrofon für die Spracheingabe.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>PopSofa verbindet deinen gekoppelten Xbox-Controller nach dem Einschalten automatisch wieder.</string>
    <key>NSCameraUsageDescription</key>
    <string>PopSofa misst auf Wunsch einmalig deinen Abstand zum Bildschirm, um die Schrift anzupassen. Es werden keine Bilder gespeichert.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>PopSofa bietet im WLAN eine Fernbedienung fürs iPhone an.</string>
    <key>NSBonjourServices</key>
    <array><string>_popsofa._tcp</string></array>
    <key>NSAppleEventsUsageDescription</key>
    <string>PopSofa lädt einen schon offenen Netflix-/Prime-Tab mit deiner neuen Auswahl, statt einen weiteren Tab zu öffnen.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>PopSofa wandelt deine Sprache in Text um, damit du nicht tippen musst.</string>
</dict>
</plist>
PLIST

# Mit festem lokalem Zertifikat signieren: Die App-Identität bleibt über Builds gleich,
# so behält macOS Bedienungshilfen- und Schlüsselbund-Freigaben. Ohne Zertifikat: ad hoc.
IDENTITY="Couchkino Local Signing"
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "  (Kein Zertifikat „$IDENTITY“ – ad-hoc signiert, Freigaben gehen nach Updates verloren)"
    codesign --force --deep --sign - "$APP"
fi

echo "✓ Fertig: $(pwd)/$APP"

# Liegt die App schon in „Programme“ (auch noch unter altem Namen), dort gleich mit aktualisieren.
# Bundle-ID und Zertifikat bleiben gleich → Freigaben und Einstellungen bleiben erhalten.
if [ -d "/Applications/$APP" ] || [ -d /Applications/Couchkino.app ]; then
    pkill -x PopSofa || true
    pkill -x Couchkino || true
    rm -rf "/Applications/$APP" /Applications/Couchkino.app
    cp -R "$APP" "/Applications/$APP"
    echo "✓ Auch in /Applications aktualisiert"
fi
echo "  Tipp: In den Ordner „Programme“ ziehen und starten."
