# HAOS Chromium Kiosk

Chromium-based kiosk app for HAOS HDMI output. Designed to display a Lovelace panel view in kiosk aka Fullscreen mode.
Large parts of the code are inspired by the HAOS Kiosk App from https://github.com/puterboy/HAOS-kiosk/. 

## Features
- Chromium in kiosk mode on the HAOS host HDMI output
- Optional auto-login (user/pass)
- Screen timeout and rotation
- HDMI/USB audio sink selection
- Chromium watchdog with health endpoint
- Extension-based UI tweaks (sidebar/header/theme)

## Options
- `ha_url`: Base URL for Home Assistant (default `http://homeassistant:8123`)
- `ha_dashboard`: Optional dashboard path
- `ha_username` / `ha_password`: For auto-login (optional)
- `dark_mode`: Force Chromium dark mode
- `ha_theme`: Home Assistant theme name (optional); use `{ "dark": true }` or `{ "dark": false }` to force default theme mode
- `ha_sidebar`: full | narrow | none | auto
- `hide_sidebar`: Hide Home Assistant sidebar
- `hide_header`: Hide Home Assistant header
- `resolution_width`: Force display width (0 = auto)
- `resolution_height`: Force display height (0 = auto)
- `refresh_rate`: Force display refresh rate (0 = auto)
- `login_delay`: Seconds before auto-login attempt
- `browser_refresh`: Seconds between refreshes (0 = disabled, default 0)
- `browser_mod_id`: Value for browser_mod-browser-id
- `clear_chromium_on_start`: Reset Chromium profile on startup (default false)
- `zoom_level`: 100 = normal
- `screen_timeout`: Seconds to blank display (0 = never)
- `rotate_display`: normal | left | right | inverted
- `audio_sink`: auto | hdmi | usb | none
- `hide_cursor`: Hide mouse cursor

## Notes
- Auto-login and UI tweaks are injected via a bundled Chromium extension.
- Startup logs include connectivity checks to the configured `ha_url`.
- Home Assistant 2026.2+ moved some dashboard and app panels; if the kiosk shows a redirect or blank panel, review `ha_dashboard` to match the new dashboard/app panel URL.
- Created with AI tools, reviewed and tested by me.

## Installation (Custom App Repository)
1. In Home Assistant, go to Settings -> Apps -> Install App (App-Store).
2. Open the three-dot menu -> Repositories.
3. Add this repository URL: `https://github.com/speedy3wk/haos-chromium-kiosk`
4. Refresh the App-Store and install "HAOS Chromium Kiosk".

## HACS
This is an unofficial app and is not listed in HACS. Install it via the Custom App Repository method above.
