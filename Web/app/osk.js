// Bildschirmtastatur für Controller und Fernbedienung (wie KeyboardController.swift in der Mac-App).
// A auf einem Eingabefeld öffnet sie; Steuerkreuz wählt die Taste, A tippt, X = ⌫, Y = Leertaste, LB = ⇧, RB = ↵, B = schließen.
// ponytail: tippt nur am Ende des Textes (kein Cursor in der Mitte) – reicht für Suche, Namen und Schlüssel.
'use strict';

let osk = null;   // { input, shift }

const OSK_ROWS = {
  de: ['1234567890', 'qwertzuiopü', 'asdfghjklöä', 'yxcvbnm,.-'],
  pt: ['1234567890', 'qwertyuiop', 'asdfghjklç', 'zxcvbnm,.-'],
  en: ['1234567890', 'qwertyuiop', 'asdfghjkl\'', 'zxcvbnm,.-'],
};

function oskRender() {
  // data-k immer klein geschrieben, damit der Fokus beim Umschalten (⇧) auf derselben Taste bleibt
  const k = (v, label, cls = '') => `<button class="key ${cls}" data-f data-k="key-${esc(v.toLocaleLowerCase())}" data-a="oskKey" data-v="${esc(v)}">${label}</button>`;
  const rows = OSK_ROWS[ui()].map(r => `<div class="keyrow">${[...r].map(c => {
    const ch = osk.shift ? c.toLocaleUpperCase() : c;
    return k(ch, esc(ch));
  }).join('')}</div>`).join('');
  const special = `<div class="keyrow">${k('⇧', icon('arrow-big-up'), 'wide' + (osk.shift ? ' on' : ''))}${k('@', '@')}
    ${k(' ', esc(t('Leertaste')), 'space')}${k('.com', '.com', 'wide')}${k('⌫', icon('delete'), 'wide')}${k('↵', icon('corner-down-left'), 'wide primary')}
    ${k('✕', icon('x'), 'wide')}</div>`;
  const box = document.getElementById('osk');
  box.innerHTML = `<div class="oskbox" role="dialog" aria-label="${esc(t('Tastatur'))}">
    <div class="osktext" aria-live="polite">${esc(osk.input.value) || `<span class="dim">${esc(osk.input.placeholder)}</span>`}<i class="caret"></i></div>
    ${rows}${special}</div>`;
  box.hidden = false;
  if (typeof applyLook === 'function') applyLook();
}

function oskOpen(input) {
  osk = { input, shift: false };
  oskRender();
  focusEl(document.querySelector('#osk [data-k="key-q"]') || document.querySelector('#osk [data-f]'));
  document.getElementById('hints').innerHTML = hints(current.view);
}
function oskClose() {
  const input = osk?.input;
  osk = null;
  Object.assign(document.getElementById('osk'), { hidden: true, innerHTML: '' });
  input?.focus();
  document.getElementById('hints').innerHTML = hints(current.view);
}
/// Taste anwenden; das input-Ereignis hält Entwurf, Suche und Schlüssel wie beim normalen Tippen aktuell.
function oskType(v) {
  const el = osk.input, focusKey = document.activeElement?.dataset.k;
  if (v === '✕') return oskClose();
  if (v === '↵') { const form = el.form; oskClose(); form ? form.requestSubmit() : move('down'); return; }
  if (v === '⇧') osk.shift = !osk.shift;
  else {
    el.value = v === '⌫' ? el.value.slice(0, -1) : el.value + v;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    if (osk.shift && v.length === 1 && v !== ' ') osk.shift = false;   // ⇧ gilt für einen Buchstaben
  }
  oskRender();
  focusEl(document.querySelector(`#osk [data-k="${CSS.escape(focusKey || '')}"]`) || document.querySelector('#osk [data-f]'));
}
actions.oskKey = v => oskType(v);

/// Controller-Tasten bei offener Tastatur; true = erledigt.
function oskAct(k) {
  if (!osk) return false;
  const map = { a: () => document.activeElement?.click(), b: oskClose, x: () => oskType('⌫'), y: () => oskType(' '),
    lb: () => oskType('⇧'), rb: () => oskType('↵') };
  map[k] ? map[k]() : move(k);
  return true;
}
