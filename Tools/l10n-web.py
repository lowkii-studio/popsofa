#!/usr/bin/env python3
# Erzeugt Web/app/i18n.js aus der Übersetzungstabelle der Mac-App (Sources/PopSofa/L10n.swift).
# Nach neuen Texten in L10n.swift einfach erneut ausführen: python3 Tools/l10n-web.py
import json, re, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
s = (root / 'Sources/PopSofa/L10n.swift').read_text()
q = r'"((?:[^"\\]|\\.)*)"'
table = {json.loads(f'"{k}"'): [json.loads(f'"{p}"'), json.loads(f'"{e}"')]
         for k, p, e in re.findall(rf'^\s*{q}: \[{q}, {q}\],$', s, re.M)}
out = root / 'Web/app/i18n.js'
out.write_text('// Erzeugt von Tools/l10n-web.py aus L10n.swift – nicht von Hand ändern.\n'
               'const L10N = ' + json.dumps(table, ensure_ascii=False, indent=0) + ';\n')
print(f'✓ {len(table)} Texte → {out.relative_to(root)}')
