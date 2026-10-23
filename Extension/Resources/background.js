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
