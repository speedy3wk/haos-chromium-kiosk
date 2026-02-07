#!/usr/bin/with-contenv bashio
set -euo pipefail

export NO_PROXY=127.0.0.1,localhost
export no_proxy=127.0.0.1,localhost
export HTTP_PROXY=
export HTTPS_PROXY=
export http_proxy=
export https_proxy=

TTY0_DELETED=""
cleanup() {
  if [ -n "$TTY0_DELETED" ]; then
    mknod -m 620 /dev/tty0 c 4 0 || true
  fi
}
trap cleanup EXIT

load_config_var() {
  local VAR_NAME="$1"
  local DEFAULT_VALUE="$2"
  local VALUE

  if bashio::config.has_value "$VAR_NAME"; then
    VALUE="$(bashio::config "$VAR_NAME")"
  else
    VALUE="$DEFAULT_VALUE"
  fi
  export "${VAR_NAME^^}"="$VALUE"
}

load_config_var ha_url "http://homeassistant:8123"
load_config_var ha_dashboard ""
load_config_var ha_username ""
load_config_var ha_password ""
load_config_var dark_mode true
load_config_var ha_theme ""
load_config_var ha_sidebar "full"
load_config_var hide_sidebar false
load_config_var hide_header false
load_config_var resolution_width 0
load_config_var resolution_height 0
load_config_var refresh_rate 0
load_config_var login_delay 2
load_config_var browser_refresh 0
load_config_var browser_mod_id "haos_kiosk"
load_config_var clear_chromium_on_start false
load_config_var zoom_level 100
load_config_var screen_timeout 0
load_config_var rotate_display "normal"
load_config_var audio_sink "auto"
load_config_var hide_cursor true

HA_URL_BASE="$HA_URL"
HA_URL_BASE="${HA_URL_BASE%/}"
if [ -n "$HA_DASHBOARD" ]; then
  HA_URL_BASE="$HA_URL_BASE/$HA_DASHBOARD"
fi

HA_URL_HOST="$(python3 - <<'PY'
import os
from urllib.parse import urlparse

value = os.environ.get("HA_URL", "")
parsed = urlparse(value)
if parsed.scheme and parsed.netloc:
  print(f"{parsed.scheme}://{parsed.netloc}".rstrip("/"))
else:
  print(value.rstrip("/"))
PY
)"

case "$HA_URL_HOST" in
  http://127.0.0.1:8123|http://localhost:8123)
    bashio::log.warning "haos-kiosk: HA_URL_HOST is localhost; using localhost as-is"
    ;;
esac

export HA_URL_BASE
export HA_URL_HOST

if [ "$CLEAR_CHROMIUM_ON_START" = true ]; then
  bashio::log.info "haos-kiosk: clear_chromium_on_start enabled"
  rm -rf /data/chromium
fi

bashio::log.info "haos-kiosk: ha_url=$HA_URL"
bashio::log.info "haos-kiosk: ha_dashboard=$HA_DASHBOARD"
bashio::log.info "haos-kiosk: ha_dashboard_full=$HA_URL_BASE"
if [ -n "$HA_DASHBOARD" ]; then
  case "$HA_DASHBOARD" in
    lovelace*|dashboard*|hassio*|addon*|developer-tools*|config*)
      bashio::log.warning "haos-kiosk: ha_dashboard looks like a legacy or internal path; verify it still resolves on HA 2026.2+"
      ;;
  esac
fi
bashio::log.info "haos-kiosk: dark_mode=$DARK_MODE ha_sidebar=$HA_SIDEBAR hide_sidebar=$HIDE_SIDEBAR hide_header=$HIDE_HEADER"
bashio::log.info "haos-kiosk: resolution=${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT} refresh_rate=$REFRESH_RATE"
bashio::log.info "haos-kiosk: browser_refresh=$BROWSER_REFRESH browser_mod_id=$BROWSER_MOD_ID"
bashio::log.info "haos-kiosk: rotate_display=$ROTATE_DISPLAY zoom_level=$ZOOM_LEVEL screen_timeout=$SCREEN_TIMEOUT"
bashio::log.info "haos-kiosk: audio_sink=$AUDIO_SINK"
bashio::log.info "haos-kiosk: hide_cursor=$HIDE_CURSOR"


python3 - <<'PY'
import os
import socket
import urllib.request
from urllib.parse import urlparse

ha_url = os.environ.get("HA_URL", "")
ha_url_base = os.environ.get("HA_URL_BASE", "")

def _log(msg: str) -> None:
  print(f"haos-kiosk: {msg}")

def _check_url(label: str, url: str) -> None:
  if not url:
    _log(f"connectivity {label}: empty")
    return
  try:
    req = urllib.request.Request(url, headers={"User-Agent": "haos-kiosk-check"})
    with urllib.request.urlopen(req, timeout=3) as resp:
      _log(f"connectivity {label}: {url} -> {resp.status}")
  except Exception as exc:
    _log(f"connectivity {label}: {url} -> error {exc}")

def _check_tcp(hostname: str | None, port: int | None) -> None:
  if not hostname or not port:
    _log("connectivity tcp: missing host or port")
    return
  try:
    sock = socket.create_connection((hostname, port), timeout=3)
    sock.close()
    _log(f"connectivity tcp: {hostname}:{port} -> ok")
  except Exception as exc:
    _log(f"connectivity tcp: {hostname}:{port} -> error {exc}")


parsed = urlparse(ha_url)
host = parsed.hostname
if host:
  try:
    _log(f"dns {host}: {socket.gethostbyname(host)}")
  except Exception as exc:
    _log(f"dns {host}: error {exc}")

_check_tcp(parsed.hostname, parsed.port or 8123)

_check_url("ha_url", ha_url)
_check_url("ha_url_base", ha_url_base)
PY

bashio::log.info "Starting DBus..."
mkdir -p /run/dbus
dbus-daemon --system --fork
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address || true)
if [ -n "$DBUS_SESSION_BUS_ADDRESS" ]; then
  export DBUS_SESSION_BUS_ADDRESS
  echo "export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS'" >> "$HOME/.profile" || true
fi

bashio::log.info "DRM video cards:"
find /dev/dri/ -maxdepth 1 -type c -name 'card[0-9]*' 2>/dev/null | sed 's/^/  /'
bashio::log.info "DRM video card driver and connection status:"
selected_card=""
for status_path in /sys/class/drm/card[0-9]*-*/status; do
  [ -e "$status_path" ] || continue
  status=$(cat "$status_path")
  card_port=$(basename "$(dirname "$status_path")")
  card=${card_port%%-*}
  driver=$(basename "$(readlink "/sys/class/drm/$card/device/driver")")
  if [ -z "$selected_card" ] && [ "$status" = "connected" ]; then
    selected_card="$card"
    printf "  *"
  else
    printf "   "
  fi
  printf "%-25s%-20s%s\n" "$card_port" "$driver" "$status"
done

if [ -z "$selected_card" ]; then
  bashio::log.error "ERROR: No connected video card detected. Exiting.."
  exit 1
fi

if [ -e "/dev/tty0" ]; then
  bashio::log.info "Attempting to remount /dev as 'rw' so we can (temporarily) delete /dev/tty0..."
  if ! mount -o remount,rw /dev ; then
    bashio::log.error "Failed to remount /dev as read-write..."
    exit 1
  fi
  if ! rm -f /dev/tty0 ; then
    bashio::log.error "Failed to delete /dev/tty0..."
    exit 1
  fi
  TTY0_DELETED=1
  bashio::log.info "Deleted /dev/tty0 successfully..."
fi

bashio::log.info "Starting udev..."
if ! udevd --daemon || ! udevadm trigger; then
  bashio::log.warning "WARNING: Failed to start udevd or trigger udev, input devices may not work"
fi
udevadm settle --timeout=10 || true

bashio::log.info "Starting Xorg..."
rm -rf /tmp/.X*-lock
cp -a /etc/X11/xorg.conf.default /etc/X11/xorg.conf
sed -i "/Option[[:space:]]\+\"DRI\"[[:space:]]\+\"3\"/a\    Option          \"kmsdev\" \"/dev/dri/$selected_card\"" /etc/X11/xorg.conf
echo "."
printf '%*s xorg.conf %*s\n' 35 '' 34 '' | tr ' ' '#'
cat /etc/X11/xorg.conf
printf '%*s\n' 80 '' | tr ' ' '#'
echo "."

NOCURSOR=""
if [ "$HIDE_CURSOR" = true ]; then
  NOCURSOR="-nocursor"
fi
Xorg $NOCURSOR :0 -noreset -nolisten tcp </dev/null 2>&1 | grep -v "Could not resolve keysym XF86\|Errors from xkbcomp are not fatal\|XKEYBOARD keymap compiler (xkbcomp) reports" &

XSTARTUP=20
for i in $(seq 1 $XSTARTUP); do
  if xset q >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if [ -n "$TTY0_DELETED" ]; then
  if mknod -m 620 /dev/tty0 c 4 0; then
    bashio::log.info "Restored /dev/tty0 successfully..."
  else
    bashio::log.error "Failed to restore /dev/tty0..."
  fi
fi

if ! xset q >/dev/null 2>&1; then
  bashio::log.error "Error: X server failed to start within $XSTARTUP seconds."
  exit 1
fi

sleep 2

bashio::log.info "Starting Openbox..."
openbox &

if [ "$HIDE_CURSOR" = true ]; then
  unclutter-xfixes --start-hidden --hide-on-touch --fork --timeout 1 >/dev/null 2>&1 || true
fi

bashio::log.info "Setting display rotation: $ROTATE_DISPLAY"
case "$ROTATE_DISPLAY" in
  left) xrandr --output "$(xrandr | awk '/ connected/{print $1; exit}')" --rotate left ;;
  right) xrandr --output "$(xrandr | awk '/ connected/{print $1; exit}')" --rotate right ;;
  inverted) xrandr --output "$(xrandr | awk '/ connected/{print $1; exit}')" --rotate inverted ;;
  *) xrandr --output "$(xrandr | awk '/ connected/{print $1; exit}')" --rotate normal ;;
esac

if [ "$RESOLUTION_WIDTH" -gt 0 ] && [ "$RESOLUTION_HEIGHT" -gt 0 ]; then
  bashio::log.info "Setting resolution: ${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT}"
  if [ "$REFRESH_RATE" -gt 0 ]; then
    bashio::log.info "Setting refresh rate: ${REFRESH_RATE}"
    xrandr --output "$(xrandr | awk '/ connected/{print $1; exit}')" --mode "${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT}" --rate "$REFRESH_RATE" || true
  else
    xrandr --output "$(xrandr | awk '/ connected/{print $1; exit}')" --mode "${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT}" || true
  fi
fi

if [ "$SCREEN_TIMEOUT" -gt 0 ]; then
  bashio::log.info "Setting screen timeout: $SCREEN_TIMEOUT"
  xset s "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT"
  xset dpms "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT"
else
  xset s off
  xset -dpms
fi

if [ "$AUDIO_SINK" != "none" ]; then
  bashio::log.info "Setting audio sink: $AUDIO_SINK"
  if [ "$AUDIO_SINK" = "hdmi" ]; then
    pactl set-default-sink "$(pactl list short sinks | awk '/hdmi/{print $2; exit}')" || true
  elif [ "$AUDIO_SINK" = "usb" ]; then
    pactl set-default-sink "$(pactl list short sinks | awk '/usb/{print $2; exit}')" || true
  fi
fi


launch_chromium() {
  mkdir -p /data/chromium
  chromium \
    --no-sandbox \
    --disable-dev-shm-usage \
    --no-first-run \
    --no-default-browser-check \
    --disable-features=TranslateUI,PasswordManagerOnboarding,PasswordManagerEnableUpdatingPasswords \
    --disable-save-password-bubble \
    --password-store=basic \
    --use-mock-keychain \
    $(if [ "$DARK_MODE" = true ]; then echo "--force-dark-mode --enable-features=WebUIDarkMode"; fi) \
    --disable-extensions-except=/data/haos-extension \
    --load-extension=/data/haos-extension \
    --autoplay-policy=no-user-gesture-required \
    --kiosk \
    --start-fullscreen \
    --user-data-dir=/data/chromium \
    --force-device-scale-factor=$(echo "scale=2; $ZOOM_LEVEL/100" | bc -l) \
    "$HA_URL_BASE" &
}


configure_chromium_prefs() {
  python3 - <<'PY'
import json
import os

prefs_path = "/data/chromium/Default/Preferences"
os.makedirs(os.path.dirname(prefs_path), exist_ok=True)

try:
  with open(prefs_path, "r", encoding="utf-8") as f:
    data = json.load(f)
except Exception:
  data = {}

data["credentials_enable_service"] = False
profile = data.get("profile", {})
profile["password_manager_enabled"] = False
data["profile"] = profile

with open(prefs_path, "w", encoding="utf-8") as f:
  json.dump(data, f)
PY
}

init_extension() {
  mkdir -p /data/haos-extension
  cp -a /haos-extension/. /data/haos-extension/
  python3 - <<'PY'
import json
import os

def _as_bool(value: str) -> bool:
  return value.strip().lower() == "true"

def _as_int_ms(value: str) -> int:
  try:
    return max(int(float(value) * 1000), 0)
  except Exception:
    return 0

def _as_int(value: str) -> int:
  try:
    return max(int(float(value)), 0)
  except Exception:
    return 0

config = {
  "haUrlHost": os.getenv("HA_URL_HOST", "").strip(),
  "haUrlBase": os.getenv("HA_URL_BASE", "").strip(),
  "haUrlHosts": [],
  "username": os.getenv("HA_USERNAME", ""),
  "password": os.getenv("HA_PASSWORD", ""),
  "darkMode": _as_bool(os.getenv("DARK_MODE", "true")),
  "sidebarMode": os.getenv("HA_SIDEBAR", "full").strip().lower(),
  "browserModId": os.getenv("BROWSER_MOD_ID", "haos_kiosk").strip(),
  "hideSidebar": _as_bool(os.getenv("HIDE_SIDEBAR", "false")),
  "hideHeader": _as_bool(os.getenv("HIDE_HEADER", "false")),
  "theme": os.getenv("HA_THEME", ""),
  "loginDelayMs": _as_int_ms(os.getenv("LOGIN_DELAY", "2")),
  "refreshIntervalSec": _as_int(os.getenv("BROWSER_REFRESH", "0")),
}

def _host(url: str) -> str:
  try:
    from urllib.parse import urlparse
    parsed = urlparse(url)
    if parsed.scheme and parsed.netloc:
      return f"{parsed.scheme}://{parsed.netloc}".rstrip("/")
  except Exception:
    pass
  return ""

hosts = set()
for value in (config["haUrlHost"], config["haUrlBase"]):
  host = _host(value)
  if host:
    hosts.add(host)
config["haUrlHosts"] = sorted(hosts)

with open("/data/haos-extension/config.js", "w", encoding="utf-8") as handle:
  handle.write("window.__HAOS_KIOSK_CONFIG = ")
  handle.write(json.dumps(config))
  handle.write(";\n")
PY
}

bashio::log.info "Launching Chromium..."
configure_chromium_prefs
init_extension
launch_chromium


bashio::log.info "Starting Chromium watchdog"
(
  sleep 5
  while true; do
    if ! pgrep -f chromium >/dev/null 2>&1; then
      bashio::log.warning "Chromium not running, restarting"
      launch_chromium
    fi
    sleep 10
  done
) &

while true; do
  sleep 60
done
