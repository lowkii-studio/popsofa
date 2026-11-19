// Sehtest (Schriftgröße) und Farbsehtest mit Farbanpassung – wie in der Mac-App (Profiles.swift, ColorTest.swift, Access.swift).
// Ergebnis liegt im Profil: scale (Textfaktor), vision (normal/protan/deutan/tritan/achromat), severity (0,5 / 1).
'use strict';

// MARK: - Farbanpassung (Daltonisierung, Matrizen nach Machado, Oliveira & Fernandes 2009, lineares RGB)

const SIM = {
  protan: [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
  deutan: [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
  tritan: [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
};
const VISION_TITLE = { normal: 'Normales Farbsehen', protan: 'Rot-Schwäche (Protanopie)', deutan: 'Grün-Schwäche (Deuteranopie)',
  tritan: 'Blau-Gelb-Schwäche (Tritanopie)', achromat: 'Keine Farben (Achromatopsie)' };
const I3 = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];
const mul = (a, b) => a.map((r, i) => r.map((_, j) => r.reduce((s, _, k) => s + a[i][k] * b[k][j], 0)));

/// Was die Schwäche verschluckt, wird auf noch unterscheidbare Kanäle verschoben: M = I + D · (I − S).
function adaptation(vision, severity = 1) {
  if (!SIM[vision]) return null;   // normal / keine Farben: Farbverschiebung hilft nicht
  const s = SIM[vision].map((r, i) => r.map((v, j) => I3[i][j] + severity * (v - I3[i][j])));
  const d = vision === 'tritan' ? [[1, 0, 0.7], [0, 1, 0.7], [0, 0, 0]] : [[0, 0, 0], [0.7, 1, 0], [0.7, 0, 1]];
  const err = I3.map((r, i) => r.map((v, j) => v - s[i][j]));
  return mul(d, err).map((r, i) => r.map((v, j) => v + I3[i][j]));
}

// SVG-Filter (feColorMatrix rechnet standardmäßig in linearem RGB – wie Core Image in der Mac-App).
document.body.insertAdjacentHTML('beforeend', `<svg width="0" height="0" style="position:absolute" aria-hidden="true">
  <filter id="cv" color-interpolation-filters="linearRGB"><feColorMatrix id="cvm" type="matrix"/></filter></svg>`);

/// Schriftgröße und Farbanpassung des aktiven Profils anwenden (bei jedem Neuzeichnen).
function applyLook() {
  const p = me(), view = current?.view;
  document.documentElement.style.setProperty('--scale', view === 'eyetest' ? 1 : zoom());   // Browser-Zoomstufe (app.js)
  document.body.dataset.theme = themeOf();
  const m = view === 'colortest' ? null : adaptation(p?.vision, p?.severity);   // Test misst die echten Farben
  if (m) document.getElementById('cvm').setAttribute('values',
    m.map(r => [...r, 0, 0].join(' ')).join(' ') + ' 0 0 0 1 0');
  for (const id of ['app', 'hints', 'toast', 'sheet', 'osk']) document.getElementById(id).style.filter = m ? 'url(#cv)' : '';
}

// MARK: - Sehtest: kleinste bequem lesbare Zeile → Textfaktor des Profils

const EYE_SIZES = [0.85, 1.0, 1.2, 1.45, 1.75], EYE_FACTORS = [0.9, 1.0, 1.2, 1.45, 1.75];
const EYE_SAMPLES = [
  'Ein pensionierter Uhrmacher entdeckt in seinem Keller eine Tür, die es gestern noch nicht gab.',
  'Zwei Schwestern erben ein Strandhotel in Lissabon – und mit ihm ein Geheimnis aus den Siebzigern.',
  'Als der Strom in der ganzen Stadt ausfällt, muss eine Nachtschicht im Zoo improvisieren.',
  'Ein junger Koch will das Restaurant seiner Familie retten und kocht gegen die Zeit.',
  'Eine Astronautin kehrt zur Erde zurück und findet ihre Heimat völlig verändert vor.',
];
const stepLine = (n, d) => d.setup ? `<p class="dim">${esc(t('Schritt %@ von %@', n, 5))}</p>` : '';

views.eyetest = d => `${stepLine(2, d)}<h1>${esc(t('Kurzer Sehtest'))}</h1>
  <p class="intro">${esc(t('Bleib dort sitzen, wo du sonst schaust. Die Zeilen sind Filmbeschreibungen – die kleinste Schrift in PopSofa. Welche ist die kleinste Zeile, die du bequem lesen kannst?'))}</p>
  <div class="eyelines">${EYE_SAMPLES.map((s, i) => `<button class="eyeline" data-f data-k="eye${i}" data-a="eye" data-v="${i}"
    style="font-size:${(EYE_SIZES[i] * 0.85).toFixed(3)}rem">${esc(t(s))}</button>`).join('')}</div>
  <div class="row-btns"><button class="btn" data-f data-k="later" data-a="eyeDone">${esc(t('Später'))}</button></div>`;
views.eyetest.after = (_, k) => { if (!k) refocus('eye1'); };

Object.assign(actions, {
  eye(v) {
    const p = me(), f = EYE_FACTORS[+v], pct = Math.round((f - 1) * 100);
    p.scale = f; save();
    toast(pct ? t('Text für %@ %@', p.name, `${pct > 0 ? '+' : ''}${pct} %`) : t('Textgröße passt so'));
    actions.eyeDone();
  },
  // Einrichtung: weiter zum Prismen-Check (an derselben Stelle im Verlauf), sonst zurück.
  eyeDone() { current.data.setup ? step('prism') : back(); },
});
/// Nächster Einrichtungsschritt ersetzt den aktuellen im Verlauf – Zurück führt dann zur Startseite.
function step(view) {
  history.replaceState({ ...history.state, view, data: { setup: true } }, '');
  show(view, { setup: true });
}

// MARK: - Prismen-Check: Prismengläser zerlegen helle Kanten auf dunklem Grund in farbige Säume.
// Wer das sieht, bekommt „Pop hell (Prismen)“ – dunkle Schrift auf hellem Grund (wie in der Mac-App).

const prismSample = (cls) => `<div class="prism ${cls}"><b>PopSofa</b>
  <p>${esc(t('Zwei Schwestern erben ein Strandhotel in Lissabon – und mit ihm ein Geheimnis aus den Siebzigern.'))}</p>
  <i>${'<span></span>'.repeat(9)}</i></div>`;
views.prism = d => `${stepLine(3, d)}<h1>${esc(t('Prismen-Check'))}</h1>
  <p class="intro">${esc(t('Trägst du eine Brille mit Prismen? Prismengläser zeigen an hellen Kanten auf dunklem Grund oft rote und blaue Säume. Schau dir beide Felder an.'))}</p>
  <div class="prisms">${prismSample('dark')}${prismSample('light')}</div>
  <p><b>${esc(t('Siehst du links farbige Ränder oder Doppelkanten – oder liest du rechts entspannter?'))}</b></p>
  <div class="row-btns"><button class="btn primary" data-f data-k="yes" data-a="prism" data-v="1">${esc(t('Ja – helles Design nehmen'))}</button>
    <button class="btn" data-f data-k="no" data-a="prism" data-v="0">${esc(t('Nein – so lassen'))}</button></div>`;
views.prism.title = () => t('Prismen-Check');
actions.prism = v => {
  const p = me();
  if (v === '1' && p.theme !== 'popLight') { p.theme = 'popLight'; save(); toast(t('Stil: %@', t('Pop hell (Prismen)'))); }
  if (!current.data.setup) return back();
  ct = newTest(); step('colortest');
};

// MARK: - Farbsehtest (Cambridge-Colour-Test-Prinzip: Landolt-Ring aus Punkten, nur über den Farbton erkennbar)
// ponytail: unkalibrierter Bildschirm, nur Orientierung – keine Diagnose.

const CM = {
  white: [0.1978, 0.4683],
  levels: [0.10, 0.13, 0.16, 0.19, 0.22],
  copunctal: [[0.678, 0.501], [-1.217, 0.782], [0.257, 0.0]],   // protan, deutan, tritan (u′v′)
  uv(axis, d) {
    const [cu, cv] = CM.copunctal[axis], du = CM.white[0] - cu, dv = CM.white[1] - cv, l = Math.hypot(du, dv);
    return [CM.white[0] + du / l * d, CM.white[1] + dv / l * d];
  },
  linear(u, v, Y) {
    const den = 6 * u - 16 * v + 12, x = 9 * u / den, y = 4 * v / den;
    if (y <= 0) return null;
    const X = x * Y / y, Z = (1 - x - y) * Y / y;
    const rgb = [3.2406 * X - 1.5372 * Y - 0.4986 * Z, -0.9689 * X + 1.8758 * Y + 0.0415 * Z, 0.0557 * X - 0.2040 * Y + 1.0570 * Z];
    return rgb.every(c => c >= 0 && c <= 1) ? rgb : null;
  },
  gamma: c => c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055,
  css(axis, d, Y) {
    const [u, v] = axis == null ? CM.white : CM.uv(axis, d);
    return `rgb(${(CM.linear(u, v, Y) || [Y, Y, Y]).map(c => (CM.gamma(c) * 255).toFixed(1)).join(',')})`;
  },
  maxD(axis) {
    let d = 0;
    while (d < 0.2) { const n = d + 0.002, [u, v] = CM.uv(axis, n); if (!CM.levels.every(Y => CM.linear(u, v, Y))) break; d = n; }
    return d;
  },
};

/// Treppenverfahren je Achse: richtig → schwächer, falsch → stärker.
function stair(maxD) {
  return { d: 0.06, maxD, rev: [], last: null, trials: 0, missMax: 0,
    get done() { return this.rev.length >= 6 || this.trials >= 16 || this.missMax >= 2; },
    get threshold() {
      if (this.missMax >= 2) return this.maxD;
      const r = this.rev.slice(-4);
      return r.length ? Math.exp(r.reduce((s, x) => s + Math.log(x), 0) / r.length) : this.d;
    },
    answer(ok) {
      this.trials++;
      if (this.last !== null && this.last !== ok) this.rev.push(this.d);
      this.last = ok;
      if (!ok && this.d >= this.maxD * 0.99) this.missMax++;
      this.d = ok ? Math.max(this.d / 1.6, 0.002) : Math.min(this.d * 1.6, this.maxD);
    } };
}

/// Grenzwerte großzügig, weil Fernseher und Raumlicht nicht kalibriert sind.
function classify([p, d, b]) {
  const rg = Math.max(p, d), sev = x => x > 0.06 ? 1 : 0.5;
  if (rg <= 0.02 && b <= 0.035) return { vision: 'normal', severity: 0 };
  if (rg > 0.04 && b > 0.06) return { vision: 'achromat', severity: 1 };
  if (rg > 0.02 && rg >= b * 0.8) return { vision: p > d * 1.25 ? 'protan' : 'deutan', severity: sev(rg) };
  return { vision: 'tritan', severity: sev(b) };
}

const newTest = () => ({ phase: 'intro', stairs: [0, 1, 2].map(a => stair(CM.maxD(a))), axis: 0, gap: 0, result: null });
let ct = newTest();

function ctNext() {
  const open = [0, 1, 2].filter(a => !ct.stairs[a].done);
  if (!open.length) {
    const th = ct.stairs.map(s => s.threshold);
    ct.result = { ...classify(th), th };
    ct.phase = 'result';
  } else {
    ct.axis = open[Math.floor(Math.random() * open.length)];
    ct.gap = Math.floor(Math.random() * 4);
    ct.phase = 'trial';
  }
  show('colortest', current.data, ct.phase === 'result' ? 'adopt' : undefined);
}

views.colortest = d => {
  if (ct.phase === 'trial') {
    const done = ct.stairs.reduce((s, x) => s + Math.min(x.trials, 16), 0);
    const arrow = (v, name, s) => `<button class="btn" data-a="ctAnswer" data-v="${v}" aria-label="${s}">${icon(name)}</button>`;
    return `<section class="plate"><canvas id="plate" aria-label="${esc(t('Punktfeld mit Ring – wo ist die Lücke?'))}"></canvas>
      <div class="progress"><i style="width:${Math.min(done / 36, 0.97) * 100}%"></i></div>
      <div class="row-btns">${arrow(0, 'arrow-up', '↑')}${arrow(1, 'arrow-down', '↓')}${arrow(2, 'arrow-left', '←')}${arrow(3, 'arrow-right', '→')}
        <button class="btn" data-a="ctAnswer" data-v="none">${esc(t('Kein Ring'))}</button></div></section>`;
  }
  if (ct.phase === 'result') {
    const r = ct.result, maxD = ct.stairs.map(s => s.maxD);
    const rows = ['Rot-Achse', 'Grün-Achse', 'Blau-Achse'].map((a, i) => {
      const v = r.th[i];
      return `<p><b>${esc(t(a))}</b> · ${esc(t(v >= maxD[i] * 0.99 ? 'nicht erkannt' : v <= 0.02 ? 'fein' : 'erhöht'))}</p>`;
    }).join('');
    const text = r.vision === 'normal' ? t('Unauffällig – dein Farbsehen wirkt normal.')
      : r.vision === 'achromat' ? t('Du hast auf allen Achsen Farben kaum unterschieden. Das kann an starker Farbsehschwäche liegen – oder an Licht und Bildschirm.')
      : t(r.severity < 1 ? 'Hinweis auf leichte %@.' : 'Hinweis auf deutliche %@.', t(VISION_TITLE[r.vision]));
    return `${stepLine(4, d)}<h1>${esc(t('Ergebnis'))}</h1><p class="intro">${esc(text)}</p>${rows}
      ${r.vision !== 'normal' ? `<p><b>${esc(t('Empfehlung: Farben für „%@“ anpassen.', t(VISION_TITLE[r.vision])))}</b></p>` : ''}
      <div class="row-btns"><button class="btn primary" data-f data-k="adopt" data-a="ctAdopt">${esc(t(r.vision === 'normal' ? 'Normal übernehmen' : 'Anpassung übernehmen'))}</button>
        <button class="btn" data-f data-k="skip" data-a="ctClose">${esc(t('Nicht übernehmen'))}</button></div>`;
  }
  return `${stepLine(4, d)}<h1>${esc(t('Farbsehen testen'))}</h1>
    <p class="intro">${esc(t('Du siehst ein Punktfeld mit einem Ring, der an einer Stelle offen ist. Zeig mit dem Steuerkreuz, wo die Lücke ist – oben, unten, links oder rechts. Siehst du keinen Ring, drück A. Die Farben werden immer schwächer, bis es schwer wird. Dauer etwa 2 Minuten.'))}</p>
    <p class="dim note">${icon('info')}${esc(t('Kein medizinischer Test: Fernseher und Raumlicht verändern Farben. Für eine Diagnose: Augenarzt.'))}</p>
    <p class="dim note">${icon('tv')}${esc(t('Bildmodus am Fernseher am besten auf „Film“ oder „Kino“, Raum nicht zu hell.'))}</p>
    <div class="row-btns"><button class="btn primary" data-f data-k="start" data-a="ctStart">${esc(t('Test starten'))}</button>
      <button class="btn" data-f data-k="close" data-a="ctClose">${esc(t(d.setup ? 'Später' : 'Abbrechen'))}</button></div>`;
};
views.colortest.after = () => { if (ct.phase === 'trial') drawPlate(); };
// Im Test: Richtung = Antwort, A = „kein Ring“, B = abbrechen.
views.colortest.key = k => {
  if (ct.phase !== 'trial') return false;
  const dir = { up: 0, down: 1, left: 2, right: 3 }[k];
  if (dir !== undefined) actions.ctAnswer(dir);
  else if (k === 'a') actions.ctAnswer('none');
  else if (k === 'b') actions.ctClose();
  return true;
};

function drawPlate() {
  const c = document.getElementById('plate'), size = Math.min(innerHeight * 0.68, innerWidth * 0.9), dpr = devicePixelRatio || 1;
  c.width = c.height = size * dpr; c.style.width = c.style.height = size + 'px';
  const g = c.getContext('2d'); g.scale(dpr, dpr);
  const r = size / 2, dots = [];
  // Punkte zufällig, ohne Überlappung (einfaches Ausprobieren reicht).
  for (let n = 0; n < 2600; n++) {
    const rad = r * (0.014 + Math.random() * 0.026), a = Math.random() * 2 * Math.PI, dist = Math.sqrt(Math.random()) * (r - rad);
    const x = r + Math.cos(a) * dist, y = r + Math.sin(a) * dist;
    if (dots.every(([px, py, pr]) => Math.hypot(px - x, py - y) > pr + rad + r * 0.004)) dots.push([x, y, rad]);
  }
  const gapAngle = [-Math.PI / 2, Math.PI / 2, Math.PI, 0][ct.gap], d = ct.stairs[ct.axis].d;
  for (const [x, y, rad] of dots) {
    const dx = x - r, dy = y - r, dr = Math.hypot(dx, dy) / r;
    let ang = Math.atan2(dy, dx) - gapAngle; ang = Math.atan2(Math.sin(ang), Math.cos(ang));
    const inRing = dr > 0.36 && dr < 0.66 && Math.abs(ang) > 0.42;
    const Y = CM.levels[Math.floor(Math.random() * CM.levels.length)];
    g.fillStyle = CM.css(inRing ? ct.axis : null, inRing ? d : 0, Y);
    g.beginPath(); g.arc(x, y, rad, 0, 2 * Math.PI); g.fill();
  }
}

Object.assign(actions, {
  ctStart() { ct = newTest(); ctNext(); },
  ctAnswer(v) { ct.stairs[ct.axis].answer(v !== 'none' && +v === ct.gap); ctNext(); },
  ctAdopt() {
    const p = me(), r = ct.result;
    p.vision = r.vision; p.severity = r.vision === 'normal' ? 1 : r.severity; save();
    actions.ctClose();
  },
  ctClose() {
    ct = newTest();
    if (!current.data.setup) return back();
    // Einrichtung: weiter zur Genre-Wahl (letzter Schritt), an derselben Stelle im Verlauf.
    history.replaceState({ ...history.state, view: 'genres', data: { setup: true } }, '');
    show('genres', { setup: true });
  },
});

applyLook();
views.eyetest.title = () => t('Kurzer Sehtest');
views.colortest.title = () => t('Farbsehen testen');
