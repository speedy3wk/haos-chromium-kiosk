# HAOS Chromium Kiosk

Chromium-based kiosk add-on for HAOS HDMI output. Displays a Home Assistant dashboard in full-screen kiosk mode directly on the host display output.
Large parts of the code are inspired by the HAOS Kiosk App from https://github.com/puterboy/HAOS-kiosk/.

## Features
- Chromium in kiosk mode on the HAOS host HDMI output
- Optional auto-login (username/password)
- Screen timeout and display rotation
- HDMI/USB audio sink selection
- Display output management with reconnect monitoring
- HDR and color space configuration via xrandr (AMD/Nvidia; Intel: Broadcast RGB)
- Chromium watchdog (auto-restarts if Chromium exits)
- Extension-based UI tweaks (sidebar mode, header, theme, dark mode)
- Clean startup log with optional verbose debug output

## Options

### Display & Browser
| Option | Default | Description |
|---|---|---|
| `ha_url` | `http://homeassistant:8123` | Base URL for Home Assistant |
| `ha_dashboard` | _(empty)_ | Optional dashboard path appended to the URL |
| `ha_username` / `ha_password` | _(empty)_ | Auto-login credentials (optional) |
| `dark_mode` | `true` | Force Chromium dark mode |
| `ha_theme` | _(empty)_ | Home Assistant theme name (optional) |
| `ha_sidebar` | `full` | Sidebar visibility: `full` \| `narrow` \| `none` \| `auto` |
| `hide_header` | `false` | Hide the Home Assistant header bar |
| `zoom_level` | `100` | Browser zoom level (100 = normal) |
| `login_delay` | `2` | Seconds before auto-login attempt |
| `browser_refresh` | `0` | Page refresh interval in seconds (0 = disabled) |
| `browser_mod_id` | `haos_kiosk` | ID sent as `browser_mod` browser-id |
| `clear_chromium_on_start` | `false` | Wipe Chromium profile on every startup |
| `software_rendering` | `false` | Force CPU-only rendering via SwiftShader (fallback for GPU issues) |

### Display Hardware
| Option | Default | Description |
|---|---|---|
| `resolution_width` / `resolution_height` | `0` | Force display resolution (0 = auto) |
| `refresh_rate` | `0` | Force refresh rate in Hz (0 = auto; decimals like `59.94` supported) |
| `rotate_display` | `normal` | Display rotation: `normal` \| `left` \| `right` \| `inverted` |
| `screen_timeout` | `0` | Seconds before screen blank/DPMS (0 = never) |
| `audio_sink` | `auto` | Audio output: `auto` \| `hdmi` \| `usb` \| `none` |
| `hide_cursor` | `true` | Hide the mouse cursor |
| `force_output_on` | `false` | Force DRM connector on when no display is detected |

### Video & Color
| Option | Default | Description |
|---|---|---|
| `video_profile_preset` | `passthrough` | Applies a preset for `hdr_mode`, `color_space`, `color_profile`, `rgb_range` — see presets below |
| `hdr_mode` | `auto` | HDR via xrandr `max bpc` / Colorspace: `auto` \| `off` \| `on` |
| `color_space` | `auto` | Output color format: `auto` \| `rgb` \| `yuv444` \| `yuv422` \| `yuv420` |
| `color_profile` | `auto` | Explicit xrandr colorspace profile (see full list below) |
| `rgb_range` | `auto` | Broadcast RGB range: `auto` \| `full` \| `limited` (only applies to RGB output) |

### Debug
| Option | Default | Description |
|---|---|---|
| `debug_logging` | `false` | Enable verbose debug output in the add-on log |

## Video Profile Presets

`video_profile_preset` is the recommended entry point for color/HDR configuration. Setting it to anything other than `custom` overrides `hdr_mode`, `color_space`, `color_profile`, and `rgb_range`.

| Preset | HDR | Color Space | Color Profile | RGB Range | Use Case |
|---|---|---|---|---|---|
| `passthrough` | auto | auto | auto | auto | Default — let the display and driver negotiate |
| `custom` | _(from individual options)_ | — | — | — | Full manual control |
| `sdr_rgb_limited` | off | rgb | auto | limited | SDR with limited RGB (16–235), common for TV displays |
| `sdr_bt709_ycc` | off | yuv422 | bt709 | auto | SDR YCC BT.709, typical broadcast/TV signal style |
| `hdr_bt2020_ycc` | on | yuv422 | bt2020_ycc | auto | HDR BT.2020 YCC (AMD/Nvidia; requires compatible display and driver) |

### Color Profile Values (for `color_profile`)
`auto` · `default` · `bt709` · `bt2020_ycc` · `bt2020_rgb` · `bt2020_cycc` · `smpte170m` · `xvycc_709` · `xvycc_601` · `sycc_601` · `opycc_601` · `oprgb` · `dci_p3_d65` · `dci_p3_theater`

### Hardware Notes
- **Intel (i915/modesetting):** Only `Broadcast RGB` (`rgb_range`) is reliably available. `Colorspace`/`ColorSpace` properties are not exposed by i915 — HDR and explicit color profiles will have no effect.
- **AMD (amdgpu) / Nvidia:** Full xrandr color space and HDR property support; all presets and `color_profile` values work as intended.
- `color_profile != auto` takes priority over `color_space` mapping.
- `rgb_range` is ignored for YCC-based profiles.

## Logging

In normal operation the add-on log shows only:
- A compact settings summary on startup (URL, display, video, browser settings)
- Warnings and errors
- Key runtime events (display reconnect, Chromium restart)

Enable `debug_logging: true` for verbose output: DRM connector details, xorg.conf, xrandr property queries, connectivity checks, and all internal state changes.

## Notes
- Auto-login and UI tweaks are injected via a bundled Chromium extension.
- Home Assistant 2026.2+ reorganized some dashboard paths. If the kiosk shows a redirect or blank panel, update `ha_dashboard` to match the current URL.
- `video_profile_preset=passthrough` avoids any explicit forced color/HDR state and is the safest default.
- Created with AI tools, reviewed and tested by me.

## Installation (Custom Add-on Repository)
1. In Home Assistant, go to **Settings → Add-ons → Add-on Store**.
2. Open the three-dot menu → **Repositories**.
3. Add: `https://github.com/speedy3wk/haos-chromium-kiosk`
4. Refresh the store and install **HAOS Chromium Kiosk**.

## HACS
This is an unofficial add-on and is not listed in HACS. Install it via the Custom Add-on Repository method above.
