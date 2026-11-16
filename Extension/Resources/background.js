const api = typeof browser !== "undefined" ? browser : chrome;

// Pages are darkened only when Nox itself turned dark mode on (and "Dark websites" is on).
// If Nox can't be asked, do nothing: Safari then behaves exactly like stock macOS.
async function forceDarkEnabled() {
  try {
    const reply = await api.runtime.sendNativeMessage("application.id", { type: "get" });
    return !!(reply && reply.enabled === true);
  } catch (e) {
    return false;
  }
}

api.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.type === "getEnabled") {
    forceDarkEnabled().then((enabled) => sendResponse({ enabled }));
    return true;
  }
});

// Per-site choice, like Safari's Adaptive Dark Mode: right-click a page and turn
// darkening off (or back on) for that site only. Saved as "skip:<host>".
const MENU_OFF = "nox-site-off";
const MENU_ON = "nox-site-on";

function makeMenus() {
  if (!api.contextMenus) return;
  try {
    api.contextMenus.removeAll(() => {
      api.contextMenus.create({ id: MENU_OFF, title: "Nox: Don't darken this site", contexts: ["page", "frame"] });
      api.contextMenus.create({ id: MENU_ON, title: "Nox: Darken this site again", contexts: ["page", "frame"] });
    });
  } catch (e) {}
}

function hostOf(url) {
  try { return new URL(url).hostname; } catch (e) { return ""; }
}

if (api.contextMenus) {
  makeMenus();
  if (api.runtime.onInstalled) api.runtime.onInstalled.addListener(makeMenus);
  api.contextMenus.onClicked.addListener((info, tab) => {
    const host = hostOf((tab && tab.url) || info.pageUrl || "");
    if (!host || !api.storage) return;
    const key = "skip:" + host;
    const done = () => {
      if (tab && tab.id != null) {
        try { api.tabs.sendMessage(tab.id, { type: "siteChoiceChanged" }); } catch (e) {}
      }
    };
    if (info.menuItemId === MENU_OFF) api.storage.local.set({ [key]: true }).then(done, done);
    if (info.menuItemId === MENU_ON) api.storage.local.remove(key).then(done, done);
  });
}
