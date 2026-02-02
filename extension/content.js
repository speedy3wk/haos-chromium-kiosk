(function () {
  const cfg = window.__HAOS_KIOSK_CONFIG || {};
  const haUrlHost = cfg.haUrlHost || "";

  const hideSidebar = Boolean(cfg.hideSidebar);
  const hideHeader = Boolean(cfg.hideHeader);
  const theme = cfg.theme || "";
  const darkMode = cfg.darkMode === undefined ? null : Boolean(cfg.darkMode);
  const sidebarMode = (cfg.sidebarMode || "").toString().toLowerCase();
  const browserModId = (cfg.browserModId || "").toString().trim();
  const username = cfg.username || "";
  const password = cfg.password || "";
  const loginDelayMs = Number.isFinite(cfg.loginDelayMs) ? cfg.loginDelayMs : 0;
  const refreshIntervalSec = Number.isFinite(cfg.refreshIntervalSec) ? cfg.refreshIntervalSec : 0;

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
    if (hideSidebar) {
      return "always_hidden";
    }
    if (sidebarMode === "none") {
      return "always_hidden";
    }
    if (sidebarMode === "narrow" || sidebarMode === "auto") {
      return "auto";
    }
    if (sidebarMode === "full") {
      return "";
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

  function buildHeaderStyle() {
    return [
      ":host, :root { --kiosk-header-height: 0px !important; }",
      "#view {",
      "  min-height: 100vh !important;",
      "  padding-top: calc(var(--kiosk-header-height) + env(safe-area-inset-top)) !important;",
      "}",
      ".header, .view-header, hui-view-header { display: none !important; }"
    ].join("\n");
  }

  function injectHeaderStyle() {
    if (!hideHeader) {
      return;
    }
    const styleId = "haos-kiosk-header-style";
    const applyToRoot = (root) => {
      if (!root || (root.querySelector && root.querySelector(`#${styleId}`))) {
        return;
      }
      const style = document.createElement("style");
      style.id = styleId;
      style.textContent = buildHeaderStyle();
      root.appendChild(style);
    };
    const applyToShadow = (el) => {
      if (!el || !el.shadowRoot) {
        return;
      }
      applyToRoot(el.shadowRoot);
    };

    const tryApply = () => {
      applyToRoot(document.head || document.documentElement);
      const ha = document.querySelector("home-assistant") || queryDeep("home-assistant");
      applyToShadow(ha);
      applyToShadow(queryDeep("ha-panel-lovelace"));
      applyToShadow(queryDeep("hui-root"));
      return Boolean(queryDeep("hui-root"));
    };

    if (!tryApply()) {
      const observer = new MutationObserver(() => {
        if (tryApply()) {
          observer.disconnect();
        }
      });
      observer.observe(document.documentElement, { childList: true, subtree: true });
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
      const childNodes = [];
      if (node.shadowRoot) {
        childNodes.push(node.shadowRoot);
      }
      if (node.children) {
        for (const child of node.children) {
          childNodes.push(child);
        }
      }
      for (const child of childNodes) {
        queue.push(child);
      }
    }
    return null;
  }

  function attemptAutoLogin() {
    if (window.__haosKioskLoginTried) {
      return;
    }
    if (!username || !password) {
      return;
    }
    const isAuthPage = window.location.pathname.includes("/auth/");
    if (!isAuthPage) {
      return;
    }

    window.__haosKioskLoginTried = true;
    let tries = 0;

    function attempt() {
      tries += 1;
      const usernameField = queryDeep("input[autocomplete='username']");
      const passwordField = queryDeep("input[autocomplete='current-password']") ||
        queryDeep("input[type='password']");
      const haCheckbox = queryDeep("ha-checkbox") ||
        queryDeep("mwc-checkbox") ||
        queryDeep("input[type='checkbox']");
      const submitButton = queryDeep("ha-button, mwc-button, button[type='submit']");

      if (usernameField && passwordField && submitButton) {
        usernameField.value = username;
        usernameField.dispatchEvent(new Event("input", { bubbles: true }));
        usernameField.dispatchEvent(new Event("change", { bubbles: true }));

        passwordField.value = password;
        passwordField.dispatchEvent(new Event("input", { bubbles: true }));
        passwordField.dispatchEvent(new Event("change", { bubbles: true }));

        if (haCheckbox) {
          if (haCheckbox.tagName && haCheckbox.tagName.toLowerCase() === "input") {
            haCheckbox.checked = true;
          } else {
            haCheckbox.setAttribute("checked", "");
          }
          haCheckbox.dispatchEvent(new Event("change", { bubbles: true }));
          haCheckbox.dispatchEvent(new Event("input", { bubbles: true }));
        }

        submitButton.click();
        return;
      }

      if (tries < 10) {
        setTimeout(attempt, 500);
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

  function startWsWatchdog() {
    if (window.__haosKioskWsWatchdogStarted) {
      return;
    }
    window.__haosKioskWsWatchdogStarted = true;
    let disconnectedCount = 0;
    setInterval(() => {
      if (isAuthCallbackUrl()) {
        return;
      }
      const app = window.APP;
      const connected = app && app.connection && app.connection.connected;
      if (connected === false) {
        disconnectedCount += 1;
      } else if (connected === true) {
        disconnectedCount = 0;
      }
      if (disconnectedCount >= 3 && canReloadNow()) {
        window.location.reload();
      }
    }, 10000);
  }

  function startLoadFailureWatchdog() {
    if (window.__haosKioskLoadWatchdogStarted) {
      return;
    }
    window.__haosKioskLoadWatchdogStarted = true;
    let failCount = 0;
    setInterval(() => {
      if (isAuthCallbackUrl()) {
        return;
      }
      const bodyText = document.body ? document.body.textContent || "" : "";
      if (bodyText.includes("Unable to connect to Home Assistant")) {
        failCount += 1;
      } else {
        failCount = 0;
      }
      if (failCount >= 3 && canReloadNow()) {
        window.location.reload();
      }
    }, 5000);
  }

  function installUnhandledRejectionGuard() {
    if (window.__haosKioskUnhandledGuard) {
      return;
    }
    window.__haosKioskUnhandledGuard = true;
    window.addEventListener("unhandledrejection", (event) => {
      const reason = event.reason;
      const message = typeof reason === "string"
        ? reason
        : (reason && reason.message) ? reason.message : "";
      if (!message) {
        return;
      }
      if (
        message.includes("Load failed") ||
        message.includes("Failed to fetch") ||
        message.includes("NetworkError") ||
        message.includes("AbortError") ||
        message.includes("ServiceWorker")
      ) {
        event.preventDefault();
      }
    });
  }

  function startRefreshTimer() {
    if (window.__haosKioskRefreshTimerStarted) {
      return;
    }
    window.__haosKioskRefreshTimerStarted = true;
    const intervalMs = Math.max(0, Number(refreshIntervalSec) * 1000);
    if (!intervalMs) {
      return;
    }
    setInterval(() => {
      if (isAuthCallbackUrl() || document.hidden) {
        return;
      }
      if (canReloadNow()) {
        window.location.reload();
      }
    }, intervalMs);
  }


  function handleConnectionError() {
    if (window.__haosKioskAuthRedirected) {
      return;
    }
    if (isAuthCallbackUrl()) {
      return;
    }
    const bodyText = document.body ? document.body.textContent || "" : "";
    if (!bodyText.includes("Unable to connect to Home Assistant")) {
      return;
    }
    window.__haosKioskAuthRedirected = true;
    try {
      window.localStorage.removeItem("hassTokens");
    } catch (err) {
      console.warn("haos-kiosk: failed to clear tokens", err);
    }
    const authUrl = buildAuthUrl();
    setTimeout(() => {
      window.location.href = authUrl;
    }, 1000);
  }

  function boot() {
    applySettings();
    injectHeaderStyle();
    attemptAutoLogin();
    installUnhandledRejectionGuard();
    startWsWatchdog();
    startLoadFailureWatchdog();
    startRefreshTimer();
    handleConnectionError();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  } else {
    boot();
  }
})();
