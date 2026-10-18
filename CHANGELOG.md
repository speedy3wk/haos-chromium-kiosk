# Changelog

## 0.1.69

### Added
- Hardware video decoding via VA-API on Intel (iHD, x86_64) and AMD GPUs. The image now ships the VA-API drivers, and the startup log shows the detected driver and decode profiles. New option `hw_video_decode` (default `true`) to turn it off.

### Fixed
- Extension now only runs on the configured Home Assistant host. Previously credentials could be auto-filled on any page with `/auth/` in its path.
- Connection and load-failure watchdogs actually work now. Websocket state comes from a main-world probe, and the `ha-init-page` is detected inside the shadow DOM. Reloads only happen once Home Assistant answers again.
- `hide_header` works reliably, including after dashboard navigation, without continuous full-DOM scans.
- `video_profile_preset: passthrough` no longer forces `max bpc`, Colorspace or Broadcast RGB at startup.
- `rgb_range` is applied with `color_space: auto` too (useful on Intel).
- Possible false negatives in xrandr property detection under `pipefail` (SIGPIPE race).
- Stale Chromium profile locks no longer block a restart, and the "Restore pages?" bubble is suppressed.
- Chromium start waits for Home Assistant, so the kiosk no longer gets stuck on a browser error page after a reboot.
- The add-on exits when Xorg dies so the Supervisor watchdog can restart it.
- The connectivity check uses the default port of the URL scheme (443 for `https`).
- `software_rendering` no longer uses the removed `--use-gl=swiftshader` flag.
- Removed the misleading `ha_dashboard` warning for normal `dashboard-*` / `lovelace` paths.

### Changed
- Base image pinned to `ghcr.io/home-assistant/base:3.24`. The Supervisor no longer passes `BUILD_FROM`.
- Option schema: `ha_password` is a masked password field, `ha_url` is validated as a URL, and numeric options have ranges.
- Removed unused `ingress`, `homeassistant_api`, `auth_api` and `addon_config` mapping.
- Removed unused packages (onboard, x11vnc, xdotool, xinput, setxkbmap, py3-xlib, patch, bc, aiohttp, websockets) and obsolete Chromium flags.
- Cleaned up duplicated logic in `run.sh`.
- Documented that a theme saved in the HA user profile (HA 2026.2+) overrides `ha_theme`/`dark_mode`.
