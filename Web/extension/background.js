// Findet den PopSofa-Tab über seinen Titel („PopSofa · Name · 150 %“) – so braucht die Erweiterung
// keinen Zugriff auf die Seite, auf der PopSofa liegt (Fire TV, GitHub Pages, localhost …).
async function popsofaTab() {
  const tabs = await chrome.tabs.query({});
  return tabs.find(t => /^PopSofa\b/.test(t.title || ''));
}

chrome.runtime.onMessage.addListener((msg, sender, reply) => {
  (async () => {
    const tab = await popsofaTab(), [, name = '', zoom = ''] = (tab?.title || '').split(' · ');
    if (msg === 'back' && tab) {
      await chrome.tabs.update(tab.id, { active: true });
      await chrome.windows.update(tab.windowId, { focused: true });
    }
    // Beim Laden von Netflix & Co.: gleiche Zoomstufe wie die Textgröße in PopSofa (Groß = 150 %) –
    // nur für diesen Tab, damit die Seite außerhalb von PopSofa normal groß bleibt.
    if (msg === 'profile' && sender.tab) {
      const z = parseInt(zoom, 10) / 100 || 1;
      await chrome.tabs.setZoomSettings(sender.tab.id, { mode: 'automatic', scope: 'per-tab' }).catch(() => {});
      await chrome.tabs.setZoom(sender.tab.id, z).catch(() => {});
    }
    reply(name);   // Profilname fürs automatische Anklicken
  })();
  return true;   // Antwort kommt asynchron
});
