#!/usr/bin/env bash
set -euo pipefail

script="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/run.sh}"
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
DRM_ROOT="$fixture_dir/drm"
mkdir -p "$DRM_ROOT"
command_log="$fixture_dir/commands"
error_log="$fixture_dir/errors"

for function in scan_drm_connectors force_drm_connectors_on pick_active_output activate_selected_output configure_display_output; do
  source <(sed -n "/^$function() {$/,/^}$/p" "$script" |
    sed 's|/sys/class/drm|${DRM_ROOT}|g')
  declare -F "$function" >/dev/null
done

bashio::log.info() { printf '%s\n' "$*" >&2; }
bashio::log.warning() { printf '%s\n' "$*" >&2; }
bashio::log.error() { printf '%s\n' "$*" >&2; }
log_debug() { :; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

add_connector() {
  local connector="$1" status="$2" id="$3" card="${1%%-*}"
  mkdir -p "$DRM_ROOT/$connector" "$DRM_ROOT/$card/device"
  printf '%s\n' "$status" > "$DRM_ROOT/$connector/status"
  printf '%s\n' "$id" > "$DRM_ROOT/$connector/connector_id"
  : > "$DRM_ROOT/$connector/force"
  if [ ! -L "$DRM_ROOT/$card/device/driver" ]; then
    ln -s /drivers/test "$DRM_ROOT/$card/device/driver"
  fi
}

DEBUG_LOGGING=false
FORCE_OUTPUT_ON=false
add_connector card0-DP-1 connected 10
add_connector card0-HDMI-A-1 disconnected 11
add_connector card1-HDMI-A-1 connected 21

for DISPLAY_OUTPUT in "" auto 1 2 card0-HDMI-A-1 DP-1 card1-HDMI-A-1; do
  scan_drm_connectors
  case "$DISPLAY_OUTPUT" in
    ""|auto|1|DP-1) expected=card0-DP-1 ;;
    2|card1-HDMI-A-1) expected=card1-HDMI-A-1 ;;
    *) expected=card0-HDMI-A-1 ;;
  esac
  [ "$selected_connector" = "$expected" ] || fail "connector selection for '$DISPLAY_OUTPUT'"
  [ "$selected_card" = "${expected%%-*}" ] || fail "GPU selection for '$DISPLAY_OUTPUT'"
  pass "DRM selection '$DISPLAY_OUTPUT' -> $expected"
done

for DISPLAY_OUTPUT in 0 3 -1 999999999999999999999 HDMI-A-1 missing 'DP-1;echo unsafe'; do
  if (scan_drm_connectors) 2>"$error_log"; then
    fail "accepted invalid/ambiguous selection '$DISPLAY_OUTPUT'"
  fi
  grep -q "matched .* connectors" "$error_log"
  pass "rejecting '$DISPLAY_OUTPUT' with diagnostic"
done

DISPLAY_OUTPUT=card0-HDMI-A-1
scan_drm_connectors
[ "$selected_connector_status" = disconnected ]
force_drm_connectors_on
[ "$(cat "$DRM_ROOT/card0-HDMI-A-1/force")" = on ]
[ ! -s "$DRM_ROOT/card0-DP-1/force" ]
[ ! -s "$DRM_ROOT/card1-HDMI-A-1/force" ]
pass "forcing only the explicitly selected connector"

DISPLAY_OUTPUT=auto
force_drm_connectors_on
[ "$(cat "$DRM_ROOT/card0-DP-1/force")" = on ]
[ "$(cat "$DRM_ROOT/card1-HDMI-A-1/force")" = on ]
pass "automatic mode retains force-all behavior"

XRANDR_FAIL=false
XRANDR_APPLY_FAIL=false
xrandr() {
  case "$1" in
    --prop|--query)
      [ "$XRANDR_FAIL" = false ] || return 1
      printf '%s\n' "$XRANDR_STATE"
      ;;
    *)
      printf '%s\n' "$*" >> "$command_log"
      [ "$XRANDR_APPLY_FAIL" = false ]
      ;;
  esac
}
assert_output() {
  local actual
  actual="$(pick_active_output)"
  [ "$actual" = "$1" ] || fail "expected output '$1', got '$actual'"
}

XRANDR_STATE=$'DP-1 connected 1920x1080+0+0\n\tCONNECTOR_ID: 10\nHDMI-1 disconnected\n\tCONNECTOR_ID: 11'
DISPLAY_OUTPUT=""
assert_output DP-1
DISPLAY_OUTPUT=auto
assert_output DP-1
pass "automatic XrandR selection unchanged"

DISPLAY_OUTPUT=card0-HDMI-A-1
selected_connector=card0-HDMI-A-1
assert_output ""
FORCE_OUTPUT_ON=true
assert_output HDMI-1
FORCE_OUTPUT_ON=false
XRANDR_STATE="${XRANDR_STATE/HDMI-1 disconnected/HDMI-1 connected}"
assert_output HDMI-1
pass "explicit target waits for reconnect without switching to DP-1"

DISPLAY_OUTPUT=2
selected_connector=card1-HDMI-A-1
XRANDR_STATE=$'DP-1 connected\n\tCONNECTOR_ID: 10\nHDMI-1 connected\n\tCONNECTOR_ID: 21'
assert_output HDMI-1
XRANDR_STATE="${XRANDR_STATE/HDMI-1 connected/HDMI-1 disconnected}"
assert_output ""
XRANDR_STATE="${XRANDR_STATE/HDMI-1 disconnected/HDMI-1 connected}"
assert_output HDMI-1
pass "numeric choice stays bound to its original connector across reconnects"

XRANDR_STATE=$'HDMI-1 connected\n\tCONNECTOR_ID: 10\nHDMI-9 connected\n\tCONNECTOR_ID: 21'
assert_output HDMI-9
XRANDR_STATE=$'HDMI-1 connected\n\tCONNECTOR_ID: 10'
assert_output ""
pass "connector IDs override names and never fall back to a wrong connector"

XRANDR_STATE=$'DP-1 connected\nHDMI-1 connected'
assert_output HDMI-1
XRANDR_STATE=$'DP-1 connected\nHDMI-A-1 connected'
assert_output HDMI-A-1
pass "DRM/XrandR name mapping when connector IDs are unavailable"

DISPLAY_OUTPUT=auto
XRANDR_STATE=$'DP-1 disconnected\nHDMI-1 disconnected'
assert_output ""
FORCE_OUTPUT_ON=true
assert_output DP-1
FORCE_OUTPUT_ON=false
pass "automatic disconnected/force selection unchanged"

XRANDR_FAIL=true
if pick_active_output >"$fixture_dir/output" 2>"$error_log"; then
  fail "query failure was ignored"
fi
grep -q "could not query" "$error_log"
XRANDR_FAIL=false
pass "XrandR query failure reported"

ACTIVE_OUTPUT=HDMI-1
XRANDR_STATE=$'DP-1 connected 1920x1080+0+0\nHDMI-1 connected\nDP-2 disconnected'
DISPLAY_MODE=exclusive
: > "$command_log"
activate_selected_output
[ "$(cat "$command_log")" = "--output HDMI-1 --auto --primary --pos 0x0 --output DP-1 --off --output DP-2 --off" ]
pass "exclusive mode activates selected output and disables all others atomically"

DISPLAY_MODE=primary
: > "$command_log"
activate_selected_output
[ "$(cat "$command_log")" = "--output HDMI-1 --auto --primary --pos 0x0" ]
pass "primary mode leaves other outputs unchanged"

XRANDR_APPLY_FAIL=true
if activate_selected_output 2>"$error_log"; then
  fail "activation failure was ignored"
fi
grep -q "could not activate" "$error_log"
XRANDR_APPLY_FAIL=false
DISPLAY_MODE=exclusive
XRANDR_FAIL=true
if activate_selected_output 2>"$error_log"; then
  fail "exclusive-mode query failure was ignored"
fi
grep -q "could not query" "$error_log"
XRANDR_FAIL=false
pass "display mode failures reported"

color_overrides_requested() { return 1; }
log_xrandr_output_capabilities() { :; }
recover_bad_link_status() { :; }
ROTATE_DISPLAY=left
RESOLUTION_WIDTH=1280
RESOLUTION_HEIGHT=720
REFRESH_RATE=60
LAST_FULL_COLOR_APPLY_OUTPUT=""
LAST_CAPS_OUTPUT=""
DISPLAY_OUTPUT=card1-HDMI-A-1
selected_connector=card1-HDMI-A-1
for reason in startup reconnect; do
  for DISPLAY_MODE in exclusive primary; do
    : > "$command_log"
    configure_display_output "$reason"
    [ "$ACTIVE_OUTPUT" = HDMI-1 ]
    grep -qx -- "--output HDMI-1 --rotate left" "$command_log"
    grep -qx -- "--output HDMI-1 --mode 1280x720 --rate 60" "$command_log"
    if [ "$DISPLAY_MODE" = exclusive ]; then
      grep -q -- "--output DP-1 --off" "$command_log"
    elif grep -q -- "--off" "$command_log"; then
      fail "primary mode disabled another output"
    fi
    pass "$reason applies $DISPLAY_MODE, rotation, resolution and refresh to selected output"
  done
done

DISPLAY_OUTPUT=auto
DISPLAY_MODE=exclusive
: > "$command_log"
configure_display_output startup
[ "$ACTIVE_OUTPUT" = DP-1 ]
if grep -Eq -- '--primary|--off|--pos' "$command_log"; then
  fail "display_mode affected automatic selection"
fi
pass "display_mode is ignored in automatic mode"

DISPLAY_OUTPUT=card1-HDMI-A-1
XRANDR_APPLY_FAIL=true
if configure_display_output reconnect 2>"$error_log"; then
  fail "configuration reported success after activation failure"
fi
[ -z "$ACTIVE_OUTPUT" ] || fail "failed output would be marked ready by reconnect monitor"
pass "activation failure propagates to reconnect retry"
