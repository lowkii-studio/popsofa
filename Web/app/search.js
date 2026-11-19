// Suche nach Kontext statt nur nach Titeln – wie SearchPlan in der Mac-App (Search.swift), plus Herkunftsland.
// „Filme aus Brasilien“, „Actionfilme aus Deutschland“, „Filme in portugiesischer Sprache“, „gemütlicher Film zum Kuscheln“,
// „Krimi auf Netflix“, „Serie unter 2 Stunden“. Nichts erkannt → Titelsuche wie bisher.
// ponytail: Stichwort-Liste (de/en/pt), keine KI; versteht nur diese Wörter – Liste bei Bedarf ergänzen.
'use strict';

// Stimmung/Genre → Stichwörter (Teilwort genügt: „actionfilme“ enthält „action“).
const MOOD_WORDS = [
  ['Komödie', ['lustig', 'witzig', 'komödie', 'lachen', 'humor', 'leicht', 'funny', 'comedy', 'engraçad', 'comédia',
    'gemütlich', 'cozy', 'cosy', 'feel-good', 'feelgood', 'aconchegante']],
  ['Thriller', ['spannend', 'thriller', 'nervenkitzel', 'packend', 'gripping', 'suspense', 'emocionante']],
  ['Horror', ['grusel', 'horror', 'angst', 'unheimlich', 'creepy', 'scary', 'assustador', 'terror']],
  ['Krimi', ['krimi', 'mord', 'detektiv', 'verbrechen', 'crime', 'detective', 'murder', 'policial']],
  ['Doku', ['doku', 'dokumentation', 'natur', 'wahre geschichte', 'documentar', 'true story']],
  ['Familie', ['familie', 'kinder', 'family', 'família', 'kids', 'crianças']],
  ['Animation', ['animation', 'anime', 'zeichentrick', 'cartoon', 'animação']],
  ['Romantik', ['romantisch', 'liebe', 'romanze', 'date', 'romantic', 'romance', 'romântic', 'amor', 'kuschel', 'cuddl', 'abraçar']],
  ['Science-Fiction', ['sci-fi', 'science', 'weltraum', 'zukunft', 'aliens', 'space', 'ficção científica', 'espaço']],
  ['Fantasy', ['fantasy', 'magie', 'drachen', 'magic', 'dragon', 'fantasia', 'magia']],
  ['Action', ['action', 'explosion', 'de ação']],   // nicht „ação“ allein – steckt in „animação“
  ['Abenteuer', ['abenteuer', 'adventure', 'aventura']],
  ['Drama', ['drama', 'traurig', 'emotional', 'berührend', 'sad', 'triste']],
  ['Krieg & Politik', ['krieg', 'politik', 'politic', 'guerra', 'política']],
  ['Mystery', ['mystery', 'rätsel', 'mysteriös', 'mistério']],
  ['Western', ['western', 'faroeste']],
];

const mediaCue = t => ['serie', 'series', 'série', 'staffel', 'show', 'bingen', 'durchschauen'].some(w => t.includes(w)) ? 'tv'
  : ['film', 'movie'].some(w => t.includes(w)) ? 'movie' : 'any';
const FILLER = new Set(['film', 'filme', 'filmen', 'serie', 'serien', 'movie', 'movies', 'series', 'série', 'séries', 'show', 'shows',
  'ein', 'eine', 'einen', 'a', 'an', 'um', 'uma', 'alle', 'all', 'etwas', 'something', 'algo', 'zum', 'für', 'for', 'para', 'mit', 'with', 'com']);
const isOnlyType = text => { const w = text.toLowerCase().split(/\s+/).filter(Boolean); return !!w.length && w.every(x => FILLER.has(x)); };

// Sprachwörter (de/en/pt) → Originalsprache + ggf. Land; deutsche Adjektive in allen Endungen.
const adj = (...stems) => stems.flatMap(s => ['', 'e', 'en', 'er', 'es'].map(e => s + e));
const LANGUAGE_WORDS = [
  [[...adj('brasilianisch'), 'brazilian', 'brasileiro', 'brasileira', 'brasileiros', 'brasileiras'], 'pt', 'BR'],
  [[...adj('portugiesisch'), 'portuguese', 'português', 'portugues', 'portuguesa'], 'pt', null],
  [[...adj('spanisch'), 'spanish', 'español', 'espanhol'], 'es', null],
  [[...adj('französisch'), 'french', 'francês', 'français'], 'fr', null],
  [[...adj('italienisch'), 'italian', 'italiano'], 'it', null],
  [[...adj('englisch'), 'english', 'inglês'], 'en', null],
  [[...adj('japanisch'), 'japanese', 'japonês'], 'ja', null],
  [[...adj('koreanisch'), 'korean', 'coreano', 'k-drama', 'kdrama'], 'ko', null],
  [[...adj('türkisch'), 'turkish', 'turco'], 'tr', null],
  [[...adj('schwedisch'), 'swedish'], 'sv', null],
  [[...adj('dänisch'), 'danish'], 'da', null],
  [[...adj('norwegisch'), 'norwegian'], 'no', null],
  [[...adj('polnisch'), 'polish'], 'pl', null],
  [[...adj('niederländisch', 'holländisch'), 'dutch'], 'nl', null],
  [[...adj('indisch'), 'hindi', 'bollywood'], 'hi', null],
  [[...adj('deutsch'), 'german', 'alemão'], 'de', null],
];
const LANGUAGE_GLUE = new Set(['auf', 'in', 'im', 'mit', 'em', 'no', 'na', 'originalsprache', 'originalton', 'o-ton', 'omu', 'ton',
  'sprache', 'original', 'language', 'língua', 'idioma', 'audio', 'áudio']);
const clean = w => w.toLowerCase().replace(/^[^\p{L}\d-]+|[^\p{L}\d-]+$/gu, '');

/// Entfernt ein Wort samt Füllwörtern davor/danach; gibt den Rest zurück.
function cut(words, i, n, glue) {
  let b = i - 1, f = i + n;
  while (b >= 0 && glue.has(clean(words[b]))) b--;
  while (f < words.length && glue.has(clean(words[f]))) f++;
  return [...words.slice(0, b + 1), ...words.slice(f)].join(' ');
}

function extractLanguage(text) {
  const words = text.split(/\s+/).filter(Boolean);
  for (let i = 0; i < words.length; i++) {
    const hit = LANGUAGE_WORDS.find(([w]) => w.includes(clean(words[i])));
    if (hit) return { lang: hit[1], country: hit[2], rest: cut(words, i, 1, LANGUAGE_GLUE) };
  }
  return { lang: null, country: null, rest: text };
}

// Herkunftsland nur mit „aus / from / de / do / da …“ davor – „Deutschland 83“ bleibt ein Titel.
const ORIGINS = ['DE', 'AT', 'CH', 'FR', 'IT', 'ES', 'PT', 'BR', 'GB', 'US', 'IE', 'NL', 'BE', 'DK', 'SE', 'NO', 'FI', 'IS', 'PL', 'CZ',
  'HU', 'GR', 'TR', 'JP', 'KR', 'CN', 'HK', 'TW', 'TH', 'IN', 'AU', 'NZ', 'CA', 'MX', 'AR', 'CO', 'CL', 'NG', 'ZA', 'EG', 'IL', 'IR'];
const ORIGIN_NAMES = (() => {   // Ländernamen in de/en/pt aus dem Browser (Intl), längste zuerst
  const out = [];
  for (const l of ['de', 'en', 'pt']) {
    const dn = new Intl.DisplayNames([l], { type: 'region' });
    for (const c of ORIGINS) out.push([dn.of(c).toLowerCase(), c]);
  }
  out.push(['usa', 'US'], ['amerika', 'US'], ['america', 'US'], ['england', 'GB'], ['uk', 'GB'], ['korea', 'KR'], ['holland', 'NL']);
  return out.sort((a, b) => b[0].length - a[0].length);
})();
const ORIGIN_GLUE = new Set(['aus', 'from', 'de', 'do', 'da', 'dos', 'das', 'der', 'dem', 'den', 'the']);
function extractOrigin(text) {
  const low = text.toLowerCase();
  for (const [name, code] of ORIGIN_NAMES) {
    const m = new RegExp(`(^|\\s)(aus|from|de|do|da|dos|das)\\s+(der\\s+|dem\\s+|den\\s+|the\\s+|os\\s+|o\\s+)?${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?=$|[\\s,.!?])`).exec(low);
    if (m) return { country: code, rest: (text.slice(0, m.index) + ' ' + text.slice(m.index + m[0].length)).replace(/\s+/g, ' ').trim() };
  }
  return { country: null, rest: text };
}

// Dienstnamen („Krimi auf Netflix“) → nur dort suchen.
const SERVICE_WORDS = { netflix: ['netflix'], prime: ['prime video', 'amazon prime', 'prime', 'amazon'],
  disney: ['disney+', 'disney plus', 'disney'], appletv: ['apple tv+', 'apple tv', 'appletv'], wow: ['wow', 'sky'],
  rtlplus: ['rtl+', 'rtl plus', 'rtlplus'], joyn: ['joyn'], ard: ['ard'], zdf: ['zdf'],
  paramount: ['paramount+', 'paramount plus', 'paramount'], hbomax: ['hbo max', 'hbo'], crunchyroll: ['crunchyroll'],
  dazn: ['dazn'], youtube: ['youtube'] };
const SERVICE_GLUE = new Set(['auf', 'bei', 'von', 'im', 'in', 'oder', 'und', 'on', 'from', 'at', 'or', 'and', 'no', 'na', 'em', 'ou', 'e', ',']);
function extractServices(text) {
  let words = text.replace(/,/g, ' , ').split(/\s+/).filter(Boolean);
  const found = new Set();
  for (let i = 0; i < words.length; i++) {
    let hit = null;
    for (const [sid, aliases] of Object.entries(SERVICE_WORDS))
      for (const a of aliases) {
        const parts = a.split(' ');
        if (words.slice(i, i + parts.length).map(w => w.toLowerCase().replace(/[^\p{L}\d+]/gu, '')).join(' ') === a && parts.length > (hit?.[1] || 0)) hit = [sid, parts.length];
      }
    if (hit) { found.add(hit[0]); words = cut(words, i, hit[1], SERVICE_GLUE).split(' ').filter(Boolean); i = -1; }
  }
  return { services: [...found], rest: words.join(' ').replace(/\s+,\s*/g, ' ').trim() };
}

/// Stimmung, Art, Länge und „neu“ erkennen; nichts erkannt → Titelsuche.
function heuristic(text) {
  const t0 = text.toLowerCase(), p = { mediaType: mediaCue(t0), genres: [], maxRuntime: 0, minYear: 0, titleQuery: '' };
  p.genres = MOOD_WORDS.filter(([, w]) => w.some(x => t0.includes(x))).map(([n]) => GENRES.find(g => g.name === n));
  const m = /(unter|under|menos de|bis)\s+(\d+)\s*(min|minuten|std|stunden|hour|hora|h\b)/.exec(t0);
  if (m) p.maxRuntime = /st|h/.test(m[3]) ? +m[2] * 60 : +m[2];
  else if (/\b(kurz|short|curto)/.test(t0)) p.maxRuntime = 95;
  if (/\b(neu|aktuell|new|novo|nova|recente)/.test(t0)) p.minYear = new Date().getFullYear() - 2;
  if (!p.genres.length && p.mediaType === 'any' && !p.maxRuntime && !p.minYear) p.titleQuery = text;
  return p;
}

/// Ganze Eingabe → Suchplan.
function searchPlan(text) {
  const s = extractServices(text), o = extractOrigin(s.rest), l = extractLanguage(o.rest), rest = l.rest.trim();
  const plan = !rest ? { mediaType: 'any', genres: [], maxRuntime: 0, minYear: 0, titleQuery: '' }
    : isOnlyType(rest) ? { mediaType: mediaCue(rest.toLowerCase()), genres: [], maxRuntime: 0, minYear: 0, titleQuery: '' }
    : heuristic(rest);
  return { ...plan, services: s.services, language: l.lang, country: o.country || l.country };
}

/// Zusammenfassung über den Ergebnissen, z. B. „Action · Filme · aus Deutschland“.
function describe(p) {
  const regionName = c => new Intl.DisplayNames([ui()], { type: 'region' }).of(c);
  const bits = p.genres.map(g => t(g.name));
  bits.push(t(p.mediaType === 'tv' ? 'Serien' : p.mediaType === 'movie' ? 'Filme' : 'Filme & Serien'));
  if (p.maxRuntime) bits.push(t('bis %@ Min.', p.maxRuntime));
  if (p.minYear) bits.push(t('ab %@', p.minYear));
  if (p.language) bits.push(t('Originalsprache %@', langName(p.language, ui())));
  if (p.country) bits.push(t('aus %@', regionName(p.country)));
  if (p.services.length) bits.push(t(' · bei %@', p.services.map(s => SERVICES.find(x => x.id === s)?.name || s).join(t(' oder '))).replace(/^ · /, ''));
  return bits.join(' · ');
}

/// TMDB-Abfrage mit Filtern – je Land des Kontos eine (wie die Startseite), zwei Seiten je Art.
async function discoverPlan(p) {
  const prof = me(), only = p.services.length ? p.services : prof.services;
  const regions = [...new Set(only.map(s => regionOf(prof, s)))];
  let bases = regions.map(r => {
    const ids = only.filter(s => regionOf(prof, s) === r).flatMap(s => PROVIDERS[s] || []).join('|');
    return { watch_region: r, with_watch_providers: ids, with_watch_monetization_types: 'flatrate|free|ads' };
  }).filter(b => b.with_watch_providers);
  if (!bases.length) bases = [{ watch_region: prof.country }];
  // 1–2 Genres: alle verlangen („lustiger Krimi“), mehr: eins davon. Sprach-/Länder-Suchen auch mit wenigen Stimmen.
  const join = ids => ids.join(ids.length <= 2 ? ',' : '|');
  const common = { 'vote_count.gte': p.language || p.country ? 3 : 30, with_original_language: p.language || '',
    with_origin_country: p.country || '', 'with_runtime.lte': p.maxRuntime || '' };
  const run = async (type, extra) => {
    const lists = await Promise.all(bases.flatMap(b => [1, 2].map(page =>
      tmdb(`/discover/${type}`, { ...b, ...common, ...extra, page }).then(r => r.results.map(x => item(x, type))).catch(() => []))));
    return lists.reduce(mix, []);
  };
  const [movies, shows] = await Promise.all([
    p.mediaType !== 'tv' ? run('movie', { with_genres: join(p.genres.map(g => g.movie).filter(Boolean)),
      'primary_release_date.gte': p.minYear ? `${p.minYear}-01-01` : '' }) : [],
    p.mediaType !== 'movie' ? run('tv', { with_genres: join([...new Set(p.genres.map(g => g.tv).filter(Boolean))]),
      'first_air_date.gte': p.minYear ? `${p.minYear}-01-01` : '' }) : [],
  ]);
  return diversify(taste(), mix(movies, shows));   // nach Geschmack sortiert, Doppelte und 👎 raus
}

// Suche ersetzen: erst Kontext erkennen, sonst Titelsuche (in jeder Sprache).
runSearch = async function (q) {
  const status = document.getElementById('status'), box = document.getElementById('results');
  if (!S.key) {
    status.textContent = t('Neue Filme & Serien nach deinem Geschmack – mit kostenlosem TMDB-Schlüssel.');
    box.innerHTML = `<button class="btn primary" data-f data-k="key" data-a="edit" data-v="${me().id}">${esc(t('TMDB-Schlüssel'))}</button>`;
    return;
  }
  status.textContent = t('Suche …');
  const p = searchPlan(q);
  try {
    let list;
    if (p.titleQuery) {
      const r = await tmdb('/search/multi', { query: p.titleQuery });
      list = r.results.filter(x => x.media_type === 'movie' || x.media_type === 'tv').map(x => item(x))
        .filter(x => !p.language || x.lang === p.language);
      status.textContent = list.length ? t('Titel „%@“', p.titleQuery) : t('Nichts gefunden – anders formulieren?');
    } else {
      list = await discoverPlan(p);
      status.textContent = list.length ? describe(p) : t('Nichts gefunden – anders formulieren?');
    }
    if (current.view !== 'search') return;
    box.innerHTML = list.map((x, i) => { titles[x.type + ':' + x.id] = x; return poster(x, 'res' + i); }).join('');
    restorePending();   // zurück aus den Details: gleiche Stelle in den Ergebnissen
    if (!p.titleQuery) verifyPosters(box);   // Titelsuche zeigt bewusst alles, Kontextsuche nur Verfügbares
  } catch (e) { status.textContent = t('Suche fehlgeschlagen – Internet/TMDB-Schlüssel prüfen'); }
};

{ // Selbsttest (läuft beim Laden): Beispiele aus der Anfrage und Titel, die Titel bleiben müssen.
  const c = (q, f) => console.assert(f(searchPlan(q)), 'Suche: ' + q, searchPlan(q));
  c('Filme aus Brasilien', p => p.country === 'BR' && !p.language && p.mediaType === 'movie' && !p.titleQuery);
  c('Actionfilme aus Deutschland', p => p.country === 'DE' && p.genres[0]?.name === 'Action' && p.mediaType === 'movie');
  c('Filme in portugiesischer Sprache', p => p.language === 'pt' && p.mediaType === 'movie' && !p.titleQuery);
  c('gemütlicher Film zum Kuscheln', p => p.genres.map(g => g.name).sort().join() === 'Komödie,Romantik' && p.mediaType === 'movie');
  c('brasilianische Serie', p => p.language === 'pt' && p.country === 'BR' && p.mediaType === 'tv');
  c('Krimi auf Netflix', p => p.services.join() === 'netflix' && p.genres[0]?.name === 'Krimi');
  c('movies from Brazil', p => p.country === 'BR');
  c('filmes do Brasil', p => p.country === 'BR');
  c('Spannende Serie unter 2 Stunden', p => p.maxRuntime === 120 && p.mediaType === 'tv');
  c('Deutschland 83', p => p.titleQuery === 'Deutschland 83');
  c('Breaking Bad', p => p.titleQuery === 'Breaking Bad');
}
