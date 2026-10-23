(() => {
  const isTop = window.top === window;
  const api = typeof browser !== "undefined" ? browser : (typeof chrome !== "undefined" ? chrome : null);
  const STYLE_ID = "darkswitch-style";
  const KEEP = "data-ds-keep";
  const FILTER_CSS = `html { filter: invert(1) hue-rotate(180deg) !important; background: #fff; }`;
  // Re-flip only real photos and video so they keep true colours. Logos, icons and small
  // graphics flip WITH the page, so dark logo text (e.g. the Gmail wordmark) turns light.
  // Iframes are not flipped here: each frame decides for itself (see wantFilter).
  const MEDIA_CSS = `
    video, [${KEEP}] { filter: invert(1) hue-rotate(180deg) !important; }`;
  const GRAPHIC_HINT = /logo|icon|sprite|badge|emoji|wordmark|brand|\.svg/i;
  const MIN_PHOTO_PX = 96;

  // A "photo" is big enough and not named like a logo/icon. Everything else inverts with the page.
  function isPhoto(el) {
    const w = el.clientWidth || el.offsetWidth, h = el.clientHeight || el.offsetHeight;
    if (w < MIN_PHOTO_PX || h < MIN_PHOTO_PX) return false;
    if (el.tagName === "CANVAS" || el.tagName === "EMBED" || el.tagName === "OBJECT") return true;
    const hint = [el.currentSrc || el.src || "", el.alt || "", typeof el.className === "string" ? el.className : "",
      el.getAttribute("aria-label") || ""].join(" ");
    if (el.tagName !== "IMG") {
      const bg = getComputedStyle(el).backgroundImage;
      if (!bg || bg === "none" || !bg.includes("url(")) return false;
      return !GRAPHIC_HINT.test(bg + " " + hint);
    }
    return !GRAPHIC_HINT.test(hint);
  }

  function classifyMedia() {
    if (!document.getElementById(STYLE_ID)) return;
    const nodes = document.querySelectorAll('img, canvas, embed, object, [style*="background"]');
    for (const el of nodes) {
      if (isPhoto(el)) el.setAttribute(KEEP, "");
      else el.removeAttribute(KEEP);
    }
  }
  const mq = matchMedia("(prefers-color-scheme: dark)");
  // Off until Nox says it turned dark mode on itself (see background.js).
  let enabled = false;
  let nativelyDark = false;
  let parentInverted = true; // frames assume the top page is inverted until told otherwise

  function lum(r, g, b) { return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255; }

  function parseColor(str) {
    const m = (str || "").match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    const [r, g, b, a = 1] = m[1].split(/[,\/\s]+/).filter(Boolean).map(parseFloat);
    return { r, g, b, a };
  }

  // First opaque background colour at or behind an element (walks up the tree).
  function backgroundBehind(el) {
    for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
      const c = parseColor(getComputedStyle(n).backgroundColor);
      if (c && c.a >= 0.5) return c;
    }
    return null;
  }

  // Dark if most of what is actually on screen sits on dark backgrounds. Samples a 3x3 grid
  // of points, so sites that paint their background on inner sections are judged correctly.
  function pageIsNativelyDark() {
    const root = document.documentElement;
    if (!root || !document.body) return false;
    const scheme = (getComputedStyle(root).colorScheme || "").trim();
    const canvasDark = scheme === "dark" || scheme === "only dark";
    const w = window.innerWidth, h = window.innerHeight;
    let dark = 0, total = 0;
    for (const fx of [0.2, 0.5, 0.8]) {
      for (const fy of [0.2, 0.5, 0.8]) {
        const el = document.elementFromPoint(w * fx, h * fy);
        if (!el) continue;
        const c = backgroundBehind(el);
        total++;
        if (c ? lum(c.r, c.g, c.b) < 0.45 : canvasDark) dark++;
      }
    }
    if (total === 0) {
      const c = parseColor(getComputedStyle(document.body).backgroundColor);
      return c && c.a >= 0.5 ? lum(c.r, c.g, c.b) < 0.45 : canvasDark;
    }
    return dark / total >= 0.6;
  }

  // Top frame: invert light pages only. Sub-frame: inside an inverted top page, invert only
  // frames that are already dark (double flip = original look); if top is untouched, do nothing.
  function wantFilter() {
    if (!enabled || !mq.matches) return false;
    if (isTop) return !nativelyDark;
    return parentInverted ? nativelyDark : false;
  }

  function apply() {
    const want = wantFilter();
    const existing = document.getElementById(STYLE_ID);
    const css = FILTER_CSS + MEDIA_CSS;
    const parent = document.head || document.documentElement;
    if (want && !existing && parent) {
      const style = document.createElement("style");
      style.id = STYLE_ID;
      style.textContent = css;
      parent.appendChild(style);
    } else if (!want && existing) {
      existing.remove();
    }
    classifyMedia();
    if (isTop) {
      const inverted = enabled && mq.matches && !nativelyDark;
      for (const f of document.querySelectorAll("iframe")) {
        try { f.contentWindow.postMessage({ darkswitchInverted: inverted }, "*"); } catch (e) {}
      }
    }
  }

  // Measure the page's own colours with our style switched off, so our white backing
  // (html background) can't make an already-dark site look light.
  function recheckPage() {
    const ours = document.getElementById(STYLE_ID);
    if (ours) ours.disabled = true;
    nativelyDark = pageIsNativelyDark();
    if (ours) ours.disabled = false;
    apply();
  }

  function refreshSetting() {
    if (!api || !api.runtime) return;
    try {
      api.runtime.sendMessage({ type: "getEnabled" }).then((reply) => {
        if (reply && typeof reply.enabled === "boolean") {
          enabled = reply.enabled;
          apply();
        }
      }).catch(() => {});
    } catch (e) {}
  }

  if (!isTop) {
    window.addEventListener("message", (e) => {
      if (e.source === window.parent && e.data && typeof e.data.darkswitchInverted === "boolean") {
        parentInverted = e.data.darkswitchInverted;
        apply();
      }
    });
  }

  recheckPage();
  refreshSetting();
  // Dark mode just changed: ask again (Nox notes that it made the change a moment before it happens).
  mq.addEventListener("change", () => { recheckPage(); refreshSetting(); setTimeout(refreshSetting, 700); });
  document.addEventListener("visibilitychange", () => { if (!document.hidden) refreshSetting(); });
  window.addEventListener("focus", refreshSetting);
  document.addEventListener("DOMContentLoaded", recheckPage);
  window.addEventListener("load", () => {
    recheckPage();
    setTimeout(recheckPage, 1200);
    setTimeout(recheckPage, 3500);
  });
  // Late images finish loading with their real size; re-sort photos vs logos then.
  document.addEventListener("load", (e) => {
    if (e.target && e.target.tagName === "IMG") { clearTimeout(window.__dsI); window.__dsI = setTimeout(classifyMedia, 150); }
  }, true);
  {
    // Pages that switch theme late (SPA login screens), new images, and frames added after load.
    new MutationObserver(() => { clearTimeout(window.__dsT); window.__dsT = setTimeout(recheckPage, 400); })
      .observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: ["class", "style", "data-theme"] });
  }
})();
