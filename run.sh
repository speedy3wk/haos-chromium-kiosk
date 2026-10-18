#!/command/with-contenv bashio
set -euo pipefail

export NO_PROXY=127.0.0.1,localhost
export no_proxy=127.0.0.1,localhost
export HTTP_PROXY=
export HTTPS_PROXY=
export http_proxy=
export https_proxy=

TTY0_DELETED=""
cleanup() {
  if [ -n "$TTY0_DELETED" ] && [ ! -e "/dev/tty0" ]; then
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
load_config_var hide_header false
load_config_var resolution_width 0
load_config_var resolution_height 0
load_config_var refresh_rate 0
load_config_var video_profile_preset "passthrough"
load_config_var software_rendering false
load_config_var hdr_mode "auto"
load_config_var color_space "auto"
load_config_var rgb_range "auto"
load_config_var force_output_on false
load_config_var login_delay 2
load_config_var browser_refresh 0
load_config_var browser_mod_id "haos_kiosk"
load_config_var clear_chromium_on_start false
load_config_var zoom_level 100
load_config_var screen_timeout 0
load_config_var rotate_display "normal"
load_config_var audio_sink "auto"
load_config_var hide_cursor true
load_config_var debug_logging false

log_debug() {
  [ "${DEBUG_LOGGING:-false}" = "true" ] || return 0
  bashio::log.info "[DEBUG] $*"
}

apply_video_profile_preset() {
  case "$VIDEO_PROFILE_PRESET" in
    custom|"")
      return 0
      ;;
    passthrough)
      HDR_MODE="auto"
      COLOR_SPACE="auto"
      RGB_RANGE="auto"
      ;;
    sdr_rgb_limited)
      HDR_MODE="off"
      COLOR_SPACE="rgb"
      RGB_RANGE="limited"
      ;;
    sdr_bt709_ycc)
      HDR_MODE="off"
      COLOR_SPACE="bt709"
      RGB_RANGE="auto"
      ;;
    hdr_bt2020_ycc)
      HDR_MODE="on"
      COLOR_SPACE="bt2020_ycc"
      RGB_RANGE="auto"
      ;;
    *)
      bashio::log.warning "haos-kiosk: unknown video_profile_preset='$VIDEO_PROFILE_PRESET', using custom"
      VIDEO_PROFILE_PRESET="custom"
      ;;
  esac
}

apply_video_profile_preset

HA_URL_BASE="$HA_URL"
HA_URL_BASE="${HA_URL_BASE%/}"
if [ -n "$HA_DASHBOARD" ]; then
  HA_URL_BASE="$HA_URL_BASE/${HA_DASHBOARD#/}"
fi

# Origin (scheme://host[:port]) in the same form the browser reports via location.origin.
HA_URL_HOST="$(python3 - <<'PY'
import os
from urllib.parse import urlparse

value = os.environ.get("HA_URL", "")
parsed = urlparse(value)
if parsed.scheme and parsed.hostname:
  default_port = {"http": 80, "https": 443}.get(parsed.scheme)
  host = parsed.hostname
  if ":" in host:
    host = f"[{host}]"
  if parsed.port and parsed.port != default_port:
    host = f"{host}:{parsed.port}"
  print(f"{parsed.scheme}://{host}")
else:
  print(value.rstrip("/"))
PY
)"

export HA_URL_BASE
export HA_URL_HOST

if [ "$CLEAR_CHROMIUM_ON_START" = true ]; then
  bashio::log.info "haos-kiosk: clear_chromium_on_start enabled, wiping browser profile"
  rm -rf /data/chromium
fi

bashio::log.info "haos-kiosk: url=$HA_URL_BASE"
bashio::log.info "haos-kiosk: display=${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT}@${REFRESH_RATE}Hz  rotate=$ROTATE_DISPLAY  zoom=${ZOOM_LEVEL}%  sw_render=$SOFTWARE_RENDERING"
bashio::log.info "haos-kiosk: video: preset=$VIDEO_PROFILE_PRESET  hdr=$HDR_MODE  cs=$COLOR_SPACE  rgb=$RGB_RANGE"
bashio::log.info "haos-kiosk: browser: dark=$DARK_MODE  sidebar=$HA_SIDEBAR  header=$HIDE_HEADER  timeout=${SCREEN_TIMEOUT}s  audio=$AUDIO_SINK"
log_debug "haos-kiosk: ha_url=$HA_URL  dashboard=$HA_DASHBOARD  refresh=${BROWSER_REFRESH}s  mod_id=$BROWSER_MOD_ID  force_out=$FORCE_OUTPUT_ON  cursor=$HIDE_CURSOR"


python3 - <<'PY'
import os
import socket
import urllib.request
from urllib.parse import urlparse

ha_url = os.environ.get("HA_URL", "")
ha_url_base = os.environ.get("HA_URL_BASE", "")
debug = os.environ.get("DEBUG_LOGGING", "false").lower() == "true"

def _log(msg: str) -> None:
  if debug:
    print(f"haos-kiosk: {msg}")

def _warn(msg: str) -> None:
  print(f"haos-kiosk: WARNING connectivity: {msg}")

def _check_url(label: str, url: str) -> None:
  if not url:
    _log(f"connectivity {label}: empty")
    return
  try:
    req = urllib.request.Request(url, headers={"User-Agent": "haos-kiosk-check"})
    with urllib.request.urlopen(req, timeout=3) as resp:
      _log(f"connectivity {label}: {url} -> {resp.status}")
  except Exception as exc:
    _warn(f"{label}: {url} -> {exc}")

def _check_tcp(hostname: str | None, port: int | None) -> None:
  if not hostname or not port:
    _log("connectivity tcp: missing host or port")
    return
  try:
    sock = socket.create_connection((hostname, port), timeout=3)
    sock.close()
    _log(f"connectivity tcp: {hostname}:{port} -> ok")
  except Exception as exc:
    _warn(f"tcp: {hostname}:{port} -> {exc}")


parsed = urlparse(ha_url)
host = parsed.hostname
if host:
  try:
    resolved = socket.gethostbyname(host)
    _log(f"dns {host}: {resolved}")
  except Exception as exc:
    _warn(f"dns {host}: {exc}")

_check_tcp(parsed.hostname, parsed.port or {"http": 80, "https": 443}.get(parsed.scheme))

_check_url("ha_url", ha_url)
_check_url("ha_url_base", ha_url_base)
PY

log_debug "Starting DBus..."
mkdir -p /run/dbus
dbus-daemon --system --fork
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address || true)
if [ -n "$DBUS_SESSION_BUS_ADDRESS" ]; then
  export DBUS_SESSION_BUS_ADDRESS
fi

if [ "${DEBUG_LOGGING:-false}" = "true" ]; then
  bashio::log.info "DRM video cards:"
  find /dev/dri/ -maxdepth 1 -type c -name 'card[0-9]*' 2>/dev/null | sed 's/^/  /'
  bashio::log.info "DRM video card driver and connection status:"
fi
selected_card=""
selected_connector=""

scan_drm_connectors() {
  selected_card=""
  selected_connector=""
  for status_path in /sys/class/drm/card[0-9]*-*/status; do
    [ -e "$status_path" ] || continue
    status=$(cat "$status_path")
    card_port=$(basename "$(dirname "$status_path")")
    card=${card_port%%-*}
    driver=$(basename "$(readlink "/sys/class/drm/$card/device/driver")")
    if [ -z "$selected_card" ] && [ "$status" = "connected" ]; then
      selected_card="$card"
      selected_connector="$card_port"
      [ "${DEBUG_LOGGING:-false}" = "true" ] && printf "  *"
    else
      [ "${DEBUG_LOGGING:-false}" = "true" ] && printf "   "
    fi
    [ "${DEBUG_LOGGING:-false}" = "true" ] && printf "%-25s%-20s%s\n" "$card_port" "$driver" "$status"
  done
}

force_drm_connectors_on() {
  local force_path
  local connector
  local forced_any=false
  for force_path in /sys/class/drm/card[0-9]*-*/force; do
    [ -e "$force_path" ] || continue
    connector=$(basename "$(dirname "$force_path")")
    if [ -w "$force_path" ] && echo on > "$force_path" 2>/dev/null; then
      log_debug "haos-kiosk: forced DRM connector on: $connector"
      forced_any=true
    else
      bashio::log.warning "haos-kiosk: could not force DRM connector: $connector"
    fi
  done
  if [ "$forced_any" = false ]; then
    bashio::log.warning "haos-kiosk: no writable DRM force controls found"
  fi
}

scan_drm_connectors
[ -n "$selected_card" ] && bashio::log.info "haos-kiosk: GPU $selected_card  connector=$selected_connector"

if [ -z "$selected_card" ] && [ "$FORCE_OUTPUT_ON" = true ]; then
  bashio::log.warning "haos-kiosk: no connected display detected, trying force_output_on"
  force_drm_connectors_on
  udevadm settle --timeout=5 || true
  log_debug "haos-kiosk: rechecking DRM connector state after force"
  scan_drm_connectors
  [ -n "$selected_card" ] && bashio::log.info "haos-kiosk: GPU $selected_card  connector=$selected_connector"
fi

if [ -z "$selected_card" ]; then
  fallback_card_path="$(find /dev/dri/ -maxdepth 1 -type c -name 'card[0-9]*' 2>/dev/null | sort | head -n1 || true)"
  if [ -n "$fallback_card_path" ]; then
    selected_card="${fallback_card_path##*/}"
    bashio::log.warning "haos-kiosk: no connected output detected at startup; using $selected_card and waiting for output availability"
  fi
fi

if [ -z "$selected_card" ]; then
  bashio::log.error "ERROR: No connected video card detected. Exiting.."
  exit 1
fi

if [ -e "/dev/tty0" ]; then
  log_debug "haos-kiosk: remounting /dev rw to delete /dev/tty0..."
  if ! mount -o remount,rw /dev ; then
    bashio::log.error "Failed to remount /dev as read-write..."
    exit 1
  fi
  if ! rm -f /dev/tty0 ; then
    bashio::log.error "Failed to delete /dev/tty0..."
    exit 1
  fi
  TTY0_DELETED=1
  log_debug "haos-kiosk: deleted /dev/tty0..."
fi

log_debug "Starting udev..."
if ! udevd --daemon || ! udevadm trigger; then
  bashio::log.warning "WARNING: Failed to start udevd or trigger udev, input devices may not work"
fi
udevadm settle --timeout=10 || true

log_debug "Starting Xorg..."
rm -rf /tmp/.X*-lock
cp -a /etc/X11/xorg.conf.default /etc/X11/xorg.conf
sed -i "/Option[[:space:]]\+\"DRI\"[[:space:]]\+\"3\"/a\    Option          \"kmsdev\" \"/dev/dri/$selected_card\"" /etc/X11/xorg.conf
if [ "${DEBUG_LOGGING:-false}" = "true" ]; then
  echo "."
  printf '%*s xorg.conf %*s\n' 35 '' 34 '' | tr ' ' '#'
  cat /etc/X11/xorg.conf
  printf '%*s\n' 80 '' | tr ' ' '#'
  echo "."
fi

NOCURSOR=""
if [ "$HIDE_CURSOR" = true ]; then
  NOCURSOR="-nocursor"
fi
Xorg $NOCURSOR :0 -noreset -nolisten tcp </dev/null \
  > >(grep -v "Could not resolve keysym XF86\|Errors from xkbcomp are not fatal\|XKEYBOARD keymap compiler (xkbcomp) reports") 2>&1 &
XORG_PID=$!

XSTARTUP=20
for _ in $(seq 1 $XSTARTUP); do
  if xset q >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if [ -n "$TTY0_DELETED" ]; then
  if mknod -m 620 /dev/tty0 c 4 0; then
    log_debug "haos-kiosk: restored /dev/tty0..."
    TTY0_DELETED=""
  else
    bashio::log.error "Failed to restore /dev/tty0..."
  fi
fi

if ! xset q >/dev/null 2>&1; then
  bashio::log.error "Error: X server failed to start within $XSTARTUP seconds."
  exit 1
fi

sleep 2

log_debug "Starting Openbox..."
openbox &

if [ "$HIDE_CURSOR" = true ]; then
  unclutter-xfixes --start-hidden --hide-on-touch --fork --timeout 1 >/dev/null 2>&1 || true
fi

ACTIVE_OUTPUT=""

log_xrandr_output_capabilities() {
  local output="$1"
  local in_output=false
  local line
  local trimmed
  local next_supported=false

  log_debug "haos-kiosk: xrandr capability summary for output: $output"
  while IFS= read -r line; do
    if [[ "$line" =~ ^${output}[[:space:]]+(connected|disconnected) ]]; then
      in_output=true
      log_debug "haos-kiosk: xrandr[$output] ${line//$'\t'/ }"
      continue
    fi

    if [ "$in_output" = false ]; then
      continue
    fi

    if [[ "$line" =~ ^[^[:space:]] ]]; then
      break
    fi

    trimmed="${line#"${line%%[![:space:]]*}"}"

    if [ "$next_supported" = true ]; then
      if [[ "$trimmed" == supported:* ]]; then
        log_debug "haos-kiosk: xrandr[$output] $trimmed"
      fi
      next_supported=false
      continue
    fi

    case "$trimmed" in
      "max bpc:"*|"Colorspace:"*|"ColorSpace:"*|"Broadcast RGB:"*|"content type:"*|"link-status:"*)
        log_debug "haos-kiosk: xrandr[$output] $trimmed"
        next_supported=true
        ;;
    esac
  done < <(xrandr --verbose 2>/dev/null || true)

  return 0
}

LAST_CAPS_OUTPUT=""
LAST_FULL_COLOR_APPLY_OUTPUT=""

# xrandr output is captured first and then parsed, so an early `exit` in awk cannot SIGPIPE
# xrandr and turn the pipeline into a false failure under `set -o pipefail`.
xrandr_output_has_property() {
  local output="$1"
  local property="$2"
  local verbose
  verbose="$(xrandr --verbose 2>/dev/null)" || return 1
  awk -v output="$output" -v property="$property" '
    $1 == output && ($2 == "connected" || $2 == "disconnected") { in_output = 1; next }
    in_output && $0 ~ /^[^ \t]/ { exit }
    in_output {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (index(line, property ":") == 1) {
        found = 1
        exit
      }
    }
    END { exit(found ? 0 : 1) }
  ' <<<"$verbose"
}

try_set_xrandr_property() {
  local output="$1"
  local property="$2"
  shift 2
  local value
  for value in "$@"; do
    if xrandr --output "$output" --set "$property" "$value" >/dev/null 2>&1; then
      log_debug "haos-kiosk: set xrandr property $property=$value on $output"
      return 0
    fi
  done
  return 1
}

# Drivers expose the colorspace property under different names.
find_colorspace_property() {
  local candidate
  for candidate in "Colorspace" "ColorSpace" "color space"; do
    if xrandr_output_has_property "$ACTIVE_OUTPUT" "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

set_colorspace() {
  local prop
  prop="$(find_colorspace_property)" || return 1
  try_set_xrandr_property "$ACTIVE_OUTPUT" "$prop" "$@"
}

set_max_bpc() {
  xrandr_output_has_property "$ACTIVE_OUTPUT" "max bpc" || return 1
  try_set_xrandr_property "$ACTIVE_OUTPUT" "max bpc" "$@"
}

apply_hdr_mode() {
  local applied=false
  case "$HDR_MODE" in
    on)
      log_debug "haos-kiosk: applying HDR mode: on"
      set_max_bpc "10" "12" && applied=true
      set_colorspace "BT2020_RGB" "BT2020_YCC" && applied=true
      if [ "$applied" = false ]; then
        bashio::log.warning "haos-kiosk: HDR requested but no compatible xrandr property was accepted"
      fi
      ;;
    off)
      log_debug "haos-kiosk: applying HDR mode: off"
      set_max_bpc "8" || true
      set_colorspace "Default" "RGB" "RGB Full" || true
      ;;
  esac
  return 0
}

apply_rgb_range() {
  case "${RGB_RANGE,,}" in
    auto)
      try_set_xrandr_property "$ACTIVE_OUTPUT" "Broadcast RGB" "Automatic" || \
        bashio::log.warning "haos-kiosk: Broadcast RGB automatic mode could not be set"
      ;;
    full)
      try_set_xrandr_property "$ACTIVE_OUTPUT" "Broadcast RGB" "Full" || \
        bashio::log.warning "haos-kiosk: requested rgb_range='full' but Broadcast RGB could not be set"
      ;;
    limited)
      try_set_xrandr_property "$ACTIVE_OUTPUT" "Broadcast RGB" "Limited 16:235" "Limited" || \
        bashio::log.warning "haos-kiosk: requested rgb_range='limited' but Broadcast RGB could not be set"
      ;;
    *)
      bashio::log.warning "haos-kiosk: unknown rgb_range='$RGB_RANGE', using auto"
      try_set_xrandr_property "$ACTIVE_OUTPUT" "Broadcast RGB" "Automatic" || true
      ;;
  esac
  return 0
}

apply_color_space() {
  local target="${COLOR_SPACE,,}"
  local applied=false

  case "$target" in
    auto)
      # Broadcast RGB is also the only reliable knob on Intel, so honor an explicit range here too.
      [ "${RGB_RANGE,,}" != "auto" ] && apply_rgb_range
      return 0
      ;;
    rgb)
      set_colorspace "RGB" "RGB Full" "opRGB" "Default" && applied=true
      apply_rgb_range
      ;;
    yuv)
      set_colorspace "BT709_YCC" "BT2020_YCC" "SMPTE_170M_YCC" "XVYCC_709" "XVYCC_601" && applied=true
      ;;
    # Explicit YCC profiles
    bt709)       set_colorspace "BT709_YCC"      && applied=true ;;
    bt2020_ycc)  set_colorspace "BT2020_YCC"     && applied=true ;;
    bt2020_cycc) set_colorspace "BT2020_CYCC"    && applied=true ;;
    smpte170m)   set_colorspace "SMPTE_170M_YCC" && applied=true ;;
    xvycc_709)   set_colorspace "XVYCC_709"      && applied=true ;;
    xvycc_601)   set_colorspace "XVYCC_601"      && applied=true ;;
    sycc_601)    set_colorspace "SYCC_601"       && applied=true ;;
    opycc_601)   set_colorspace "opYCC_601"      && applied=true ;;
    # Explicit RGB profiles — also apply Broadcast RGB range
    bt2020_rgb)     set_colorspace "BT2020_RGB"         && applied=true; apply_rgb_range ;;
    oprgb)          set_colorspace "opRGB"              && applied=true; apply_rgb_range ;;
    dci_p3_d65)     set_colorspace "DCI-P3_RGB_D65"     && applied=true; apply_rgb_range ;;
    dci_p3_theater) set_colorspace "DCI-P3_RGB_Theater" && applied=true; apply_rgb_range ;;
    default)        set_colorspace "Default"            && applied=true; apply_rgb_range ;;
    *)
      bashio::log.warning "haos-kiosk: unknown color_space='$COLOR_SPACE', skipping"
      return 0
      ;;
  esac

  if [ "$applied" = false ] && [ "$target" != "rgb" ]; then
    bashio::log.warning "haos-kiosk: no compatible xrandr color space property found for '$COLOR_SPACE'"
  fi

  return 0
}

read_xrandr_property_value() {
  local output="$1"
  local property="$2"
  local verbose
  verbose="$(xrandr --verbose 2>/dev/null)" || return 1
  awk -v output="$output" -v property="$property" '
    $1 == output && ($2 == "connected" || $2 == "disconnected") { in_output = 1; next }
    in_output && $0 ~ /^[^ \t]/ { exit }
    in_output {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (index(line, property ":") == 1) {
        line = substr(line, length(property) + 2)
        sub(/^[ \t]+/, "", line)
        split(line, parts, /[ \t]+/)
        print parts[1]
        exit
      }
    }
  ' <<<"$verbose"
}

reset_output_to_safe_baseline() {
  set_max_bpc "8" || true
  set_colorspace "Default" || true
  try_set_xrandr_property "$ACTIVE_OUTPUT" "Broadcast RGB" "Automatic" || true
}

recover_bad_link_status() {
  local status
  status="$(read_xrandr_property_value "$ACTIVE_OUTPUT" "link-status" || true)"
  if [ "$status" != "Bad" ]; then
    return 0
  fi

  bashio::log.warning "haos-kiosk: link-status became Bad, attempting safe HDMI recovery"
  reset_output_to_safe_baseline
  xrandr --output "$ACTIVE_OUTPUT" --auto || true
}

color_overrides_requested() {
  [ "$HDR_MODE" != "auto" ] || [ "${COLOR_SPACE,,}" != "auto" ] || [ "${RGB_RANGE,,}" != "auto" ]
}

pick_active_output() {
  local state
  state="$(xrandr 2>/dev/null || true)"
  local output
  output="$(awk '$2 == "connected" {print $1; exit}' <<<"$state")"
  if [ -z "$output" ] && [ "$FORCE_OUTPUT_ON" = true ]; then
    output="$(awk '$2 == "disconnected" {print $1; exit}' <<<"$state")"
  fi
  echo "$output"
}

configure_display_output() {
  local reason="$1"
  local output
  local apply_full_color_stack=true
  output="$(pick_active_output)"
  if [ -z "$output" ]; then
    return 1
  fi

  ACTIVE_OUTPUT="$output"
  bashio::log.info "haos-kiosk: initializing output '$ACTIVE_OUTPUT' ($reason)"

  if [ "$reason" = "reconnect" ] && [ "$ACTIVE_OUTPUT" = "$LAST_FULL_COLOR_APPLY_OUTPUT" ]; then
    apply_full_color_stack=false
    log_debug "haos-kiosk: reconnect on same output, keeping previous color/HDR state"
  elif ! color_overrides_requested; then
    apply_full_color_stack=false
    log_debug "haos-kiosk: passthrough color mode, leaving HDR/color/RGB range to the driver"
  fi

  if [ "$FORCE_OUTPUT_ON" = true ]; then
    xrandr --output "$ACTIVE_OUTPUT" --auto --primary || true
  fi

  if [ "$apply_full_color_stack" = true ]; then
    # Reset first so stale prior modes (e.g. BT2020) do not survive restarts.
    reset_output_to_safe_baseline
  fi

  if [ "$LAST_CAPS_OUTPUT" != "$ACTIVE_OUTPUT" ]; then
    log_xrandr_output_capabilities "$ACTIVE_OUTPUT"
    LAST_CAPS_OUTPUT="$ACTIVE_OUTPUT"
  fi

  log_debug "haos-kiosk: setting display rotation $ROTATE_DISPLAY"
  case "$ROTATE_DISPLAY" in
    left) xrandr --output "$ACTIVE_OUTPUT" --rotate left || true ;;
    right) xrandr --output "$ACTIVE_OUTPUT" --rotate right || true ;;
    inverted) xrandr --output "$ACTIVE_OUTPUT" --rotate inverted || true ;;
    *) xrandr --output "$ACTIVE_OUTPUT" --rotate normal || true ;;
  esac

  if [ "$RESOLUTION_WIDTH" -gt 0 ] && [ "$RESOLUTION_HEIGHT" -gt 0 ]; then
    log_debug "haos-kiosk: setting resolution ${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT}"
    if awk -v r="$REFRESH_RATE" 'BEGIN { exit !(r+0 > 0) }'; then
      log_debug "haos-kiosk: setting refresh rate ${REFRESH_RATE}Hz"
      xrandr --output "$ACTIVE_OUTPUT" --mode "${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT}" --rate "$REFRESH_RATE" || true
    else
      xrandr --output "$ACTIVE_OUTPUT" --mode "${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT}" || true
    fi
  fi

  if [ "$apply_full_color_stack" = true ]; then
    apply_hdr_mode
    apply_color_space
    LAST_FULL_COLOR_APPLY_OUTPUT="$ACTIVE_OUTPUT"
  fi

  recover_bad_link_status
  return 0
}

if ! configure_display_output "startup"; then
  bashio::log.warning "haos-kiosk: startup completed without active output; waiting for reconnect"
fi

if [ "$SCREEN_TIMEOUT" -gt 0 ]; then
  log_debug "haos-kiosk: screen timeout ${SCREEN_TIMEOUT}s"
  xset s "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT"
  xset dpms "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT"
else
  xset s off
  xset -dpms
fi

if [ "$AUDIO_SINK" != "none" ]; then
  log_debug "haos-kiosk: audio sink $AUDIO_SINK"
  if [ "$AUDIO_SINK" = "hdmi" ]; then
    pactl set-default-sink "$(pactl list short sinks | awk '/hdmi/{print $2; exit}')" || true
  elif [ "$AUDIO_SINK" = "usb" ]; then
    pactl set-default-sink "$(pactl list short sinks | awk '/usb/{print $2; exit}')" || true
  fi
fi


launch_chromium() {
  mkdir -p /data/chromium
  # A previous Chromium instance (crash, container restart) can leave stale profile locks behind,
  # which makes the new instance refuse to start ("profile in use").
  rm -f /data/chromium/SingletonLock /data/chromium/SingletonSocket /data/chromium/SingletonCookie

  local extra_flags=()
  if [ "$SOFTWARE_RENDERING" = true ]; then
    extra_flags+=(--disable-gpu --disable-gpu-compositing --disable-accelerated-video-decode)
  fi
  if [ "$DARK_MODE" = true ]; then
    extra_flags+=(--force-dark-mode)
  fi

  local scale_factor
  scale_factor="$(awk -v z="$ZOOM_LEVEL" 'BEGIN { printf "%.2f", z / 100 }')"

  chromium \
    --no-sandbox \
    --disable-dev-shm-usage \
    --no-first-run \
    --no-default-browser-check \
    --noerrdialogs \
    --disable-features=Translate \
    --password-store=basic \
    --disable-extensions-except=/data/haos-extension \
    --load-extension=/data/haos-extension \
    --autoplay-policy=no-user-gesture-required \
    --kiosk \
    --user-data-dir=/data/chromium \
    "${extra_flags[@]}" \
    --force-device-scale-factor="$scale_factor" \
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
profile = data.setdefault("profile", {})
profile["password_manager_enabled"] = False
# Pretend the last session ended cleanly so no "Restore pages?" bubble appears after power loss.
profile["exit_type"] = "Normal"
profile["exited_cleanly"] = True
data.setdefault("translate", {})["enabled"] = False

with open(prefs_path, "w", encoding="utf-8") as f:
  json.dump(data, f)
PY
}

init_extension() {
  mkdir -p /data/haos-extension
  rm -rf /data/haos-extension/*
  cp -a /haos-extension/. /data/haos-extension/
  python3 - <<'PY'
import json
import os
from urllib.parse import urlparse

def _as_bool(value: str) -> bool:
  return value.strip().lower() == "true"

def _as_int(value: str) -> int:
  try:
    return max(int(float(value)), 0)
  except Exception:
    return 0

ha_url_host = os.getenv("HA_URL_HOST", "").strip()

config = {
  "haUrlHost": ha_url_host,
  "haUrlBase": os.getenv("HA_URL_BASE", "").strip(),
  "haUrlHosts": [ha_url_host] if urlparse(ha_url_host).hostname else [],
  "username": os.getenv("HA_USERNAME", ""),
  "password": os.getenv("HA_PASSWORD", ""),
  "darkMode": _as_bool(os.getenv("DARK_MODE", "true")),
  "sidebarMode": os.getenv("HA_SIDEBAR", "full").strip().lower(),
  "browserModId": os.getenv("BROWSER_MOD_ID", "haos_kiosk").strip(),
  "hideHeader": _as_bool(os.getenv("HIDE_HEADER", "false")),
  "theme": os.getenv("HA_THEME", ""),
  "loginDelayMs": _as_int(os.getenv("LOGIN_DELAY", "2")) * 1000,
  "refreshIntervalSec": _as_int(os.getenv("BROWSER_REFRESH", "0")),
}

with open("/data/haos-extension/config.js", "w", encoding="utf-8") as handle:
  handle.write("window.__HAOS_KIOSK_CONFIG = ")
  handle.write(json.dumps(config))
  handle.write(";\n")

# Restrict the extension (and therefore the credentials) to the Home Assistant host.
# Match patterns cannot contain ports, so content.js additionally checks the exact origin.
parsed = urlparse(ha_url_host)
if parsed.scheme in ("http", "https") and parsed.hostname:
  host = parsed.hostname
  if ":" in host:
    host = f"[{host}]"
  pattern = f"{parsed.scheme}://{host}/*"
  manifest_path = "/data/haos-extension/manifest.json"
  with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)
  for script in manifest.get("content_scripts", []):
    script["matches"] = [pattern]
  manifest["host_permissions"] = [pattern]
  with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
PY
}

# Chromium shows its own network error page if HA is not reachable yet; the extension cannot run
# there, so the kiosk would stay stuck. Wait (bounded) until HA answers before launching.
wait_for_home_assistant() {
  local timeout="${1:-180}"
  if python3 - "$timeout" <<'PY'
import os
import sys
import time
import urllib.error
import urllib.request

url = os.environ.get("HA_URL_BASE") or os.environ.get("HA_URL", "")
deadline = time.monotonic() + int(sys.argv[1])
while time.monotonic() < deadline:
  try:
    req = urllib.request.Request(url, headers={"User-Agent": "haos-kiosk-check"})
    with urllib.request.urlopen(req, timeout=5):
      sys.exit(0)
  except urllib.error.HTTPError:
    sys.exit(0)
  except Exception:
    time.sleep(3)
sys.exit(1)
PY
  then
    log_debug "haos-kiosk: Home Assistant is reachable"
  else
    bashio::log.warning "haos-kiosk: Home Assistant not reachable after ${timeout}s, launching Chromium anyway"
  fi
}

chromium_running() {
  pgrep -f -- "--user-data-dir=/data/chromium" >/dev/null 2>&1
}

configure_chromium_prefs
init_extension
wait_for_home_assistant 180
bashio::log.info "haos-kiosk: launching Chromium"
launch_chromium


log_debug "haos-kiosk: starting Chromium watchdog"
(
  sleep 5
  while true; do
    if ! chromium_running; then
      bashio::log.warning "Chromium not running, restarting"
      configure_chromium_prefs
      wait_for_home_assistant 60
      launch_chromium
    fi
    sleep 10
  done
) &

log_debug "haos-kiosk: starting output reconnect monitor"
(
  last_seen_output="$ACTIVE_OUTPUT"
  while true; do
    current_output="$(pick_active_output)"

    if [ -z "$current_output" ]; then
      if [ -n "$last_seen_output" ]; then
        bashio::log.warning "haos-kiosk: output became unavailable; waiting for it to return"
        last_seen_output=""
      fi
      sleep 5
      continue
    fi

    if [ "$current_output" != "$last_seen_output" ]; then
      bashio::log.info "haos-kiosk: output available: $current_output (reinitializing)"
      if configure_display_output "reconnect"; then
        last_seen_output="$current_output"
      fi
    else
      ACTIVE_OUTPUT="$current_output"
      recover_bad_link_status || true
    fi

    sleep 5
  done
) &

# Exit when Xorg dies so the Supervisor (add-on watchdog) can restart the whole stack.
while kill -0 "$XORG_PID" 2>/dev/null; do
  sleep 10
done
bashio::log.error "haos-kiosk: Xorg exited unexpectedly, stopping add-on"
exit 1
