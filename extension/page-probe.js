// Runs in the page's main world (content scripts cannot see page JS objects such as `hass`).
// Publishes only the websocket state as a DOM attribute for content.js.
(function () {
  if (window.__haosKioskPageProbe) {
    return;
  }
  window.__haosKioskPageProbe = true;

  setInterval(() => {
    const ha = document.querySelector("home-assistant");
    if (!ha) {
      return;
    }
    const connection = ha.hass && ha.hass.connection;
    let state = "unknown";
    if (connection) {
      state = connection.connected ? "connected" : "disconnected";
    }
    document.documentElement.dataset.haosKioskWs = state;
  }, 5000);
})();
