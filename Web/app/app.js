// PopSofa im Browser – für Fire TV (Silk), Windows-PC und Chrome. Keine Abhängigkeiten.
// Bedienung: Pfeiltasten/Fernbedienung, Xbox-Controller (Gamepad-API) oder Maus.
// Daten (Profile, TMDB-Schlüssel) liegen nur in diesem Browser (localStorage).
'use strict';

// MARK: - Kataloge (wie in der Mac-App: Service.swift, Recommendations.swift, Region.swift)

const SERVICES = [
  ['netflix', 'Netflix', 'https://www.netflix.com', '#E50914', '#4A0307'],
  ['prime', 'Prime Video', 'https://www.primevideo.com', '#00A8E1', '#0B2A4A'],
  ['youtube', 'YouTube', 'https://www.youtube.com', '#FF0033', '#4A0010'],
  ['disney', 'Disney+', 'https://www.disneyplus.com', '#113CCF', '#0A1433'],
  ['appletv', 'Apple TV+', 'https://tv.apple.com', '#1D1D1F', '#0A0A0B'],
  ['wow', 'WOW', 'https://www.wowtv.de', '#6C3CE1', '#1D0F4A'],
  ['rtlplus', 'RTL+', 'https://plus.rtl.de', '#E2007A', '#4A0030'],
  ['joyn', 'Joyn', 'https://www.joyn.de', '#E8A600', '#4A3600'],
  ['ard', 'ARD Mediathek', 'https://www.ardmediathek.de', '#0A5BE0', '#04204A'],
  ['zdf', 'ZDF Mediathek', 'https://www.zdf.de', '#FA7D19', '#4A2406'],
  ['paramount', 'Paramount+', 'https://www.paramountplus.com', '#0064FF', '#001F4D'],
  ['hbomax', 'HBO Max', 'https://www.hbomax.com', '#002BE7', '#00104F'],
  ['dazn', 'DAZN', 'https://www.dazn.com', '#0C161C', '#000000'],
  ['crunchyroll', 'Crunchyroll', 'https://www.crunchyroll.com', '#F47521', '#4A2306'],
  ['twitch', 'Twitch', 'https://www.twitch.tv', '#9146FF', '#2A1550'],
  ['spotify', 'Spotify', 'https://open.spotify.com', '#1DB954', '#0A3D1C'],
].map(([id, name, url, c1, c2]) => ({ id, name, url, c1, c2 }));
const DEFAULT_SERVICES = ['netflix', 'prime', 'youtube', 'disney', 'appletv'];

// ponytail: feste TMDB-Anbieter-IDs (die Mac-App lernt sie pro Land nach); neu lernen, falls Zuordnung hakt.
const PROVIDERS = {
  netflix: [8, 1796], prime: [9, 119, 2100], disney: [337], appletv: [350], wow: [30], rtlplus: [298],   // nicht 2 = Apple-Store (Kauf/Leihe)
  joyn: [304], ard: [219], zdf: [537], paramount: [531, 582], hbomax: [1899, 384], crunchyroll: [283], youtube: [188],
};
const SEARCH = {
  netflix: 'https://www.netflix.com/search?q=', prime: 'https://www.primevideo.com/search?phrase=',
  disney: 'https://www.disneyplus.com/search?q=', appletv: 'https://tv.apple.com/search?term=',
  youtube: 'https://www.youtube.com/results?search_query=', zdf: 'https://www.zdf.de/suche?q=',
  ard: 'https://www.ardmediathek.de/suche/', crunchyroll: 'https://www.crunchyroll.com/search?q=',
};

const LANGS = ['de', 'pt', 'en', 'es', 'fr', 'it', 'nl'];   // für Titel und Beschreibungen
const UI_LANGS = ['de', 'pt', 'en'];                        // für die Oberfläche (Rest → Englisch)
const COUNTRIES = ['DE', 'PT', 'AT', 'CH', 'ES', 'FR', 'IT', 'NL', 'GB', 'US', 'BR'];
const COUNTRY = { DE: 'Deutschland', PT: 'Portugal', AT: 'Österreich', CH: 'Schweiz', ES: 'Spanien', FR: 'Frankreich',
  IT: 'Italien', NL: 'Niederlande', GB: 'Großbritannien', US: 'USA', BR: 'Brasilien' };
const COUNTRY_LANG = { DE: 'de-DE', AT: 'de-AT', CH: 'de-CH', PT: 'pt-PT', BR: 'pt-BR', ES: 'es-ES', FR: 'fr-FR',
  IT: 'it-IT', NL: 'nl-NL', GB: 'en-GB', US: 'en-US' };
const LANG_TMDB = { de: 'de-DE', pt: 'pt-PT', en: 'en-US', es: 'es-ES', fr: 'fr-FR', it: 'it-IT', nl: 'nl-NL' };
const COLORS = ['#FF7BCB', '#FFD23F', '#2EBFA0', '#5C9BFF', '#FF8A3D', '#B98CFF'];

// Texte nur für die Web-App: [Português, English]. Alles andere kommt aus i18n.js (= L10n.swift).
const EXTRA = {
  'Titel suchen …': ['Pesquisar títulos…', 'Search titles…'],
  'Einstellungen': ['Definições', 'Settings'],
  'Für alle Profile in diesem Browser.': ['Para todos os perfis neste browser.', 'For all profiles in this browser.'],
  'Profil löschen?': ['Apagar perfil?', 'Delete profile?'],
  'Öffnet in neuem Tab': ['Abre num novo separador', 'Opens in a new tab'],
  'aus %@': ['de %@', 'from %@'],
};

// MARK: - Zustand

let S = load();
S.uiLang ??= deviceLang();
function load() {
  try { const s = JSON.parse(localStorage.getItem('popsofa')); if (s && Array.isArray(s.profiles)) return s; } catch (e) {}
  return { key: '', profiles: [], active: null, uiLang: deviceLang() };
}
// Gerätesprache vor der Profilwahl: Browsersprache, falls PopSofa sie kann, sonst Deutsch.
function deviceLang() {
  const l = (navigator.language || 'de').slice(0, 2);
  return UI_LANGS.includes(l) ? l : 'de';
}
function save() { try { localStorage.setItem('popsofa', JSON.stringify(S)); } catch (e) {} }
const me = () => S.profiles.find(p => p.id === S.active) || S.profiles[0];

// Oberflächensprache: de/pt/en, andere Beschreibungssprachen → Englisch (wie L10n.ui).
let draftLang = null;   // beim Bearbeiten sofort sichtbar, noch bevor gespeichert ist
// Vor der Profilwahl („Wer schaut?“) gilt die Gerätesprache, danach die des Profils.
const noProfile = () => !me() || current?.view === 'picker';
function ui() {
  const l = draftLang || (noProfile() ? S.uiLang : me().lang) || 'de';
  return ['de', 'pt'].includes(l) ? l : 'en';
}
function t(s, ...args) {
  const e = L10N[s] || EXTRA[s], u = ui();
  const parts = (u === 'de' || !e ? s : e[u === 'pt' ? 0 : 1]).split('%@');
  return parts.reduce((out, p, i) => out + (i ? String(args[i - 1] ?? '%@') : '') + p, '');
}
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function toast(msg) {
  const el = document.getElementById('toast');
  el.textContent = msg; el.classList.add('show');
  clearTimeout(toast.timer); toast.timer = setTimeout(() => el.classList.remove('show'), 2600);
}

// MARK: - TMDB

function tmdbLang(p = me()) {
  const def = (COUNTRY_LANG[p.country] || 'de-DE').slice(0, 2);
  return def === p.lang ? COUNTRY_LANG[p.country] : LANG_TMDB[p.lang] || 'de-DE';
}
async function tmdb(path, query = {}) {
  const u = new URL('https://api.themoviedb.org/3' + path), headers = {};
  for (const [k, v] of Object.entries(query)) if (v !== '' && v != null) u.searchParams.set(k, v);
  u.searchParams.set('language', tmdbLang());
  // Neuer „Read Access Token“ (mit Punkten) per Header, alter API-Key per Parameter.
  if (S.key.includes('.')) headers.Authorization = 'Bearer ' + S.key; else u.searchParams.set('api_key', S.key);
  const r = await fetch(u, { headers });
  if (!r.ok) throw new Error(String(r.status));
  return r.json();
}
const item = (r, type) => ({
  id: r.id, type: type || r.media_type, name: r.title || r.name || '', poster: r.poster_path, backdrop: r.backdrop_path,
  year: (r.release_date || r.first_air_date || '').slice(0, 4), rating: r.vote_average || 0, overview: r.overview || '',
  genres: r.genre_ids || (r.genres || []).map(g => g.id), votes: r.vote_count, lang: r.original_language,
});
const mix = (a, b) => a.flatMap((x, i) => [x, b[i]]).concat(b.slice(a.length)).filter(Boolean);
const img = (path, w = 'w342') => path ? `https://image.tmdb.org/t/p/${w}${path}` : '';
const serviceFor = pid => Object.keys(PROVIDERS).find(s => PROVIDERS[s].includes(pid));
/// Land des Kontos für einen Dienst – ohne eigene Angabe das Streaming-Land des Profils.
const regionOf = (p, sid) => p.serviceCountries?.[sid] || p.country;

const rowCache = {};
// loadRows (Empfehlungsreihen mit Geschmack und Watchlist) steht in taste.js.

// MARK: - Navigation (Verlauf = Zurück-Taste von Fire TV und Browser)

const views = {};
let current = null;
function go(view, data = {}) {
  pending = null;   // nicht wiederhergestellte Position verfällt beim Weitergehen
  // Für „Zurück“ merken: Fokus, Seiten-Scroll und Scroll jeder Reihe – damit nichts sichtbar zurückspult.
  history.replaceState({ ...history.state, focus: document.activeElement?.dataset?.k,
    scroll: { y: scrollY, shelves: [...document.querySelectorAll('.shelf')].map(s => s.scrollLeft) } }, '');
  const trail = history.state?.trail || [{ view: history.state?.view || 'home', data: history.state?.data || {} }];
  history.pushState({ view, data, depth: (history.state?.depth || 0) + 1, trail: [...trail, { view, data }] }, '');
  show(view, data);
}
// Zurück nur innerhalb der App (Tiefe 0 = Startansicht); die Fire-TV-Taste darf trotzdem den Browser-Verlauf nehmen.
function back() {
  if (osk) return oskClose();      // erst die Bildschirmtastatur …
  if (sel) return closeSelect();   // … oder eine offene Auswahlliste schließen
  if (history.state?.depth > 0) history.back();
}
function reset(view) { pending = null; history.replaceState({ view, depth: 0 }, ''); show(view); }
addEventListener('popstate', e => {
  pending = e.state?.scroll ? { focus: e.state.focus, ...e.state.scroll } : null;
  show(e.state?.view || 'home', e.state?.data || {}, e.state?.focus);
});

/// Gemerkte Position wiederherstellen – sofort, ohne Animation. Bei nachgeladenen Inhalten (Reihen, Suchergebnisse)
/// ruft die Ansicht das erneut auf, sobald sie gezeichnet sind; erledigt ist es, wenn das gemerkte Element da ist.
let pending = null;
function restorePending() {
  if (!pending) return false;
  document.querySelectorAll('.shelf').forEach((s, i) => { s.scrollLeft = pending.shelves[i] || 0; });
  scrollTo({ top: pending.y, behavior: 'instant' });
  const el = pending.focus && document.querySelector(`[data-k="${CSS.escape(pending.focus)}"]`);
  if (!el) return false;
  el.focus({ preventScroll: true });
  pending = null;
  return true;
}

function show(view, data = {}, focusKey) {
  if (view !== 'edit') draftLang = null;
  if (sel) { sel = null; Object.assign(document.getElementById('sheet'), { hidden: true, innerHTML: '' }); }
  current = { view, data };
  document.documentElement.lang = ui();
  // Die Chrome-Erweiterung liest hier Profilname und Zoomstufe (für Netflix & Co.).
  document.title = me() ? `PopSofa · ${me().name}${zoom() !== 1 ? ' · ' + pct(zoom()) : ''}` : 'PopSofa';
  const app = document.getElementById('app');
  app.innerHTML = crumbs(view, data) + views[view](data);
  document.getElementById('hints').innerHTML = hints(view);
  if (typeof applyLook === 'function') applyLook();   // Schriftgröße + Farbanpassung des Profils (vision.js)
  if (!restorePending()) { if (!pending) scrollTo(0, 0); focusKey && !pending ? refocus(focusKey) : !pending && first(); }
  views[view].after?.(data, focusKey);
}
// Erster Fokus im Inhalt – nicht auf „Zurück“, das ist mit B/Zurück-Taste ohnehin da.
function first() { (document.querySelector('[data-f]:not([data-k="back"])') || document.querySelector('[data-f]'))?.focus(); }

/// Navigationsleiste auf jeder Unterseite: „‹ Zurück“ + Pfad (PopSofa › Einstellungen › Sehtest), damit man weiß, wo man ist.
const titleOf = (view, data) => views[view]?.title?.(data) || '';
function crumbs(view, data) {
  const st = history.state;
  if (!(st?.depth > 0)) return '';
  const path = [...(st.trail || []).slice(0, -1), { view, data }].map(c => titleOf(c.view, c.data)).filter(Boolean);
  return `<nav class="crumbs" aria-label="${esc(t('Zurück'))}"><button class="btn" data-f data-k="back" data-a="back">${icon('chevron-left')}${esc(t('Zurück'))}</button>
    <ol>${path.map((p, i) => `<li${i === path.length - 1 ? ' aria-current="page"' : ''}>${esc(p)}</li>`).join('')}</ol></nav>`;
}
function refocus(k) { const el = k && document.querySelector(`[data-k="${CSS.escape(k)}"]`); el ? focusEl(el) : first(); }
function focusEl(el) { el.focus({ preventScroll: true }); el.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'smooth' }); }

// Tastenhinweise passend zum zuletzt benutzten Gerät: Controller, Tastatur, Maus oder Fire-TV-Fernbedienung.
// Die Fernbedienung meldet sich als Tastatur (Pfeile/Enter/Zurück) – erkannt am Fire-TV-Browser.
const REMOTE = /\bAFT|Silk/.test(navigator.userAgent);
let inputMode = REMOTE ? 'remote' : 'mouse';   // Controller meldet sich erst beim ersten Tastendruck
document.body.classList.toggle('mouse', inputMode === 'mouse');
function setInput(m) {
  if (m === 'keyboard' && REMOTE) m = 'remote';
  if (m === inputMode) return;
  inputMode = m;
  document.body.classList.toggle('mouse', m === 'mouse');   // Maus: Reihen-Pfeile dauerhaft sichtbar
  if (current) document.getElementById('hints').innerHTML = hints(current.view);
}
// Tasten je Gerät; fehlt eine (z. B. X/Y auf Maus oder Fernbedienung), entfällt der Hinweis – dort helfen die Knöpfe.
const GLYPH = {
  pad: { a: 'A', b: 'B', x: 'X', y: 'Y', dpad: '✥' },
  keyboard: { a: '↵', b: 'Esc', x: 'L', y: 'N', dpad: '← → ↑ ↓', search: '/' },
  remote: { a: 'OK', b: () => icon('undo-2'), dpad: '✥' },
  mouse: { a: () => icon('mouse-pointer-click') },
};
function hints(view) {
  if (osk && inputMode !== 'mouse') return inputMode === 'remote'
    ? `<span><b>OK</b>${esc(t('Auswählen'))}</span><span><b>${icon('undo-2')}</b>${esc(t('Schließen'))}</span>`
    : [['A', t('Auswählen')], ['X', '⌫'], ['Y', t('Leertaste')], ['LB', '⇧'], ['RB', '↵'], ['B', t('Schließen')]]
      .map(([k, s]) => `<span><b>${k}</b>${esc(s)}</span>`).join('');
  const h = view === 'home' ? [['a', 'Öffnen'], ['x', 'Suchen', 'search'], ['y', 'Einstellungen', 'none']]
    : view === 'picker' ? [['a', 'Auswählen'], ['x', 'Bearbeiten', 'none']]
    : view === 'detail' ? [['a', 'Auswählen'], ['x', 'Gefällt mir'], ['y', 'Nicht mein Fall'], ['b', 'Zurück']]
    : view === 'colortest' && ct.phase === 'trial' ? [['dpad', 'Wo ist die Lücke?'], ['a', 'Kein Ring zu sehen'], ['b', 'Abbrechen']]
    : [['a', 'Auswählen'], ['b', 'Zurück']];
  const g = GLYPH[inputMode];
  if (inputMode !== 'mouse' && inputMode !== 'pad' && view !== 'colortest') h.unshift(['dpad', 'Auswahl']);
  return h.map(([k, text, kb]) => {
    // Tastatur: eigene Taste für Suchen („/“); X/Y-Funktionen ohne Taste fallen weg.
    const key = inputMode === 'keyboard' && kb ? (kb === 'none' ? null : g[kb]) : g[k];
    if (!key) return '';
    return `<span><b>${typeof key === 'function' ? key() : esc(key)}</b>${esc(t(text))}</span>`;
  }).join('');
}

// Maus: echte Bewegung oder Klick schaltet die Hinweise um (nicht bei Touch).
addEventListener('pointermove', e => { if (e.pointerType === 'mouse' && (e.movementX || e.movementY)) setInput('mouse'); });
addEventListener('pointerdown', e => { if (e.pointerType === 'mouse') setInput('mouse'); });

// Klicks über data-a="aktion" + data-v="wert", damit kein Inline-JS im HTML steht.
const actions = {};
document.addEventListener('click', e => {
  const el = e.target.closest('[data-a]');
  if (el) actions[el.dataset.a](el.dataset.v, el);
});

// Toolbar (Stil, Textgröße, Sprache): Icon + Kürzel der aktuellen Wahl; öffnet die Auswahlliste.
// Sprachen stehen in der aktuellen Oberflächensprache und in sich selbst („German – Deutsch“).
/// Icons aus Lucide (vendor/lucide.min.js, ISC-Lizenz, lokal – kein CDN): icon('thumbs-up') → <svg …>.
/// Namen wie auf lucide.dev/icons. Unbekannter Name → leer (fällt nicht auf, bricht nichts).
const iconCache = {};
function icon(name) {
  if (name in iconCache) return iconCache[name];
  const node = window.lucide?.icons?.[name.replace(/(^|-)(\w)/g, (_, __, c) => c.toUpperCase())];
  if (!node) return (iconCache[name] = '');
  const el = lucide.createElement(node);
  el.setAttribute('aria-hidden', 'true');
  el.classList.add('icon');
  return (iconCache[name] = el.outerHTML);
}
const ICON = { lang: icon('globe'), theme: icon('palette'), size: '<b aria-hidden="true">Aa</b>', settings: icon('settings') };
const cap = s => s ? s[0].toLocaleUpperCase() + s.slice(1) : s;
const langName = (code, inLang) => cap(new Intl.DisplayNames([inLang], { type: 'language' }).of(code));
const THEMES = [['apple', 'Apple'], ['pop', 'Pop-Art'], ['woven', 'Webmuster'], ['clear', 'Klar dunkel'], ['clearLight', 'Klar hell'], ['popLight', 'Pop hell (Prismen)']];
// Kurzbeschreibung der Lesbarkeits-Stile in der Auswahlliste (wie in der Mac-App).
const THEME_DETAIL = { clear: 'Dunkel, ruhig, gedämpftes Weiß', clearLight: 'Hell und warm, abends gedimmt', popLight: 'Pop-Art hell, ruhig hinter Text' };
const SIZES = [['auto', 'Auto'], ['small', 'Klein'], ['normal', 'Mittel'], ['large', 'Groß'], ['xlarge', 'Sehr groß']];
const SIZE_FACTOR = { small: 0.85, normal: 1, large: 1.5, xlarge: 2 };   // wie TextSize in der Mac-App
// Zoomstufen von Chrome/Edge (wie BrowserZoom in der Mac-App): Textgröße rastet darauf ein, Groß = 150 %.
// Klein: Chromes 90 % (die Mac-App zoomt Browser nur hinein und bleibt dort bei 100 %).
const ZOOM_LEVELS = [0.9, 1, 1.1, 1.25, 1.5, 1.75, 2];
/// Zoomfaktor des Profils: Auto = Sehtest-Faktor, feste Stufen wie gewählt (Sehtest gilt dann nicht – wie am Mac).
function zoom(p = me()) {
  const s = SIZE_FACTOR[p?.size] ?? (p?.scale || 1);
  const near = ZOOM_LEVELS.reduce((a, b) => Math.abs(b - s) < Math.abs(a - s) ? b : a);
  return s >= 1.03 && near < 1.1 ? 1.1 : near;   // leicht vergrößert → mindestens eine Stufe
}
const pct = z => Math.round(z * 100) + ' %';
const themeOf = () => { const v = (noProfile() ? S.theme : me().theme) || S.theme || 'pop'; return v === 'afro' ? 'woven' : v; };   // 'afro': Name bis Version 1.0
const menuValue = kind => ({ lang: ui(), theme: themeOf(), size: me()?.size || 'auto' })[kind];

function menuOptions(kind) {
  const u = ui();
  return kind === 'lang'
    ? UI_LANGS.map(l => ({ v: l, html: l === u ? `<span lang="${l}">${esc(langName(l, l))}</span>`
        : `${esc(langName(l, u))} – <span lang="${l}">${esc(langName(l, l))}</span>` }))
    : kind === 'theme' ? THEMES.map(([v, n]) => ({ v, html: esc(t(n)), detail: THEME_DETAIL[v] && t(THEME_DETAIL[v]) }))
    : SIZES.map(([v, n]) => ({ v, html: esc(t(n)), detail: pct(zoom({ ...me(), size: v })) }));
}
const menuLabel = kind => t({ lang: 'Sprache', theme: 'Stil', size: 'Textgröße' }[kind]);
function toolMenu(kind) {
  const cur = menuValue(kind), plain = (menuOptions(kind).find(o => o.v === cur)?.html || '').replace(/<[^>]+>/g, '');
  const short = kind === 'lang' ? cur.toUpperCase() : kind === 'size' ? pct(zoom()) : '';
  return `<button class="langbtn" data-f data-k="${kind}btn" data-a="menu" data-v="${kind}" aria-haspopup="dialog"
    aria-label="${esc(menuLabel(kind) + ': ' + plain)}" title="${esc(menuLabel(kind))}">${ICON[kind]}${short ? `<span>${short}</span>` : ''}</button>`;
}

// Auswahlliste (wie in der Mac-App): Panel in der Mitte, je Option eine Zeile mit Radio-Marke und optionalem Detail.
// ↑↓ / Steuerkreuz wählt, A / Enter / Klick übernimmt und schließt, B / Esc / Klick daneben schließt ohne Änderung.
// Ersetzt alle Knöpfe, die per Klick mehrere Zustände durchschalten.
let sel = null;   // { title, options: [{ v, html, detail }], cur, pick(v), from }
function openSelect(cfg) {
  sel = { ...cfg, from: document.activeElement?.dataset?.k };
  const box = document.getElementById('sheet');
  box.innerHTML = `<div class="sheet-bg" data-a="selClose"></div>
    <div class="sheet" role="dialog" aria-modal="true" aria-label="${esc(cfg.title)}"><h2>${esc(cfg.title)}</h2>
    <div role="radiogroup">${cfg.options.map((o, i) => `<button role="radio" aria-checked="${o.v === cfg.cur}" data-f data-k="opt${i}"
      data-a="selPick" data-v="${i}"><span class="radio" aria-hidden="true"></span><span>${o.html}${o.detail
        ? `<small>${esc(o.detail)}</small>` : ''}</span></button>`).join('')}</div></div>`;
  box.hidden = false;
  if (typeof applyLook === 'function') applyLook();
  focusEl(box.querySelector(`[data-k="opt${Math.max(0, cfg.options.findIndex(o => o.v === cfg.cur))}"]`));
}
function closeSelect() {
  const k = sel?.from;
  sel = null;
  Object.assign(document.getElementById('sheet'), { hidden: true, innerHTML: '' });
  refocus(k);
}
const flag = c => String.fromCodePoint(...[...c].map(ch => 127397 + ch.charCodeAt(0)));

// MARK: - Ansichten

function greeting() {
  const h = new Date().getHours();
  return t(h < 5 ? 'Gute Nacht' : h < 11 ? 'Guten Morgen' : h < 18 ? 'Guten Tag' : 'Guten Abend');
}
const clock = () => new Date().toLocaleTimeString(ui(), { hour: '2-digit', minute: '2-digit' });
setInterval(() => { const c = document.querySelector('time'); if (c) c.textContent = clock(); }, 10000);

const poster = (x, k) => `<button class="poster" data-f data-k="${k}" data-a="detail" data-v="${x.type}:${x.id}">
  <img loading="lazy" alt="" src="${img(x.poster)}"><span>${esc(x.name)}</span></button>`;
const titles = {};   // id → Titel, für die Detailansicht

// Reihen ohne seitliches Mausrad: Pfeile links/rechts blättern eine Bildschirmbreite weiter.
// Am Anfang bzw. Ende ist der jeweilige Pfeil ausgeblendet. (Controller/Tastatur scrollen über den Fokus.)
function shelfArrows(s) {
  const w = s.parentElement;
  w.querySelector('.prev').hidden = s.scrollLeft < 8;
  w.querySelector('.next').hidden = s.scrollLeft + s.clientWidth > s.scrollWidth - 8;
}
actions.shelf = (dir, btn) => {
  const s = btn.parentElement.querySelector('.shelf');
  s.scrollBy({ left: +dir * s.clientWidth * 0.85, behavior: 'smooth' });
};

views.home = () => {
  const p = me();
  const tiles = SERVICES.filter(s => p.services.includes(s.id)).map(s =>
    `<button class="tile" data-f data-k="s-${s.id}" data-a="open" data-v="${s.id}" title="${esc(t('Öffnet in neuem Tab'))}"
      style="background:linear-gradient(135deg,${s.c1},${s.c2})">${esc(s.name)}</button>`).join('');
  return `<header><div><h1>PopSofa</h1><p class="dim">${esc(greeting())}</p></div><span class="sp"></span>${toolMenu('theme')}${toolMenu('size')}${toolMenu('lang')}
    <button class="round" data-f data-k="profile" data-a="picker" title="${esc(t('Profil wechseln'))}" style="background:${p.color}">${esc(p.name[0]?.toUpperCase())}</button>
    <button class="round" data-f data-k="settings" data-a="edit" data-v="${p.id}" title="${esc(t('Einstellungen'))}"
      aria-label="${esc(t('Einstellungen'))}">${ICON.settings}</button>
    <time>${clock()}</time></header>
    <section class="tiles"><button class="tile util" data-f data-k="search" data-a="search">${icon('search')} ${esc(t('Suchen'))}</button>${S.profiles.length > 1
      ? `<button class="tile util" data-f data-k="ours" data-a="ours">${icon('users')} ${esc(t('Unsere Watchlist'))}</button>` : ''}${tiles}</section>
    <div id="rows">${S.key ? `<p class="dim" style="margin-top:2rem">${esc(t('Lade Empfehlungen …'))}</p>`
      : `<h2>${esc(t('Empfehlungen einrichten'))}</h2><p class="dim">${esc(t('Neue Filme & Serien nach deinem Geschmack – mit kostenlosem TMDB-Schlüssel.'))}</p>
         <div class="row-btns"><button class="btn primary" data-f data-k="key" data-a="edit" data-v="${p.id}">${esc(t('TMDB-Schlüssel'))}</button></div>`}</div>`;
};
views.home.after = async (_, focusKey) => {
  if (!focusKey) refocus('search');   // am Fernseher bei den Kacheln starten, nicht oben in der Kopfzeile
  else if (pending && !S.key) restorePending();
  if (!S.key) return;
  const box = document.getElementById('rows');
  try {
    const rows = await loadRows();
    if (current.view !== 'home') return;
    box.innerHTML = rows.map(([title, list], r) => `<h2>${esc(title)}</h2><div class="shelfwrap">
      <button class="shelfnav prev" data-a="shelf" data-v="-1" aria-label="${esc(t('Nach vorn'))}" hidden>${icon('chevron-left')}</button>
      <div class="shelf">${list.map((x, i) => { titles[x.type + ':' + x.id] = x; return poster(x, `r${r}-${i}`); }).join('')}</div>
      <button class="shelfnav next" data-a="shelf" data-v="1" aria-label="${esc(t('Nach hinten'))}">${icon('chevron-right')}</button></div>`).join('');
    box.querySelectorAll('.shelf').forEach(s => { s.addEventListener('scroll', () => shelfArrows(s), { passive: true }); shelfArrows(s); });
    verifyPosters(box, rows[0]?.[0] === t('Meine Watchlist') ? box.querySelector('.shelf') : null);
    if (!restorePending() && focusKey?.startsWith('r')) refocus(focusKey);
  } catch (e) {
    box.innerHTML = `<p class="dim" style="margin-top:2rem">${esc(t(e.message === '401'
      ? 'TMDB-Schlüssel ungültig – A zum Ändern' : 'Empfehlungen nicht erreichbar – A für Schlüssel, später erneut'))}</p>`;
  }
};

views.picker = () => `<header><span class="sp"></span>${toolMenu('theme')}${toolMenu('lang')}</header><section class="picker"><h1>${esc(t('Wer schaut?'))}</h1><div class="avatars">${
  S.profiles.map(p => `<button class="avatar" data-f data-k="p-${p.id}" data-a="choose" data-v="${p.id}">
    <b style="background:${p.color}">${esc(p.name[0]?.toUpperCase())}</b>${esc(p.name)}</button>`).join('')}
  <button class="avatar" data-f data-k="p-new" data-a="edit"><b style="background:#222;color:#fff">${icon('plus')}</b>${esc(t('Profil hinzufügen'))}</button>
  </div></section>`;
views.picker.after = (_, focusKey) => { if (!focusKey) refocus('p-' + S.active); };

views.search = d => `<h1>${esc(t('Suchen'))}</h1>
  <form class="form" data-search><input data-f data-k="q" name="q" enterkeyhint="search" autocomplete="off"
    placeholder="${esc(t('Titel suchen …'))}" value="${esc(d.q || '')}"></form>
  <p class="dim" id="status"></p><div class="grid" id="results"></div>`;
views.search.after = d => { if (d.q) runSearch(d.q); };
document.addEventListener('submit', e => {
  if (!e.target.matches('[data-search]')) return;
  e.preventDefault();
  const q = e.target.q.value.trim();
  if (q) { history.replaceState({ ...history.state, data: { q } }, ''); runSearch(q); }
});
async function runSearch(q) {
  const status = document.getElementById('status'), box = document.getElementById('results');
  if (!S.key) {   // ohne Schlüssel keine Suche – Knopf zum Eintragen statt automatisch weiterzuleiten
    status.textContent = t('Neue Filme & Serien nach deinem Geschmack – mit kostenlosem TMDB-Schlüssel.');
    box.innerHTML = `<button class="btn primary" data-f data-k="key" data-a="edit" data-v="${me().id}">${esc(t('TMDB-Schlüssel'))}</button>`;
    return;
  }
  status.textContent = t('Suche …');
  try {
    const r = await tmdb('/search/multi', { query: q });
    const list = r.results.filter(x => x.media_type === 'movie' || x.media_type === 'tv').map(x => item(x));
    status.textContent = list.length ? t('Titel „%@“', q) : t('Nichts gefunden – anders formulieren?');
    box.innerHTML = list.map((x, i) => { titles[x.type + ':' + x.id] = x; return poster(x, 'res' + i); }).join('');
  } catch (e) { status.textContent = t('Suche fehlgeschlagen – Internet/TMDB-Schlüssel prüfen'); }
}

views.detail = d => {
  const x = titles[d.key] || { name: '', overview: '' };
  const meta = [x.type === 'tv' ? t('Serie') : t('Film'), x.year, x.rating ? '★ ' + x.rating.toFixed(1) : ''].filter(Boolean).join('  ·  ');
  return `<div class="backdrop" style="background-image:url('${img(x.backdrop, 'w1280')}')"></div>
    <section class="detail"><img alt="" src="${img(x.poster, 'w500')}"><div>
      <h1 style="color:#fff">${esc(x.name)}</h1><p class="dim">${esc(meta)}</p>
      <div class="row-btns" id="tastebtns">${x.id ? tasteButtons(x) : ''}</div>
      <div id="trailerbox"></div>
      <p class="overview">${esc(x.overview || t('Keine Beschreibung verfügbar.'))}</p>
      <h2>${esc(t('Ansehen bei'))}</h2><div class="row-btns" id="providers"><p class="dim">${esc(t('Lade Anbieter …'))}</p></div>
    </div></section>`;
};
views.detail.after = async d => {
  const [type, id] = d.key.split(':'), p = me(), box = document.getElementById('providers');
  try {
    const r = await tmdb(`/${type}/${id}`, { append_to_response: 'watch/providers,videos', include_video_language: `${p.lang},en,null` });
    const had = !!titles[d.key];
    const x = titles[d.key] = { ...item(r, type), ...titles[d.key], overview: r.overview || titles[d.key]?.overview };
    if (!had) return redraw();   // direkt geladen (z. B. nach Neuladen): Kopf mit Titel und Bild neu zeichnen
    // Wie Region.combine in der Mac-App: im Heimatland alles außer eigenen Diensten mit Konto anderswo;
    // diese nur im Land ihres Kontos (z. B. HBO Max aus Portugal, Prime aus Deutschland).
    const res = r['watch/providers']?.results || {};
    const offersIn = c => { const g = res[c] || {}; return [...(g.flatrate || []), ...(g.free || []), ...(g.ads || [])].map(o => serviceFor(o.provider_id)).filter(Boolean); };
    const abroad = s => p.services.includes(s) && regionOf(p, s) !== p.country;
    const sids = [...new Set([...offersIn(p.country).filter(s => !abroad(s)), ...p.services.filter(s => abroad(s) && offersIn(regionOf(p, s)).includes(s))])]
      .sort((a, b) => p.services.includes(b) - p.services.includes(a));
    if (current.view !== 'detail') return;
    const trailer = pickTrailer(r.videos?.results || [], p.lang);
    if (trailer) {
      // Trailer sofort abspielen (wie in der Mac-App); A auf dem Knopf = Pause/Fortsetzen.
      document.getElementById('trailerbox').innerHTML = `<div class="trailer"><iframe id="yt" title="Trailer"
        allow="autoplay; encrypted-media; fullscreen" allowfullscreen
        src="https://www.youtube-nocookie.com/embed/${encodeURIComponent(trailer)}?autoplay=1&enablejsapi=1&playsinline=1&rel=0&modestbranding=1&origin=${encodeURIComponent(location.origin)}"></iframe></div>`;
      trailerPaused = false;
    }
    box.innerHTML = (trailer ? trailerButton() : '') + (sids.length ? sids.map((s, i) => {
      const svc = SERVICES.find(v => v.id === s), mine = p.services.includes(s), name = abroad(s) ? `${svc.name} ${flag(regionOf(p, s))}` : svc.name;
      return `<button class="btn ${mine ? 'primary' : ''}" data-f data-k="prov${i}" data-a="open" data-v="${s}|${esc(x.name)}">
        ${esc(mine ? t('%@ · deine Dienste', name) : name)}</button>`;
    }).join('') : `<p class="dim">${esc(t('In %@ gerade nicht im Stream.', t(COUNTRY[p.country])))}</p>`);
    document.querySelector(trailer ? '[data-k="trailer"]' : '[data-k="prov0"]')?.focus();
  } catch (e) { box.innerHTML = `<p class="dim">${esc(t('Empfehlungen nicht erreichbar – A für Schlüssel, später erneut'))}</p>`; }
};

/// YouTube-Trailer: Sprache des Profils vor Englisch, „Trailer“ vor „Teaser“, offizielle zuerst.
function pickTrailer(videos, lang) {
  const rank = v => (v.iso_639_1 === lang ? 0 : 2) + (v.type === 'Trailer' ? 0 : 1) + (v.official ? 0 : 0.5);
  return videos.filter(v => v.site === 'YouTube' && (v.type === 'Trailer' || v.type === 'Teaser'))
    .sort((a, b) => rank(a) - rank(b))[0]?.key;
}
let trailerPaused = false;
const trailerButton = () => `<button class="btn" data-f data-k="trailer" data-a="trailer">${trailerPaused ? icon('play') + esc(t('Fortsetzen')) : icon('pause') + esc(t('Pause'))}</button>`;
function ytCommand(func) {
  document.getElementById('yt')?.contentWindow?.postMessage(JSON.stringify({ event: 'command', func, args: [] }), '*');
}
/// Trailer verstummt, sobald Netflix & Co. aufgehen oder der Tab in den Hintergrund geht.
function stopTrailer() { const f = document.getElementById('yt'); if (f) { f.remove(); document.querySelector('[data-k="trailer"]')?.remove(); } }
document.addEventListener('visibilitychange', () => {
  if (document.hidden && document.getElementById('yt') && !trailerPaused) {
    ytCommand('pauseVideo'); trailerPaused = true;
    const b = document.querySelector('[data-k="trailer"]'); if (b) b.outerHTML = trailerButton();
  }
});

// Profil anlegen/bearbeiten: Name, Sprache (Oberfläche + Beschreibungen), Land, Dienste, TMDB-Schlüssel.
let draft = null;
views.edit = d => {
  const old = S.profiles.find(p => p.id === d.id);
  if (!draft || draft.id !== (old?.id || 'new'))
    draft = old ? { ...old, services: [...old.services], serviceCountries: { ...(old.serviceCountries || {}) },
      multiRegion: Object.keys(old.serviceCountries || {}).length > 0 }
      : { id: 'new', name: '', color: COLORS[S.profiles.length % COLORS.length], lang: S.uiLang || 'de',
          country: { de: 'DE', pt: 'PT', en: 'GB' }[S.uiLang] || 'DE', services: [...DEFAULT_SERVICES] };
  draftLang = draft.lang;
  return `<h1>${esc(t(old ? 'Profil bearbeiten' : 'Neues Profil'))}</h1>
  <div class="form">
    <label for="name">${esc(t('Dein Name in PopSofa'))}</label>
    <input id="name" data-f data-k="name" value="${esc(draft.name)}" placeholder="${esc(t('z. B. Alex'))}" autocomplete="off">
    <div class="row-btns">
      <button class="btn" data-f data-k="lang" data-a="lang">${esc(t('Sprache: %@', langName(draft.lang, ui())))} ›</button>
    </div>
    <h2>${esc(t('Welche Dienste nutzt du?'))}</h2>
    <div class="regionbar">
      <button class="switch" role="switch" aria-checked="${!!draft.multiRegion}" data-f data-k="multi" data-a="multi">
        <span class="track" aria-hidden="true"><span class="knob"></span></span>${esc(t('Dienste aus verschiedenen Ländern'))}</button>
      ${draft.multiRegion ? '' : `<button class="btn" data-f data-k="country" data-a="country">${esc(t('Streaming-Land: %@', flag(draft.country) + ' ' + t(COUNTRY[draft.country])))} ›</button>`}
    </div>
    <p class="dim">${esc(t(draft.multiRegion ? 'Z. B. HBO Max aus Portugal, Prime aus Deutschland' : 'Wo deine Abos laufen – gilt für alle Dienste.'))}</p>
    <div class="toggles">${SERVICES.map(s => {
      const on = draft.services.includes(s.id), r = regionOf(draft, s.id);
      // Nur mit „Dienste aus verschiedenen Ländern“: neben dem Dienst das Land des Kontos (öffnet die Auswahlliste)
      return `<div class="svcrow"><button class="btn ${on ? 'on' : ''}" data-f data-k="svc-${s.id}" data-a="svc" data-v="${s.id}"
        aria-pressed="${on}">${on ? icon('check') : ''}${esc(s.name)}</button>${on && draft.multiRegion ? `<button class="btn acct"
        data-f data-k="sc-${s.id}" data-a="svcCountry" data-v="${s.id}" title="${esc(t('Land des Kontos'))}"
        aria-label="${esc(t('Land des Kontos: %@', t(COUNTRY[r])))}">${flag(r)} ${r}</button>` : ''}</div>`;
    }).join('')}</div>
    <h2>${esc(t('TMDB-Schlüssel'))}</h2>
    <p class="dim intro">${esc(t('1. Kostenloses Konto auf themoviedb.org anlegen\n2. Einstellungen › API › Schlüssel anfordern (privat)\n3. „API Read Access Token“ oder „API Key“ kopieren und hier einfügen (⌘V oder iPhone)').replace(/ \(⌘V.*\)$/, ''))}
      ${esc(t('Für alle Profile in diesem Browser.'))}</p>
    <p class="dim intro">This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.</p>
    <img src="tmdb-logo.svg" alt="TMDB" width="90" style="margin:4px 0 12px">
    <input id="key" data-f data-k="key" value="${esc(S.key)}" placeholder="${esc(t('Schlüssel einfügen'))}" autocomplete="off" spellcheck="false">
    <div class="row-btns">
      <button class="btn primary" data-f data-k="save" data-a="save">${esc(t('Speichern'))}</button>
      ${old ? `<button class="btn" data-f data-k="eyetest" data-a="goView" data-v="eyetest">${esc(t('Sehtest wiederholen'))}</button>
        <button class="btn" data-f data-k="prism" data-a="goView" data-v="prism">${esc(t('Prismen-Check'))}</button>
        <button class="btn" data-f data-k="colortest" data-a="goView" data-v="colortest">${esc(t('Farbsehen testen'))}</button>
        <button class="btn" data-f data-k="genres" data-a="goView" data-v="genres">${esc(t('Genres'))}</button>` : ''}
      ${old && S.profiles.length > 1 ? `<button class="btn danger" data-f data-k="del" data-a="del">${esc(t('Löschen'))}</button>` : ''}
      ${S.profiles.length ? `<button class="btn" data-f data-k="cancel" data-a="back">${esc(t('Abbrechen'))}</button>` : ''}
    </div>
  </div>`;
};
// Eingaben im Entwurf halten, damit Sprache/Land/Dienste-Wechsel (neu zeichnen) nichts verlieren.
document.addEventListener('input', e => {
  if (e.target.id === 'name' && draft) draft.name = e.target.value;
  if (e.target.id === 'key') S.key = e.target.value.trim();
});
function redraw(k) { show(current.view, current.data, k); }

// MARK: - Aktionen

Object.assign(actions, {
  open(v) {
    const [id, title] = v.split('|'), s = SERVICES.find(x => x.id === id);
    const url = title && SEARCH[id] ? SEARCH[id] + encodeURIComponent(title) : s.url;
    stopTrailer();
    window.open(url, '_blank');
    toast(title ? t('„%@“ bei %@', title, s.name) : s.name);
  },
  detail: v => go('detail', { key: v }),
  trailer() {
    trailerPaused = !trailerPaused;
    ytCommand(trailerPaused ? 'pauseVideo' : 'playVideo');
    document.querySelector('[data-k="trailer"]').outerHTML = trailerButton();
    document.querySelector('[data-k="trailer"]').focus();
  },
  // Tests gelten fürs aktive Profil – beim Bearbeiten eines anderen erst zu ihm wechseln.
  goView(v) { if (draft?.id && draft.id !== 'new') S.active = draft.id; save(); go(v); },
  search: () => go('search'),
  picker: () => go('picker'),
  edit: v => { draft = null; go('edit', { id: v }); },
  back,
  menu(kind) {
    // Vor der Profilwahl gelten Sprache und Stil fürs Gerät, danach fürs Profil (Sprache = Oberfläche + Beschreibungen).
    openSelect({ title: menuLabel(kind), options: menuOptions(kind), cur: menuValue(kind), pick(val) {
      const target = noProfile() ? null : me();
      if (kind === 'lang') target ? target.lang = val : S.uiLang = val;
      if (kind === 'theme') target ? target.theme = val : S.theme = val;
      if (kind === 'size' && target) target.size = val;
      save(); redraw(kind + 'btn');
    } });
  },
  selPick(i) { const s = sel; closeSelect(); s.pick(s.options[+i].v); },
  selClose: () => closeSelect(),
  choose(v) {
    S.active = v; save(); reset('home');
    toast(t('Hallo %@!', me().name));
  },
  // Sprache (Oberfläche + Beschreibungen) und Streaming-Land: Auswahlliste statt Durchschalten.
  lang() {
    openSelect({ title: t('Sprache'), cur: draft.lang, pick(v) { draft.lang = v; redraw('lang'); },
      options: LANGS.map(l => ({ v: l, html: l === ui() ? esc(langName(l, l))
        : `${esc(langName(l, ui()))} – <span lang="${l}">${esc(langName(l, l))}</span>` })) });
  },
  country() {
    openSelect({ title: t('Streaming-Land'), cur: draft.country, pick(v) {
      draft.country = v;
      for (const s in draft.serviceCountries) if (draft.serviceCountries[s] === v) delete draft.serviceCountries[s];   // jetzt „wie Streaming-Land“
      redraw('country');
    },
      options: COUNTRIES.map(c => ({ v: c, html: `${flag(c)} ${esc(t(COUNTRY[c]))}` })) });
  },
  // Ein Streaming-Land reicht den meisten; Länder je Dienst nur mit eingeschaltetem Schalter. Aus = alle wieder gleich.
  multi() {
    draft.multiRegion = !draft.multiRegion;
    if (!draft.multiRegion) draft.serviceCountries = {};
    redraw('multi');
  },
  // Land des Kontos je Dienst (nur bei eingeschaltetem Schalter; das eine Streaming-Land ist dann ausgeblendet).
  // Ohne eigene Wahl gilt das bisherige Streaming-Land – so steht jeder Dienst gleich auf einem sinnvollen Land.
  svcCountry(id) {
    openSelect({ title: `${t('Land des Kontos')} – ${SERVICES.find(s => s.id === id).name}`, cur: regionOf(draft, id), pick(v) {
      draft.serviceCountries ||= {};
      if (v !== draft.country) draft.serviceCountries[id] = v; else delete draft.serviceCountries[id];
      redraw('sc-' + id);
    }, options: COUNTRIES.map(c => ({ v: c, html: `${flag(c)} ${esc(t(COUNTRY[c]))}` })) });
  },
  svc(v) {
    const on = draft.services.includes(v);
    draft.services = on ? draft.services.filter(x => x !== v) : [...draft.services, v];
    redraw('svc-' + v);
  },
  save() {
    if (!draft.name.trim()) { toast(t('Bitte einen Namen eingeben')); document.getElementById('name').focus(); return; }
    const p = { ...draft, name: draft.name.trim(), id: draft.id === 'new' ? String(Date.now()) : draft.id };
    delete p.multiRegion;   // nur Anzeige – ergibt sich aus serviceCountries
    S.profiles = draft.id === 'new' ? [...S.profiles, p] : S.profiles.map(x => x.id === p.id ? p : x);
    const isNew = draft.id === 'new';
    S.active = p.id; draft = null; save(); reset('home');
    if (isNew) go('eyetest', { setup: true });   // neues Profil: Sehtest → Farbtest → Start
  },
  del() {
    if (!confirm(t('Profil löschen?'))) return;
    S.profiles = S.profiles.filter(x => x.id !== draft.id);
    S.active = S.profiles[0]?.id; draft = null; save(); reset('home');
  },
});

// MARK: - Eingabe: Pfeiltasten (auch Fire-TV-Fernbedienung), Controller, Maus

// Räumliche Navigation: nächstes fokussierbares Element in Pfeilrichtung (Hauptrichtung + doppelt Querabstand;
// überlappen sich die Elemente quer, zählt der Querabstand 0 und sie gehen vor – bei Gleichstand das erste im Dokument).
function move(dir) {
  const scope = document.getElementById(osk ? 'osk' : sel ? 'sheet' : 'app');   // offene Tastatur/Auswahlliste fängt die Navigation
  const all = [...scope.querySelectorAll('[data-f]')].filter(e => e.offsetParent);
  const cur = document.activeElement;
  if (!all.includes(cur)) { all[0]?.focus(); return; }
  const a = cur.getBoundingClientRect(), ax = a.left + a.width / 2, ay = a.top + a.height / 2;
  let best = null, score = Infinity;
  for (const el of all) {
    if (el === cur) continue;
    const b = el.getBoundingClientRect(), dx = b.left + b.width / 2 - ax, dy = b.top + b.height / 2 - ay;
    const gap = (lo1, hi1, lo2, hi2) => Math.max(0, lo2 - hi1, lo1 - hi2);
    const main = { left: -dx, right: dx, up: -dy, down: dy }[dir];
    const side = dir === 'left' || dir === 'right' ? gap(a.top, a.bottom, b.top, b.bottom) : gap(a.left, a.right, b.left, b.right);
    // Seitwärts nie weit nach oben/unten springen; hoch/runter darf zur Not weit quer (z. B. zur Toolbar).
    if (main <= 4 || (side > main && (dir === 'left' || dir === 'right'))) continue;
    // Gleiche Zeile/Spalte zuerst, dann schräg im 45°-Kegel, erst zuletzt weit quer.
    const s = main + side * 2 + (side > 0 ? 1e5 : 0) + (side > main ? 1e6 : 0);
    if (s < score) { score = s; best = el; }
  }
  if (best) focusEl(best);
}

function act(k) {
  if (oskAct(k)) return;   // offene Bildschirmtastatur (osk.js) hat Vorrang
  if (views[current.view].key?.(k)) return;   // Ansicht mit eigener Tastenbelegung (Farbsehtest)
  const el = document.activeElement, typing = el?.tagName === 'INPUT';
  if (k === 'a') { typing ? oskOpen(el) : el?.click(); }   // A auf Eingabefeld = Bildschirmtastatur
  else if (k === 'b') back();
  else if (k === 'x') current.view === 'picker' ? actions.edit(el?.dataset.v) : current.view !== 'search' && go('search');
  else if (k === 'y') current.view === 'home' && actions.edit(me().id);
  else move(k);
}

addEventListener('keydown', e => {
  setInput('keyboard');
  // Fernbedienung: OK auf einem Eingabefeld öffnet die Bildschirmtastatur
  if (inputMode === 'remote' && e.key === 'Enter' && e.target.tagName === 'INPUT' && !osk) { e.preventDefault(); oskOpen(e.target); return; }
  if (e.key === '/' && e.target.tagName !== 'INPUT' && current.view !== 'search') { e.preventDefault(); go('search'); return; }
  const typing = e.target.tagName === 'INPUT';
  const dir = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right' }[e.key];
  const k = dir || { Enter: 'a', Escape: 'b', l: 'x', n: 'y' }[e.key];   // L/N = 👍/👎 wie am Mac
  if (k && views[current.view].key?.(k)) { e.preventDefault(); return; }
  if (dir && !(typing && (dir === 'left' || dir === 'right'))) { e.preventDefault(); move(dir); }
  else if (e.key === 'Escape' || (e.key === 'Backspace' && !typing) || e.key === 'GoBack' || e.key === 'BrowserBack') { e.preventDefault(); back(); }
});

// Xbox-Controller: Steuerkreuz/linker Stick mit Wiederholung, A/B/X/Y einmal pro Druck.
const pad = { prev: [], rep: {} };
function poll(now) {
  const g = [...(navigator.getGamepads?.() || [])].find(Boolean);
  if (g && !document.hidden) {
    const b = g.buttons.map(x => x.pressed), [lx = 0, ly = 0] = g.axes;
    const dirs = { up: b[12] || ly < -0.5, down: b[13] || ly > 0.5, left: b[14] || lx < -0.5, right: b[15] || lx > 0.5 };
    for (const d in dirs) {
      if (!dirs[d]) { delete pad.rep[d]; continue; }
      if (!pad.rep[d]) { pad.rep[d] = now + 380; act(d); } else if (now > pad.rep[d]) { pad.rep[d] = now + 110; act(d); }
    }
    if (b.some((p, i) => p && !pad.prev[i]) || Object.values(dirs).some(Boolean)) setInput('pad');
    ['a', 'b', 'x', 'y', 'lb', 'rb'].forEach((k, i) => { if (b[i] && !pad.prev[i]) act(k); });
    pad.prev = b;
  }
  requestAnimationFrame(poll);
}
requestAnimationFrame(poll);

// MARK: - Start

const start = !S.profiles.length ? 'edit' : S.profiles.length > 1 ? 'picker' : 'home';
if (!S.active) S.active = S.profiles[0]?.id;
reset(start);

// Seitentitel für die Navigationsleiste.
views.home.title = () => 'PopSofa';
views.picker.title = () => t('Wer schaut?');
views.search.title = () => t('Suchen');
views.detail.title = d => titles[d.key]?.name || '';
views.edit.title = d => d.id ? t('Einstellungen') : t('Neues Profil');
