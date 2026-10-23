// Asks the Nox app whether Nox itself turned dark mode on. Pages are only darkened then.
// On a Mac, if the Nox app is not running there is nobody to ask, so pages stay as they are (off).
// Windows has no native host, so there the extension follows the system setting on its own.
const HOST = "com.solomon.nox";
const IS_MAC = /Mac/i.test((navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || "");
const NO_NOX = IS_MAC ? { enabled: false } : { enabled: true, standalone: true };

function askNox() {
  return new Promise((resolve) => {
    try {
      chrome.runtime.sendNativeMessage(HOST, { type: "get" }, (reply) => {
        if (chrome.runtime.lastError || !reply || typeof reply.enabled !== "boolean") {
          resolve(NO_NOX);
        } else {
          resolve({ enabled: reply.enabled });
        }
      });
    } catch (e) {
      resolve(NO_NOX);
    }
  });
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.type === "getEnabled") {
    askNox().then(sendResponse);
    return true;
  }
});
