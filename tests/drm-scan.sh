#!/usr/bin/env bash
set -euo pipefail

script="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/run.sh}"
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

# Exercise the production function under errexit, redirecting only its sysfs root.
source <(sed -n '/^scan_drm_connectors() {$/,/^}$/p' "$script" |
  sed 's|/sys/class/drm|${DRM_ROOT}|g')
declare -F scan_drm_connectors >/dev/null

bashio::log.info() { printf '%s\n' "$*" >&2; }
bashio::log.error() { printf '%s\n' "$*" >&2; }

run_case() {
  local name="$1" expected_card="$2" expected_connector="$3"
  shift 3
  local index=0 state marker_count
  DRM_ROOT="$fixture_dir/${DISPLAY_OUTPUT:-empty}-$DEBUG_LOGGING-$name"
  mkdir -p "$DRM_ROOT"
  for state in "$@"; do
    mkdir -p "$DRM_ROOT/card$index-Virtual-1" "$DRM_ROOT/card$index/device"
    printf '%s\n' "$state" > "$DRM_ROOT/card$index-Virtual-1/status"
    ln -s /drivers/virtio-pci "$DRM_ROOT/card$index/device/driver"
    index=$((index + 1))
  done

  selected_card=stale
  selected_connector=stale
  # Do not call in an if/&&/|| condition: that would disable errexit in the function.
  scan_drm_connectors > "$DRM_ROOT/output"
  [ "$selected_card" = "$expected_card" ]
  [ "$selected_connector" = "$expected_connector" ]
  if [ "$DEBUG_LOGGING" = false ]; then
    [ ! -s "$DRM_ROOT/output" ]
  else
    [ "$(wc -l < "$DRM_ROOT/output" | tr -d ' ')" -eq "$index" ]
    marker_count="$(grep -c '^  \*' "$DRM_ROOT/output" || true)"
    if [ -n "$expected_card" ]; then
      [ "$marker_count" -eq 1 ]
      grep -q "^  \*$expected_connector " "$DRM_ROOT/output"
    else
      [ "$marker_count" -eq 0 ]
    fi
  fi
  printf 'PASS debug=%s %s\n' "$DEBUG_LOGGING" "$name"
}

for DISPLAY_OUTPUT in "" auto; do
  for DEBUG_LOGGING in false true; do
    run_case connected card0 card0-Virtual-1 connected
    run_case disconnected "" "" disconnected
    run_case empty "" ""
    run_case first-connected card0 card0-Virtual-1 connected disconnected
    run_case last-connected card1 card1-Virtual-1 disconnected connected
    run_case multiple-connected card0 card0-Virtual-1 connected connected
  done
done
