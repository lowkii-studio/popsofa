// Watchlist, Genre-Wahl und Geschmack lernen (👍/👎) – wie in der Mac-App (Recommendations.swift, AppState.swift).
// Alles pro Profil im Browser: p.watchlist = [Titel], p.taste = { picked, weights, liked, disliked, lastLiked }.
'use strict';

// TMDB hat getrennte Genre-IDs für Filme und Serien.
const GENRES = [
  ['Action', 28, 10759], ['Abenteuer', 12, 10759], ['Animation', 16, 16], ['Komödie', 35, 35], ['Krimi', 80, 80],
  ['Doku', 99, 99], ['Drama', 18, 18], ['Familie', 10751, 10751], ['Fantasy', 14, 10765], ['Science-Fiction', 878, 10765],
  ['Horror', 27, null], ['Mystery', 9648, 9648], ['Thriller', 53, null], ['Romantik', 10749, null],
  ['Krieg & Politik', 10752, 10768], ['Western', 37, 37],
].map(([name, movie, tv]) => ({ name, ids: [movie, tv].filter(Boolean), movie, tv }));
const MOVIE_GENRES = GENRES.map(g => g.movie).filter(Boolean), TV_GENRES = GENRES.map(g => g.tv).filter(Boolean);

const taste = (p = me()) => (p.taste ||= { picked: [], weights: {}, liked: [], disliked: [], lastLiked: null });
const watchlist = (p = me()) => (p.watchlist ||= []);
const keyOf = x => x.type + ':' + x.id;

function weight(tt, g) { return (tt.picked.includes(g) ? 3 : 0) + (tt.weights[g] || 0); }
/// Bewertung mit Stimmen gewichtet: wenige Stimmen → Richtung TMDB-Durchschnitt (6,8).
function quality(x) {
  if (!x.rating) return 6.8;
  const m = x.type === 'tv' ? 200 : 500, v = x.votes ?? m;
  return (v * x.rating + m * 6.8) / (v + m);
}
// ponytail: Genre-Gewichtung + Bewertung; Lieblingsgenre gedeckelt, damit es nicht alles verdrängt.
function score(tt, x) {
  const affinity = Math.min(Math.max((x.genres || []).reduce((s, g) => s + weight(tt, g), 0), -4), 6);
  return 0.75 * affinity + (quality(x) - 5);
}
/// Abwechslungsreich sortieren (MMR): ähnelt ein Titel den letzten drei, rutscht er nach hinten.
function diversify(tt, list) {
  const seen = new Set();
  const pool = list.filter(x => !tt.disliked.includes(keyOf(x)) && !seen.has(keyOf(x)) && seen.add(keyOf(x)))
    .sort((a, b) => score(tt, b) - score(tt, a));
  const sim = (a, b) => {
    const x = new Set(a.genres || []), y = new Set(b.genres || []);
    const both = [...x].filter(g => y.has(g)).length, any = new Set([...x, ...y]).size;
    return any ? both / any : 0;
  };
  const out = [];
  while (pool.length) {
    const recent = out.slice(-3), mmr = x => score(tt, x) - 2 * Math.max(0, ...recent.map(r => sim(x, r)));
    let best = 0;
    pool.forEach((x, i) => { if (mmr(x) > mmr(pool[best])) best = i; });
    out.push(pool.splice(best, 1)[0]);
  }
  return out;
}
const topGenres = (tt, domain) => domain.map(g => [g, weight(tt, g)]).filter(([, w]) => w > 0)
  .sort((a, b) => b[1] - a[1]).slice(0, 3).map(([g]) => g);

// MARK: - Empfehlungsreihen

function forget() { for (const k in rowCache) delete rowCache[k]; }   // nach 👍/👎/Genres neu laden

async function loadRows() {
  const p = me(), tt = taste(p), k = [p.id, p.lang, p.country, p.services, JSON.stringify(p.serviceCountries || {}), JSON.stringify(tt)].join();
  if (!rowCache[k]) {
    // Je Land eine Abfrage: Dienste mit Konto in einem anderen Land (z. B. HBO Max aus Portugal) werden dort gesucht.
    const regions = [...new Set([p.country, ...p.services.map(s => regionOf(p, s))])];
    let bases = regions.map(r => {
      const ids = p.services.filter(s => regionOf(p, s) === r).flatMap(s => PROVIDERS[s] || []).join('|');
      return { watch_region: r, with_watch_providers: ids, with_watch_monetization_types: ids ? 'flatrate|free|ads' : '' };
    }).filter(b => b.with_watch_providers);
    if (!bases.length) bases = [{ watch_region: p.country }];   // keine Dienste gewählt: alles im Streaming-Land
    const base = bases[0];
    const today = new Date().toISOString().slice(0, 10), since = new Date(Date.now() - 90 * 864e5).toISOString().slice(0, 10);
    const both = async (q, qm = {}, qt = {}) => {
      const lists = await Promise.all(bases.map(async b => {
        const [m, tv] = await Promise.all([tmdb('/discover/movie', { ...b, ...q, ...qm }), tmdb('/discover/tv', { ...b, ...q, ...qt })]);
        return mix(m.results.map(r => item(r, 'movie')), tv.results.map(r => item(r, 'tv')));
      }));
      const seen = new Set();   // Länder reihum mischen, Doppelte raus
      return lists.reduce(mix, []).filter(x => !seen.has(keyOf(x)) && seen.add(keyOf(x)));
    };
    const mg = topGenres(tt, MOVIE_GENRES).join('|'), tg = topGenres(tt, TV_GENRES).join('|');
    const last = tt.lastLiked, unseen = x => !tt.liked.includes(keyOf(x)) && !tt.disliked.includes(keyOf(x));
    const [forYou, fresh, popular, because] = await Promise.all([
      mg || tg ? both({}, { with_genres: mg }, { with_genres: tg }) : [],
      both({}, { 'primary_release_date.gte': since, 'primary_release_date.lte': today }, { 'first_air_date.gte': since, 'first_air_date.lte': today }),
      both({}, { 'vote_count.gte': 200 }, { 'vote_count.gte': 100 }),
      // „Weil dir X gefallen hat“: gleiche Genres (UND), nur bei deinen Diensten.
      last ? tmdb(`/discover/${last.type}`, { ...base, with_genres: (last.genres || []).slice(0, 2).join(',') })
        .then(r => r.results.map(x => item(x, last.type))) : [],
    ]);
    rowCache[k] = [
      [t('Für dich'), diversify(tt, forYou).filter(unseen)],
      [t('Neu bei deinen Diensten'), diversify(tt, fresh)],
      [last ? t('Weil dir „%@“ gefallen hat', last.name) : '', diversify(tt, because).filter(x => unseen(x) && keyOf(x) !== keyOf(last))],
      [t('Beliebt bei deinen Diensten'), popular.filter(x => !tt.disliked.includes(keyOf(x)))],
    ].filter(([title, list]) => title && list.length);
  }
  // Watchlist immer als erste Reihe (unabhängig von den Diensten), ohne Cache.
  const wl = watchlist(p);
  return wl.length ? [[t('Meine Watchlist'), wl], ...rowCache[k]] : rowCache[k];
}

// MARK: - 👍 / 👎 / Watchlist

function like(x) {
  const tt = taste(), k = keyOf(x);
  if (!tt.liked.includes(k)) { tt.liked.push(k); (x.genres || []).forEach(g => tt.weights[g] = (tt.weights[g] || 0) + 1); }
  tt.disliked = tt.disliked.filter(d => d !== k);
  tt.lastLiked = x; save();
  toast(t('Gefällt dir – mehr wie „%@“', x.name));
}
function dislike(x) {
  const tt = taste(), k = keyOf(x);
  if (!tt.disliked.includes(k)) { tt.disliked.push(k); (x.genres || []).forEach(g => tt.weights[g] = (tt.weights[g] || 0) - 1); }
  tt.liked = tt.liked.filter(l => l !== k);
  if (tt.lastLiked && keyOf(tt.lastLiked) === k) tt.lastLiked = null;
  save();
  toast(t('Ausgeblendet – weniger davon'));
}
function toggleWatchlist(x) {
  const p = me(), k = keyOf(x), on = watchlist(p).some(w => keyOf(w) === k);
  p.watchlist = on ? p.watchlist.filter(w => keyOf(w) !== k) : [x, ...p.watchlist];
  save();
  toast(on ? t('Von der Watchlist entfernt') : t('„%@“ auf der Watchlist', x.name));
}
const onWatchlist = x => watchlist().some(w => keyOf(w) === keyOf(x));
const liked = x => taste().liked.includes(keyOf(x));

// Detailseite: Knöpfe für Maus, X/Y am Controller, L/N auf der Tastatur.
const tasteButtons = x => `<button class="btn ${onWatchlist(x) ? 'on' : ''}" data-f data-k="wl" data-a="wl">${onWatchlist(x) ? icon('bookmark-check') + esc(t('Auf der Watchlist')) : icon('bookmark-plus') + esc(t('Auf die Watchlist'))}</button>
  <button class="btn ${liked(x) ? 'on' : ''}" data-f data-k="like" data-a="like">${icon('thumbs-up')}${esc(t(liked(x) ? 'Gefällt dir' : 'Gefällt mir'))}</button>
  <button class="btn" data-f data-k="dislike" data-a="dislike">${icon('thumbs-down')}${esc(t('Nicht mein Fall'))}</button>`;
const detailTitle = () => titles[current.data.key];
function refreshTasteButtons(k) {
  document.getElementById('tastebtns').innerHTML = tasteButtons(detailTitle());
  refocus(k);
}

Object.assign(actions, {
  wl() { toggleWatchlist(detailTitle()); refreshTasteButtons('wl'); },
  like() { like(detailTitle()); forget(); refreshTasteButtons('like'); },
  dislike() { dislike(detailTitle()); forget(); back(); },   // wie am Mac: Titel verschwindet, zurück
});
views.detail.key = k => {
  if (k === 'x') { actions.like(); return true; }
  if (k === 'y') { actions.dislike(); return true; }
};
// Auf den Postern der Startseite: X = 👍, Y = 👎 (sonst X = Suchen, Y = Einstellungen).
views.home.key = k => {
  const el = document.activeElement, x = el?.dataset.a === 'detail' && titles[el.dataset.v];
  if (!x || (k !== 'x' && k !== 'y')) return false;
  k === 'x' ? like(x) : dislike(x);
  forget();
  if (k === 'y') { const next = el.nextElementSibling || el.previousElementSibling; el.remove(); next && focusEl(next); }
  return true;
};

// MARK: - Genre-Wahl („Was schaust du gern?“)

// TMDB fasst Serien-Genres zusammen (Action & Abenteuer = 10759, Fantasy & Sci-Fi = 10765): Ein Genre gilt nur über
// seine eigene Film-ID als gewählt (ohne Film-ID: Serien-ID). Abwählen entfernt die geteilte Serien-ID nur,
// wenn kein anderes gewähltes Genre sie noch braucht.
const ownId = g => g.movie ?? g.tv;
const isPicked = (list, g) => list.includes(ownId(g));
function togglePick(list, g) {
  if (!isPicked(list, g)) return [...new Set([...list, ...g.ids])];
  const rest = list.filter(id => id !== ownId(g));
  const stillUsed = id => GENRES.some(o => o !== g && isPicked(rest, o) && o.ids.includes(id));
  return rest.filter(id => !g.ids.includes(id) || stillUsed(id));
}
{ // Selbsttest (läuft beim Laden, kostet nichts): Action wählen lässt Abenteuer abgewählt.
  const action = GENRES[0], adventure = GENRES[1], both = togglePick(togglePick([], action), adventure);
  console.assert(!isPicked(togglePick([], action), adventure), 'Action wählt Abenteuer mit');
  console.assert(togglePick(both, action).includes(10759) && !isPicked(togglePick(both, action), action), 'geteilte Serien-ID bleibt');
  console.assert(togglePick(togglePick([], action), action).length === 0, 'Abwählen räumt auf');
}
const picked = g => isPicked(taste().picked, g);
views.genres = d => `${d.setup ? `<p class="dim">${esc(t('Schritt %@ von %@', 5, 5))}</p>` : ''}
  <h1>${esc(t('Was schaust du gern?'))}</h1>
  <p class="intro">${esc(t('Wähle ein paar Genres. Später lernt PopSofa durch 👍 und 👎 auf den Postern dazu.'))}</p>
  <div class="toggles" style="margin-top:1.5rem">${GENRES.map((g, i) => `<button class="btn ${picked(g) ? 'on' : ''}" data-f data-k="g${i}"
    data-a="genre" data-v="${i}" aria-pressed="${picked(g)}">${picked(g) ? icon('check') : ''}${esc(t(g.name))}</button>`).join('')}</div>
  <div class="row-btns"><button class="btn primary" data-f data-k="gdone" data-a="back">${esc(t('Fertig'))}</button></div>`;
actions.genre = v => {
  const g = GENRES[+v], tt = taste();
  tt.picked = togglePick(tt.picked, g);
  save(); forget(); redraw('g' + v);
};
views.genres.title = () => t('Genres');

// MARK: - Verfügbarkeit nachprüfen
// TMDBs /discover prüft „bei deinem Anbieter“ und „im Abo“ unabhängig voneinander: Ein Titel, der bei deinem Dienst nur
// zum Kauf steht und im Abo bei einem fremden Dienst läuft, kommt trotzdem. Deshalb je Titel nachsehen
// (/watch/providers) und Poster ohne Abo/Gratis/Werbung bei einem deiner Dienste – im Land des Kontos – ausblenden.
// ponytail: eine Anfrage pro Titel (4 gleichzeitig, pro Sitzung gemerkt); bei Bedarf auf sichtbare Poster begrenzen.
const offerCache = {};
function ownOffers(x, p = me()) {
  const k = keyOf(x);
  offerCache[k] ||= tmdb(`/${x.type}/${x.id}/watch/providers`).then(r => r.results || {}).catch(() => null);
  return offerCache[k].then(res => res && p.services.filter(s => {
    const g = res[regionOf(p, s)] || {};
    return [...(g.flatrate || []), ...(g.free || []), ...(g.ads || [])].some(o => (PROVIDERS[s] || []).includes(o.provider_id));
  }));
}
async function verifyPosters(box, skip = null) {
  const p = me();
  if (!p.services.some(s => PROVIDERS[s])) return;   // keine prüfbaren Dienste gewählt
  const queue = [...box.querySelectorAll('.poster[data-a="detail"]')].filter(el => !skip?.contains(el));
  const worker = async () => {
    for (let el; (el = queue.shift());) {
      const x = titles[el.dataset.v];
      const own = x && await ownOffers(x, p);
      if (!own || own.length || !el.isConnected) continue;   // Fehler beim Nachsehen: lieber stehen lassen
      if (document.activeElement === el) focusEl(el.nextElementSibling || el.previousElementSibling || el);
      el.remove();
      for (const k in rowCache) rowCache[k].forEach(r => { r[1] = r[1].filter(y => keyOf(y) !== keyOf(x)); });
    }
  };
  await Promise.all([worker(), worker(), worker(), worker()]);
  box.querySelectorAll('.shelf').forEach(s => shelfArrows(s));
}

// MARK: - Unsere Watchlist (alle Profile dieses Browsers zusammen)
// Jeder Titel einmal, mit den Profilen, die ihn gemerkt haben; von mehreren gemerkte („gemeinsam ausgewählt“) zuerst.
function household(profiles = S.profiles) {
  const map = new Map();
  for (const p of profiles) for (const x of watchlist(p)) {
    const k = keyOf(x);
    map.has(k) ? map.get(k).who.push(p) : map.set(k, { x, who: [p] });
  }
  return [...map.values()].sort((a, b) => b.who.length - a.who.length);   // stabil: sonst Reihenfolge der Profile
}
{ // Selbsttest: gemeinsamer Titel steht vorn, jeder Titel nur einmal.
  const a = { type: 'movie', id: 1 }, b = { type: 'movie', id: 2 };
  const h = household([{ id: 'x', watchlist: [b] }, { id: 'y', watchlist: [b, a].reverse() }]);
  console.assert(h.length === 2 && keyOf(h[0].x) === 'movie:2' && h[0].who.length === 2, 'Unsere Watchlist', h);
}
const whoDots = who => `<span class="who" aria-label="${esc(t('Gemerkt von %@', who.map(p => p.name).join(', ')))}">${
  who.map(p => `<i style="background:${p.color}" title="${esc(p.name)}">${esc(p.name[0]?.toUpperCase())}</i>`).join('')}</span>`;
views.ours = () => {
  const all = household(), shared = all.filter(e => e.who.length > 1), only = !!S.sharedOnly;
  const grid = (list, from) => `<div class="grid">${list.map(({ x, who }, i) => {
    titles[keyOf(x)] = x;
    return poster(x, 'o' + (from + i)).replace('<img', whoDots(who) + '<img');
  }).join('')}</div>`;
  const rest = all.slice(shared.length);
  return `<h1>${esc(t('Unsere Watchlist'))}</h1>
    <button class="switch" role="switch" aria-checked="${only}" data-f data-k="shared" data-a="sharedOnly">
      <span class="track" aria-hidden="true"><span class="knob"></span></span>${esc(t('Nur gemeinsame'))}</button>
    ${!all.length ? `<p class="dim intro">${esc(t('Noch nichts gemerkt – auf der Detailseite „Auf die Watchlist“.'))}</p>` : ''}
    ${shared.length ? `<h2>${esc(t('Gemeinsam ausgewählt'))}</h2>${grid(shared, 0)}`
      : all.length && only ? `<p class="dim intro">${esc(t('Noch kein Titel, den mehrere gemerkt haben.'))}</p>` : ''}
    ${rest.length && !only ? `<h2>${esc(t('Einzeln gemerkt'))}</h2>${grid(rest, shared.length)}` : ''}`;
};
views.ours.title = () => t('Unsere Watchlist');
actions.ours = () => go('ours');
actions.sharedOnly = () => { S.sharedOnly = !S.sharedOnly; save(); redraw('shared'); };
