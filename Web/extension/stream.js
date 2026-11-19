// PopSofa Controller in Netflix & Co.
// Linker Stick = Zeiger, A = Klick, B = Esc/Vollbild aus, X = Pause, Y = Vollbild, LB/RB = ← →,
// Steuerkreuz = Pfeiltasten, LT/RT = Lautstärke, rechter Stick = Scrollen, ⧉ (Ansicht) = zurück zu PopSofa.
(() => {
  const cursor = document.createElement('div');
  cursor.style.cssText = 'position:fixed;left:0;top:0;width:28px;height:28px;margin:-14px 0 0 -14px;border-radius:50%;' +
    'border:4px solid #FFD23F;box-shadow:0 0 0 3px #000;pointer-events:none;z-index:2147483647;display:none';
  document.documentElement.appendChild(cursor);
  let x = innerWidth / 2, y = innerHeight / 2, lastMove = 0, prev = [], repeat = {};

  const video = () => [...document.querySelectorAll('video')].sort((a, b) => b.clientWidth - a.clientWidth)[0];
  const key = (k, code) => {
    const target = document.activeElement || document.body;
    for (const type of ['keydown', 'keyup'])
      target.dispatchEvent(new KeyboardEvent(type, { key: k, code: code || k, bubbles: true, cancelable: true }));
  };
  function click() {
    const el = document.elementFromPoint(x, y);
    if (!el) return;
    const o = { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window };
    for (const type of ['pointerover', 'pointerdown', 'mousedown', 'pointerup', 'mouseup'])
      el.dispatchEvent(new (type.startsWith('pointer') ? PointerEvent : MouseEvent)(type, o));
    el.focus?.();
    el.click();
  }

  function poll(now) {
    const g = [...(navigator.getGamepads?.() || [])].find(Boolean);
    if (g && !document.hidden) {
      const b = g.buttons.map(v => v.pressed), [lx = 0, ly = 0, rx = 0, ry = 0] = g.axes;
      const dead = v => Math.abs(v) < 0.15 ? 0 : v;
      // Zeiger: quadratisch beschleunigt – fein langsam, voll ausgelenkt schnell.
      const dx = dead(lx), dy = dead(ly);
      if (dx || dy) {
        x = Math.min(innerWidth - 1, Math.max(0, x + Math.sign(dx) * dx * dx * 22));
        y = Math.min(innerHeight - 1, Math.max(0, y + Math.sign(dy) * dy * dy * 22));
        cursor.style.transform = `translate(${x}px,${y}px)`; cursor.style.display = 'block'; lastMove = now;
      } else if (now - lastMove > 4000) cursor.style.display = 'none';
      if (dead(ry) || dead(rx)) {
        const el = document.elementFromPoint(x, y);
        const box = el && [...function* () { for (let e = el; e; e = e.parentElement) yield e; }()]
          .find(e => e.scrollHeight > e.clientHeight + 4 && /auto|scroll/.test(getComputedStyle(e).overflowY));
        (box || window).scrollBy(dead(rx) * 24, dead(ry) * 24);
      }
      const edge = i => b[i] && !prev[i];
      if (edge(0)) cursor.style.display === 'block' ? click() : key('Enter');
      if (edge(1)) { document.fullscreenElement ? document.exitFullscreen() : key('Escape'); }
      if (edge(2) || edge(9)) { const v = video(); if (v) v.paused ? v.play() : v.pause(); }
      if (edge(3)) document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen?.().catch(() => {});
      if (edge(4)) key('ArrowLeft'); if (edge(5)) key('ArrowRight');
      if (edge(8) || edge(16)) chrome.runtime.sendMessage('back');
      // Steuerkreuz als Pfeiltasten (mit Wiederholung beim Halten).
      [[12, 'ArrowUp'], [13, 'ArrowDown'], [14, 'ArrowLeft'], [15, 'ArrowRight']].forEach(([i, k]) => {
        if (!b[i]) { delete repeat[i]; return; }
        if (!repeat[i]) { repeat[i] = now + 400; key(k); } else if (now > repeat[i]) { repeat[i] = now + 120; key(k); }
      });
      // Lautstärke stufenlos, solange LT/RT gedrückt sind.
      const v = video(), lt = g.buttons[6]?.value || 0, rt = g.buttons[7]?.value || 0;
      if (v && (lt > 0.2 || rt > 0.2)) v.volume = Math.min(1, Math.max(0, v.volume + (rt - lt) * 0.01));
      prev = b;
    }
    requestAnimationFrame(poll);
  }
  requestAnimationFrame(poll);

  // Profil automatisch anklicken: gleicher Name wie das aktive PopSofa-Profil, nur in den ersten 20 s.
  chrome.runtime.sendMessage('profile', name => {
    name = (name || '').trim().toLowerCase();
    if (!name) return;
    const until = Date.now() + 20000;
    const timer = setInterval(() => {
      const hit = [...document.querySelectorAll('a, button, [role="button"], [role="link"], li')]
        .find(e => e.offsetParent && e.innerText?.trim().toLowerCase() === name);
      if (hit) hit.click();
      if (hit || Date.now() > until) clearInterval(timer);
    }, 700);
  });
})();
