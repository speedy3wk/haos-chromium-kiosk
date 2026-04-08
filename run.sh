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
load_config_var hide_sidebar false
load_config_var hide_header false
load_config_var resolution_width 0
load_config_var resolution_height 0
load_config_var refresh_rate 0
load_config_var video_profile_preset "custom"
load_config_var hdr_mode "auto"
load_config_var color_space "auto"
load_config_var color_profile "auto"
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

apply_video_profile_preset() {
  case "$VIDEO_PROFILE_PRESET" in
    custom|"")
      return 0
      ;;
    sdr_rgb_limited)
      HDR_MODE="off"
      COLOR_SPACE="rgb"
      COLOR_PROFILE="default"
      RGB_RANGE="limited"
      ;;
    sdr_bt709_ycc)
      HDR_MODE="off"
      COLOR_SPACE="yuv422"
      COLOR_PROFILE="bt709"
      RGB_RANGE="auto"
      ;;
    hdr_bt2020_ycc)
      HDR_MODE="on"
      COLOR_SPACE="yuv422"
      COLOR_PROFILE="bt2020_ycc"
      RGB_RANGE="auto"
      ;;
    match_shield_bt2020)
      HDR_MODE="on"
      COLOR_SPACE="yuv420"
      COLOR_PROFILE="bt2020_ycc"
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
bashio::log.info "haos-kiosk: video_profile_preset=$VIDEO_PROFILE_PRESET"
bashio::log.info "haos-kiosk: hdr_mode=$HDR_MODE color_space=$COLOR_SPACE color_profile=$COLOR_PROFILE rgb_range=$RGB_RANGE force_output_on=$FORCE_OUTPUT_ON"
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
      printf "  *"
    else
      printf "   "
    fi
    printf "%-25s%-20s%s\n" "$card_port" "$driver" "$status"
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
      bashio::log.info "haos-kiosk: forced DRM connector on: $connector"
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

if [ -z "$selected_card" ] && [ "$FORCE_OUTPUT_ON" = true ]; then
  bashio::log.warning "haos-kiosk: no connected display detected, trying force_output_on"
  force_drm_connectors_on
  udevadm settle --timeout=5 || true
  bashio::log.info "haos-kiosk: rechecking DRM connector state after force"
  scan_drm_connectors
fi

if [ -z "$selected_card" ] && [ "$FORCE_OUTPUT_ON" = true ]; then
  fallback_card_path="$(find /dev/dri/ -maxdepth 1 -type c -name 'card[0-9]*' 2>/dev/null | sort | head -n1 || true)"
  if [ -n "$fallback_card_path" ]; then
    selected_card="${fallback_card_path##*/}"
    bashio::log.warning "haos-kiosk: using fallback video card $selected_card without connected status"
  fi
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

bashio::log.info "Starting Openbox..."
openbox &

if [ "$HIDE_CURSOR" = true ]; then
  unclutter-xfixes --start-hidden --hide-on-touch --fork --timeout 1 >/dev/null 2>&1 || true
fi

ACTIVE_OUTPUT="$(xrandr | awk '/ connected/{print $1; exit}')"
if [ -z "$ACTIVE_OUTPUT" ] && [ "$FORCE_OUTPUT_ON" = true ]; then
  ACTIVE_OUTPUT="$(xrandr | awk '/ disconnected/{print $1; exit}')"
fi

if [ -z "$ACTIVE_OUTPUT" ]; then
  bashio::log.warning "haos-kiosk: no active xrandr output detected yet; waiting for HDMI/AVR availability"
fi

log_xrandr_output_capabilities() {
  local output="$1"
  local in_output=false
  local line
  local trimmed
  local next_supported=false

  bashio::log.info "haos-kiosk: xrandr capability summary for output: $output"
  while IFS= read -r line; do
    if [[ "$line" =~ ^${output}[[:space:]]+(connected|disconnected) ]]; then
      in_output=true
      bashio::log.info "haos-kiosk: xrandr[$output] ${line//$'\t'/ }"
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
        bashio::log.info "haos-kiosk: xrandr[$output] $trimmed"
      fi
      next_supported=false
      continue
    fi

    case "$trimmed" in
      "max bpc:"*|"Colorspace:"*|"ColorSpace:"*|"Broadcast RGB:"*|"content type:"*|"link-status:"*)
        bashio::log.info "haos-kiosk: xrandr[$output] $trimmed"
        next_supported=true
        ;;
    esac
  done < <(xrandr --verbose 2>/dev/null || true)

  return 0
}

LAST_CAPS_OUTPUT=""

xrandr_output_has_property() {
  local output="$1"
  local property="$2"
  xrandr --verbose | awk -v output="$output" -v property="$property" '
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
  '
}

try_set_xrandr_property() {
  local output="$1"
  local property="$2"
  shift 2
  local value
  for value in "$@"; do
    if xrandr --output "$output" --set "$property" "$value" >/dev/null 2>&1; then
      bashio::log.info "haos-kiosk: set xrandr property $property=$value on $output"
      return 0
    fi
  done
  return 1
}

apply_hdr_mode() {
  local applied=false
  case "$HDR_MODE" in
    auto)
      return 0
      ;;
    on)
      bashio::log.info "haos-kiosk: applying HDR mode: on"
      if xrandr_output_has_property "$ACTIVE_OUTPUT" "max bpc"; then
        if try_set_xrandr_property "$ACTIVE_OUTPUT" "max bpc" "10" "12"; then
          applied=true
        fi
      fi
      if xrandr_output_has_property "$ACTIVE_OUTPUT" "Colorspace"; then
        if try_set_xrandr_property "$ACTIVE_OUTPUT" "Colorspace" "BT2020_RGB" "BT2020_YCC"; then
          applied=true
        fi
      elif xrandr_output_has_property "$ACTIVE_OUTPUT" "ColorSpace"; then
        if try_set_xrandr_property "$ACTIVE_OUTPUT" "ColorSpace" "BT2020_RGB" "BT2020_YCC"; then
          applied=true
        fi
      elif xrandr_output_has_property "$ACTIVE_OUTPUT" "color space"; then
        if try_set_xrandr_property "$ACTIVE_OUTPUT" "color space" "BT2020_RGB" "BT2020_YCC"; then
          applied=true
        fi
      fi
      if [ "$applied" = false ]; then
        bashio::log.warning "haos-kiosk: HDR requested but no compatible xrandr property was accepted"
      fi
      ;;
    off)
      bashio::log.info "haos-kiosk: applying HDR mode: off"
      if xrandr_output_has_property "$ACTIVE_OUTPUT" "max bpc"; then
        try_set_xrandr_property "$ACTIVE_OUTPUT" "max bpc" "8" || true
      fi
      if xrandr_output_has_property "$ACTIVE_OUTPUT" "Colorspace"; then
        try_set_xrandr_property "$ACTIVE_OUTPUT" "Colorspace" "Default" "RGB" "RGB Full" || true
      elif xrandr_output_has_property "$ACTIVE_OUTPUT" "ColorSpace"; then
        try_set_xrandr_property "$ACTIVE_OUTPUT" "ColorSpace" "Default" "RGB" "RGB Full" || true
      elif xrandr_output_has_property "$ACTIVE_OUTPUT" "color space"; then
        try_set_xrandr_property "$ACTIVE_OUTPUT" "color space" "Default" "RGB" "RGB Full" || true
      fi
      ;;
  esac
}

apply_color_space() {
  local target="$1"
  local property=""
  local applied=false
  local color_profile_key="${COLOR_PROFILE,,}"
  local color_profile_value=""
  local rgb_range_value="${RGB_RANGE,,}"
  local explicit_profile_is_ycc=false

  apply_rgb_range_for_rgb_mode() {
    case "$rgb_range_value" in
      auto)
        if xrandr_output_has_property "$ACTIVE_OUTPUT" "Broadcast RGB"; then
          if ! try_set_xrandr_property "$ACTIVE_OUTPUT" "Broadcast RGB" "Automatic"; then
            bashio::log.warning "haos-kiosk: Broadcast RGB exists but automatic mode could not be set"
          fi
        fi
        ;;
      full)
        if xrandr_output_has_property "$ACTIVE_OUTPUT" "Broadcast RGB"; then
          if ! try_set_xrandr_property "$ACTIVE_OUTPUT" "Broadcast RGB" "Full"; then
            bashio::log.warning "haos-kiosk: requested rgb_range='full' but Broadcast RGB could not be set"
          fi
        else
          bashio::log.warning "haos-kiosk: requested rgb_range='full' but Broadcast RGB property is unavailable"
        fi
        ;;
      limited)
        if xrandr_output_has_property "$ACTIVE_OUTPUT" "Broadcast RGB"; then
          if ! try_set_xrandr_property "$ACTIVE_OUTPUT" "Broadcast RGB" "Limited 16:235" "Limited"; then
            bashio::log.warning "haos-kiosk: requested rgb_range='limited' but Broadcast RGB could not be set"
          fi
        else
          bashio::log.warning "haos-kiosk: requested rgb_range='limited' but Broadcast RGB property is unavailable"
        fi
        ;;
      *)
        bashio::log.warning "haos-kiosk: unknown rgb_range='$RGB_RANGE', using auto"
        if xrandr_output_has_property "$ACTIVE_OUTPUT" "Broadcast RGB"; then
          try_set_xrandr_property "$ACTIVE_OUTPUT" "Broadcast RGB" "Automatic" || true
        fi
        ;;
    esac
  }

  try_set_colorspace_value() {
    local value
    if [ -n "$property" ]; then
      try_set_xrandr_property "$ACTIVE_OUTPUT" "$property" "$@"
      return $?
    fi

    for property_candidate in "Colorspace" "ColorSpace" "color space"; do
      if try_set_xrandr_property "$ACTIVE_OUTPUT" "$property_candidate" "$@"; then
        property="$property_candidate"
        return 0
      fi
    done
    return 1
  }

  resolve_color_profile_value() {
    case "$color_profile_key" in
      auto|"") color_profile_value="" ;;
      default) color_profile_value="Default" ;;
      bt709) color_profile_value="BT709_YCC" ;;
      bt2020_ycc) color_profile_value="BT2020_YCC" ;;
      bt2020_rgb) color_profile_value="BT2020_RGB" ;;
      bt2020_cycc) color_profile_value="BT2020_CYCC" ;;
      smpte170m) color_profile_value="SMPTE_170M_YCC" ;;
      xvycc_709) color_profile_value="XVYCC_709" ;;
      xvycc_601) color_profile_value="XVYCC_601" ;;
      sycc_601) color_profile_value="SYCC_601" ;;
      opycc_601) color_profile_value="opYCC_601" ;;
      oprgb) color_profile_value="opRGB" ;;
      dci_p3_d65) color_profile_value="DCI-P3_RGB_D65" ;;
      dci_p3_theater) color_profile_value="DCI-P3_RGB_Theater" ;;
      *)
        bashio::log.warning "haos-kiosk: unknown color_profile='$COLOR_PROFILE', using auto"
        color_profile_value=""
        ;;
    esac
  }

  detect_explicit_profile_type() {
    case "$color_profile_key" in
      bt709|bt2020_ycc|bt2020_cycc|smpte170m|xvycc_709|xvycc_601|sycc_601|opycc_601)
        explicit_profile_is_ycc=true
        ;;
      *)
        explicit_profile_is_ycc=false
        ;;
    esac
  }

  apply_explicit_color_profile() {
    if [ -z "$color_profile_value" ]; then
      return 1
    fi
    if try_set_colorspace_value "$color_profile_value"; then
      bashio::log.info "haos-kiosk: set explicit color_profile='$COLOR_PROFILE' ($color_profile_value)"
      return 0
    fi
    bashio::log.warning "haos-kiosk: requested color_profile='$COLOR_PROFILE' is not supported by available color space properties on $ACTIVE_OUTPUT"
    return 1
  }

  case "$COLOR_SPACE" in
    auto)
      target="auto"
      ;;
    rgb)
      target="rgb"
      ;;
    yuv444|yuv422|yuv420)
      target="$COLOR_SPACE"
      ;;
    *)
      bashio::log.warning "haos-kiosk: unknown color_space='$COLOR_SPACE', skipping"
      return 0
      ;;
  esac

  for candidate in "Colorspace" "ColorSpace" "color space"; do
    if xrandr_output_has_property "$ACTIVE_OUTPUT" "$candidate"; then
      property="$candidate"
      break
    fi
  done

  resolve_color_profile_value
  detect_explicit_profile_type

  if apply_explicit_color_profile; then
    if [ "$target" = "rgb" ]; then
      if [ "$explicit_profile_is_ycc" = true ]; then
        if [ "$rgb_range_value" != "auto" ]; then
          bashio::log.info "haos-kiosk: rgb_range is ignored because color_profile='$COLOR_PROFILE' is YCC-based"
        fi
      else
        apply_rgb_range_for_rgb_mode
      fi
    elif [ "$rgb_range_value" != "auto" ]; then
      bashio::log.info "haos-kiosk: rgb_range is ignored unless color_space=rgb"
    fi
    return 0
  fi

  if [ "$target" = "auto" ]; then
    if [ "$rgb_range_value" != "auto" ]; then
      bashio::log.info "haos-kiosk: rgb_range is ignored when color_space=auto"
    fi
    return 0
  fi

  if [ -n "$property" ]; then
    case "$target" in
      rgb)
        if try_set_colorspace_value "RGB" "RGB Full" "opRGB" "Default"; then
          applied=true
        fi
        apply_rgb_range_for_rgb_mode
        ;;
      yuv444)
        if try_set_colorspace_value "BT709_YCC" "BT2020_YCC" "SMPTE_170M_YCC" "XVYCC_709" "XVYCC_601"; then
          applied=true
        fi
        ;;
      yuv422)
        if try_set_colorspace_value "BT709_YCC" "BT2020_YCC" "SMPTE_170M_YCC" "XVYCC_709" "XVYCC_601"; then
          applied=true
          bashio::log.info "haos-kiosk: color_space=yuv422 mapped to driver colorspace profile (subsampling is sink/GPU managed)"
        fi
        ;;
      yuv420)
        if try_set_colorspace_value "BT709_YCC" "BT2020_YCC" "SMPTE_170M_YCC" "XVYCC_709" "XVYCC_601"; then
          applied=true
          bashio::log.info "haos-kiosk: color_space=yuv420 mapped to driver colorspace profile (subsampling is sink/GPU managed)"
        fi
        ;;
    esac

    if [ "$applied" = false ]; then
      bashio::log.warning "haos-kiosk: requested color_space='$COLOR_SPACE' is not supported by $property on $ACTIVE_OUTPUT"
    fi
    return 0
  elif [ "$target" = "rgb" ]; then
    apply_rgb_range_for_rgb_mode
  else
    bashio::log.warning "haos-kiosk: no compatible xrandr color space property found for '$COLOR_SPACE'"
  fi
}

read_xrandr_property_value() {
  local output="$1"
  local property="$2"
  xrandr --verbose | awk -v output="$output" -v property="$property" '
    $1 == output && ($2 == "connected" || $2 == "disconnected") { in_output = 1; next }
    in_output && $0 ~ /^[^ \t]/ { exit }
    in_output {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (index(line, property ":") == 1) {
        sub("^" property ":[ \\t]*", "", line)
        split(line, parts, /[ \\t]+/)
        print parts[1]
        exit
      }
    }
  '
}

recover_bad_link_status() {
  local status
  status="$(read_xrandr_property_value "$ACTIVE_OUTPUT" "link-status" || true)"
  if [ "$status" != "Bad" ]; then
    return 0
  fi

  bashio::log.warning "haos-kiosk: link-status became Bad, attempting safe HDMI recovery"
  if xrandr_output_has_property "$ACTIVE_OUTPUT" "max bpc"; then
    try_set_xrandr_property "$ACTIVE_OUTPUT" "max bpc" "8" || true
  fi
  if xrandr_output_has_property "$ACTIVE_OUTPUT" "Colorspace"; then
    try_set_xrandr_property "$ACTIVE_OUTPUT" "Colorspace" "Default" || true
  elif xrandr_output_has_property "$ACTIVE_OUTPUT" "ColorSpace"; then
    try_set_xrandr_property "$ACTIVE_OUTPUT" "ColorSpace" "Default" || true
  elif xrandr_output_has_property "$ACTIVE_OUTPUT" "color space"; then
    try_set_xrandr_property "$ACTIVE_OUTPUT" "color space" "Default" || true
  fi
  if xrandr_output_has_property "$ACTIVE_OUTPUT" "Broadcast RGB"; then
    try_set_xrandr_property "$ACTIVE_OUTPUT" "Broadcast RGB" "Automatic" || true
  fi
  xrandr --output "$ACTIVE_OUTPUT" --auto || true
}

pick_active_output() {
  local output
  output="$(xrandr | awk '/ connected/{print $1; exit}')"
  if [ -z "$output" ] && [ "$FORCE_OUTPUT_ON" = true ]; then
    output="$(xrandr | awk '/ disconnected/{print $1; exit}')"
  fi
  echo "$output"
}

configure_display_output() {
  local reason="$1"
  local output
  output="$(pick_active_output)"
  if [ -z "$output" ]; then
    return 1
  fi

  ACTIVE_OUTPUT="$output"
  bashio::log.info "haos-kiosk: initializing output '$ACTIVE_OUTPUT' ($reason)"

  if [ "$FORCE_OUTPUT_ON" = true ]; then
    xrandr --output "$ACTIVE_OUTPUT" --auto --primary || true
  fi

  if [ "$LAST_CAPS_OUTPUT" != "$ACTIVE_OUTPUT" ]; then
    log_xrandr_output_capabilities "$ACTIVE_OUTPUT"
    LAST_CAPS_OUTPUT="$ACTIVE_OUTPUT"
  fi

  bashio::log.info "Setting display rotation: $ROTATE_DISPLAY"
  case "$ROTATE_DISPLAY" in
    left) xrandr --output "$ACTIVE_OUTPUT" --rotate left || true ;;
    right) xrandr --output "$ACTIVE_OUTPUT" --rotate right || true ;;
    inverted) xrandr --output "$ACTIVE_OUTPUT" --rotate inverted || true ;;
    *) xrandr --output "$ACTIVE_OUTPUT" --rotate normal || true ;;
  esac

  if [ "$RESOLUTION_WIDTH" -gt 0 ] && [ "$RESOLUTION_HEIGHT" -gt 0 ]; then
    bashio::log.info "Setting resolution: ${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT}"
    if [ "$REFRESH_RATE" -gt 0 ]; then
      bashio::log.info "Setting refresh rate: ${REFRESH_RATE}"
      xrandr --output "$ACTIVE_OUTPUT" --mode "${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT}" --rate "$REFRESH_RATE" || true
    else
      xrandr --output "$ACTIVE_OUTPUT" --mode "${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT}" || true
    fi
  fi

  apply_hdr_mode
  apply_color_space "$COLOR_SPACE"
  recover_bad_link_status
  return 0
}

if ! configure_display_output "startup"; then
  bashio::log.warning "haos-kiosk: startup completed without active output; waiting for reconnect"
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

bashio::log.info "Starting output reconnect monitor"
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

while true; do
  sleep 60
done
