(function () {
  const cfg = window.__HAOS_KIOSK_CONFIG || {};

  const allowedOrigins = Array.isArray(cfg.haUrlHosts) ? cfg.haUrlHosts : [];
  if (allowedOrigins.length && !allowedOrigins.includes(window.location.origin)) {
    return;
  }

  const haUrlHost = cfg.haUrlHost || "";
  const hideHeader = Boolean(cfg.hideHeader);
  const theme = cfg.theme || "";
  const darkMode = cfg.darkMode === undefined ? null : Boolean(cfg.darkMode);
  const sidebarMode = (cfg.sidebarMode || "").toString().toLowerCase();
  const browserModId = (cfg.browserModId || "").toString().trim();
  const username = cfg.username || "";
  const password = cfg.password || "";
  const loginDelayMs = Number.isFinite(cfg.loginDelayMs) ? cfg.loginDelayMs : 0;
  const refreshIntervalSec = Number.isFinite(cfg.refreshIntervalSec) ? cfg.refreshIntervalSec : 0;

  const INIT_FAILURE_KEY = "haos-kiosk-init-failures";

  function safeLocalStorageSet(key, value) {
    try {
      window.localStorage.setItem(key, value);
    } catch (err) {
      console.warn("haos-kiosk: localStorage set failed", err);
    }
  }

  function safeLocalStorageRemove(key) {
    try {
      window.localStorage.removeItem(key);
    } catch (err) {
      console.warn("haos-kiosk: localStorage remove failed", err);
    }
  }

  function safeLocalStorageSetJson(key, value) {
    safeLocalStorageSet(key, JSON.stringify(value));
  }

  function resolveSidebarValue() {
    if (sidebarMode === "none") {
      return "always_hidden";
    }
    if (sidebarMode === "narrow" || sidebarMode === "auto") {
      return "auto";
    }
    return "";
  }

  function resolveThemeSetting() {
    const raw = theme.trim();
    if (!raw || raw === "{}" || raw.toLowerCase() === "home assistant" || raw.toLowerCase() === "default") {
      if (typeof darkMode === "boolean") {
        return { theme: "", dark: darkMode };
      }
      return null;
    }

    if (raw.startsWith("{")) {
      try {
        const parsed = JSON.parse(raw);
        const themeValue = typeof parsed.theme === "string" ? parsed.theme : "";
        if (typeof parsed.dark === "boolean") {
          return { theme: themeValue, dark: parsed.dark };
        }
        if (themeValue) {
          return { theme: themeValue };
        }
      } catch (_err) {
        return { theme: raw };
      }
      return null;
    }

    return { theme: raw };
  }

  function applySettings() {
    if (browserModId) {
      safeLocalStorageSet("browser_mod-browser-id", browserModId);
    }

    const sidebarValue = resolveSidebarValue();
    if (sidebarValue) {
      safeLocalStorageSetJson("dockedSidebar", sidebarValue);
    } else {
      safeLocalStorageRemove("dockedSidebar");
    }

    const selectedTheme = resolveThemeSetting();
    if (selectedTheme) {
      safeLocalStorageSetJson("selectedTheme", selectedTheme);
    } else {
      safeLocalStorageRemove("selectedTheme");
    }
  }

  function queryDeep(selector, root) {
    const queue = [root || document];
    while (queue.length) {
      const node = queue.shift();
      if (!node) {
        continue;
      }
      if (node.querySelector) {
        const found = node.querySelector(selector);
        if (found) {
          return found;
        }
      }
      if (node.shadowRoot) {
        queue.push(node.shadowRoot);
      }
      if (node.children) {
        for (const child of node.children) {
          queue.push(child);
        }
      }
    }
    return null;
  }

  function pickFirstDeep(selectors) {
    for (const selector of selectors) {
      const found = queryDeep(selector);
      if (found) {
        return found;
      }
    }
    return null;
  }

  // Fast path through the known HA element tree; avoids a full deep scan on every poll.
  function getHaShadow() {
    const ha = document.querySelector("home-assistant");
    return ha && ha.shadowRoot ? ha.shadowRoot : null;
  }

  function findHuiRoot(allowDeepScan) {
    const haShadow = getHaShadow();
    const main = haShadow && haShadow.querySelector("home-assistant-main");
    const mainShadow = main && main.shadowRoot;
    const panel = mainShadow && mainShadow.querySelector("ha-panel-lovelace");
    const huiRoot = panel && panel.shadowRoot && panel.shadowRoot.querySelector("hui-root");
    if (huiRoot) {
      return huiRoot;
    }
    return allowDeepScan ? queryDeep("hui-root") : null;
  }

  function findInitPage() {
    const haShadow = getHaShadow();
    return (haShadow && haShadow.querySelector("ha-init-page")) || document.querySelector("ha-init-page");
  }

  function isAppLoaded() {
    const haShadow = getHaShadow();
    return Boolean(haShadow && haShadow.querySelector("home-assistant-main"));
  }

  function deepText(node) {
    if (!node) {
      return "";
    }
    let text = "";
    const queue = [node];
    while (queue.length) {
      const current = queue.shift();
      if (current.nodeType === Node.TEXT_NODE) {
        text += current.textContent + " ";
        continue;
      }
      if (current.shadowRoot) {
        queue.push(current.shadowRoot);
      }
      for (const child of current.childNodes || []) {
        queue.push(child);
      }
    }
    return text;
  }

  function buildHeaderStyle() {
    return [
      ":host { --header-height: 0px !important; }",
      ".header { display: none !important; }",
      "#view {",
      "  min-height: 100vh !important;",
      "  padding-top: env(safe-area-inset-top) !important;",
      "}"
    ].join("\n");
  }

  function startHeaderHider() {
    if (!hideHeader) {
      return;
    }
    const styleId = "haos-kiosk-header-style";
    let tick = 0;
    // HA renders inside shadow roots, which a document MutationObserver cannot see; poll cheaply
    // and re-apply whenever a new hui-root is created (dashboard navigation, reconnect).
    const apply = () => {
      tick += 1;
      const huiRoot = findHuiRoot(tick % 5 === 0);
      const root = huiRoot && huiRoot.shadowRoot;
      if (!root || root.getElementById(styleId)) {
        return;
      }
      const style = document.createElement("style");
      style.id = styleId;
      style.textContent = buildHeaderStyle();
      root.appendChild(style);
    };
    apply();
    setInterval(apply, 1000);
  }

  function dispatchComposed(target, type) {
    if (!target || !target.dispatchEvent) {
      return;
    }
    target.dispatchEvent(new Event(type, { bubbles: true, composed: true }));
  }

  function findAuthFields() {
    const usernameField = pickFirstDeep([
      "ha-input[name='username']",
      "ha-input[autocomplete='username']",
      "ha-auth-textfield[name='username']",
      "ha-textfield[name='username']",
      "input[name='username']",
      "input[autocomplete='username']"
    ]);

    const passwordField = pickFirstDeep([
      "ha-input[name='password']",
      "ha-input[autocomplete='current-password']",
      "ha-auth-textfield[name='password']",
      "ha-textfield[name='password']",
      "input[name='password']",
      "input[autocomplete='current-password']",
      "input[type='password']"
    ]);

    return { usernameField, passwordField };
  }

  function setFieldValue(field, value) {
    if (!field) {
      return;
    }

    try {
      if ("value" in field) {
        field.value = value;
      }
    } catch (_err) {
      // ignore value assignment failures on non-standard elements
    }

    if (field.shadowRoot) {
      const innerInput = field.shadowRoot.querySelector("input");
      if (innerInput) {
        innerInput.value = value;
        dispatchComposed(innerInput, "input");
        dispatchComposed(innerInput, "change");
      }
    }

    dispatchComposed(field, "input");
    dispatchComposed(field, "change");
  }

  function setPersistCheckbox() {
    const checkbox = pickFirstDeep([
      "ha-checkbox",
      "mwc-checkbox",
      "input[type='checkbox']"
    ]);

    if (!checkbox) {
      return;
    }

    if ("checked" in checkbox) {
      checkbox.checked = true;
    } else {
      checkbox.setAttribute("checked", "");
    }

    dispatchComposed(checkbox, "input");
    dispatchComposed(checkbox, "change");
  }

  function submitAuthForm() {
    const submitButton = pickFirstDeep([
      ".action ha-button",
      ".action mwc-button",
      "ha-button[type='submit']",
      "mwc-button[type='submit']",
      "button[type='submit']",
      "ha-button",
      "mwc-button",
      "button"
    ]);

    if (submitButton && submitButton.click) {
      submitButton.click();
      return true;
    }

    const form = queryDeep("form");
    if (!form) {
      return false;
    }

    if (typeof form.requestSubmit === "function") {
      form.requestSubmit();
      return true;
    }

    form.dispatchEvent(new Event("submit", { bubbles: true, composed: true, cancelable: true }));
    return true;
  }

  function attemptAutoLogin() {
    if (window.__haosKioskLoginSubmitted || window.__haosKioskLoginAttemptRunning) {
      return;
    }
    if (!username || !password) {
      return;
    }
    if (!window.location.pathname.includes("/auth/")) {
      return;
    }

    window.__haosKioskLoginAttemptRunning = true;
    let tries = 0;
    const maxTries = 30;

    function attempt() {
      if (window.__haosKioskLoginSubmitted) {
        window.__haosKioskLoginAttemptRunning = false;
        return;
      }

      tries += 1;
      const { usernameField, passwordField } = findAuthFields();

      if (usernameField && passwordField) {
        setFieldValue(usernameField, username);
        setFieldValue(passwordField, password);
        setPersistCheckbox();

        if (submitAuthForm()) {
          window.__haosKioskLoginSubmitted = true;
          window.__haosKioskLoginAttemptRunning = false;
          return;
        }
      }

      if (tries < maxTries) {
        setTimeout(attempt, 500);
      } else {
        window.__haosKioskLoginAttemptRunning = false;
      }
    }

    setTimeout(attempt, Math.max(loginDelayMs, 0));
  }

  function buildAuthUrl() {
    const origin = haUrlHost || window.location.origin;
    const clientId = encodeURIComponent(origin + "/");
    const redirectUri = encodeURIComponent(origin + "/?auth_callback=1");
    return origin + "/auth/authorize?response_type=code&client_id=" + clientId + "&redirect_uri=" + redirectUri;
  }

  function isAuthPage() {
    return window.location.pathname.includes("/auth/");
  }

  function isAuthCallbackUrl() {
    const params = new URLSearchParams(window.location.search);
    return params.get("auth_callback") === "1" || params.has("code");
  }

  function canReloadNow() {
    const now = Date.now();
    const lastReload = window.__haosKioskLastReload || 0;
    if (now - lastReload < 20000) {
      return false;
    }
    window.__haosKioskLastReload = now;
    return true;
  }

  // Only navigate when HA answers; otherwise Chromium would land on its own network error
  // page, where this extension cannot run and the kiosk would stay stuck.
  async function isServerReachable() {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 5000);
    try {
      const res = await fetch(window.location.origin + "/manifest.json", {
        cache: "no-store",
        credentials: "omit",
        signal: controller.signal
      });
      return res.ok;
    } catch (_err) {
      return false;
    } finally {
      clearTimeout(timer);
    }
  }

  async function safeNavigate(target) {
    if (!canReloadNow()) {
      return false;
    }
    if (!(await isServerReachable())) {
      window.__haosKioskLastReload = 0;
      return false;
    }
    if (target) {
      window.location.href = target;
    } else {
      window.location.reload();
    }
    return true;
  }

  function readInitFailures() {
    try {
      return Number(window.sessionStorage.getItem(INIT_FAILURE_KEY)) || 0;
    } catch (_err) {
      return 0;
    }
  }

  function writeInitFailures(value) {
    try {
      if (value) {
        window.sessionStorage.setItem(INIT_FAILURE_KEY, String(value));
      } else {
        window.sessionStorage.removeItem(INIT_FAILURE_KEY);
      }
    } catch (_err) {
      // ignore
    }
  }

  // Reads the websocket state published by page-probe.js (runs in the page's main world).
  function startWsWatchdog() {
    let disconnectedCount = 0;
    setInterval(() => {
      if (isAuthPage() || isAuthCallbackUrl()) {
        return;
      }
      const state = document.documentElement.dataset.haosKioskWs;
      if (state === "disconnected") {
        disconnectedCount += 1;
      } else if (state === "connected") {
        disconnectedCount = 0;
      }
      if (disconnectedCount >= 3) {
        safeNavigate().then((navigated) => {
          if (navigated) {
            disconnectedCount = 0;
          }
        });
      }
    }, 10000);
  }

  // Detects a stuck ha-init-page ("Unable to connect to Home Assistant"). First recovery step is
  // a reload; if that does not help and auto-login is configured, stale tokens are dropped.
  function startLoadFailureWatchdog() {
    let failCount = 0;
    setInterval(() => {
      if (isAuthPage() || isAuthCallbackUrl()) {
        return;
      }
      if (isAppLoaded()) {
        failCount = 0;
        writeInitFailures(0);
        return;
      }
      const initPage = findInitPage();
      if (!initPage) {
        failCount = 0;
        return;
      }
      failCount += 1;
      if (failCount < 3) {
        return;
      }

      const failures = readInitFailures();
      const connectError = deepText(initPage).includes("Unable to connect");
      if (failures >= 1 && connectError && username && password) {
        safeNavigate(buildAuthUrl()).then((navigated) => {
          if (navigated) {
            safeLocalStorageRemove("hassTokens");
            writeInitFailures(0);
          }
        });
        return;
      }

      safeNavigate().then((navigated) => {
        if (navigated) {
          writeInitFailures(failures + 1);
          failCount = 0;
        }
      });
    }, 5000);
  }

  function startRefreshTimer() {
    const intervalMs = Math.max(0, Number(refreshIntervalSec) * 1000);
    if (!intervalMs) {
      return;
    }
    setInterval(() => {
      if (isAuthPage() || isAuthCallbackUrl() || document.hidden) {
        return;
      }
      safeNavigate();
    }, intervalMs);
  }

  function boot() {
    if (window.__haosKioskBooted) {
      return;
    }
    window.__haosKioskBooted = true;
    applySettings();
    startHeaderHider();
    attemptAutoLogin();
    startWsWatchdog();
    startLoadFailureWatchdog();
    startRefreshTimer();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  } else {
    boot();
  }
})();
