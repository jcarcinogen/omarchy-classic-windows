#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
HYPRLAND_CONFIG="$HYPR_DIR/hyprland.lua"
AUTOSTART_CONFIG="$HYPR_DIR/autostart.lua"
OVERLAY="$HYPR_DIR/classic-windows.lua"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-classic-windows"
PACKAGED_OVERLAY="$PROJECT_DIR/config/classic-windows.lua"
EDITOR="$PROJECT_DIR/lib/edit_config.py"
HYPRPM_STATUS="$PROJECT_DIR/lib/hyprpm_status.py"
PLUGIN_REPO="https://github.com/hyprwm/hyprland-plugins"
LOADER_BEGIN="-- BEGIN omarchy-classic-windows"
LOADER_END="-- END omarchy-classic-windows"
AUTOSTART_BEGIN="-- BEGIN omarchy-classic-windows plugin reload"
AUTOSTART_END="-- END omarchy-classic-windows plugin reload"
LOADER='local xdg_config = os.getenv("XDG_CONFIG_HOME"); dofile(((xdg_config ~= nil and xdg_config ~= "") and xdg_config or (os.getenv("HOME") .. "/.config")) .. "/hypr/classic-windows.lua")'
LEGACY_LOADER='dofile(os.getenv("HOME") .. "/.config/hypr/classic-windows.lua")'
RELOAD='o.launch_on_start("hyprpm reload -n")'
ASSUME_YES=false

if [[ "${1:-}" == "--yes" ]]; then
  ASSUME_YES=true
elif [[ $# -gt 0 ]]; then
  printf 'Unknown option: %s\n' "$1" >&2
  printf 'Run %s with no options, or use --yes.\n' "$0" >&2
  exit 2
fi

fail() {
  printf '\nSetup stopped: %s\n' "$1" >&2
  printf 'Nothing after this check was changed.\n' >&2
  exit 1
}

has_exact_line() {
  local path=$1
  local expected=$2
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$expected" ]] && return 0
  done < "$path"
  return 1
}

for command_name in python3 hyprpm hyprctl omarchy; do
  command -v "$command_name" >/dev/null 2>&1 || fail "the '$command_name' command is missing. This installer requires Omarchy Quattro."
done

[[ -f "$HYPRLAND_CONFIG" ]] || fail "could not find your Omarchy Hyprland configuration at $HYPRLAND_CONFIG."
[[ -f "$AUTOSTART_CONFIG" ]] || fail "could not find your Omarchy autostart configuration at $AUTOSTART_CONFIG."
[[ -f "$PACKAGED_OVERLAY" ]] || fail "the package is incomplete: config/classic-windows.lua is missing."

printf '%s\n' 'Omarchy Classic Windows will:'
printf '%s\n' '  • add a close-only title bar that matches your current Omarchy theme'
printf '%s\n' '  • make Super+T float and center the active window'
printf '%s\n' '  • make Super+Ctrl+T toggle automatic floating for newly opened windows'
printf '%s\n' '  • maximize and restore a floating window when you double-click its title bar'
printf '%s\n' '  • let you resize floating windows by dragging an edge or corner'
printf '%s\n' '  • leave tiled windows clean, without title bars'
printf '\n%s\n' 'Your existing Hyprland files are backed up or edited only inside clearly marked blocks.'

if [[ "$ASSUME_YES" != true ]]; then
  printf '\nInstall Classic Windows now? [y/N] '
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || { printf 'Cancelled.\n'; exit 0; }
fi

mkdir -p "$HYPR_DIR" "$STATE_DIR"

HYPRPM_LIST=$(hyprpm list 2>/dev/null || true)
if [[ "$HYPRPM_LIST" != *"Repository hyprland-plugins"* ]]; then
  printf '\nInstalling the official Hyprland plugin collection…\n'
  hyprpm add "$PLUGIN_REPO"
  : > "$STATE_DIR/repository.added"
fi

HYPRPM_LIST=$(hyprpm list 2>/dev/null || true)
HYPRBARS_ENABLED=$(printf '%s\n' "$HYPRPM_LIST" | python3 "$HYPRPM_STATUS")
if [[ "$HYPRBARS_ENABLED" != "true" ]]; then
  printf 'Enabling the official hyprbars plugin…\n'
  hyprpm enable hyprbars
  : > "$STATE_DIR/hyprbars.enabled"
fi

if [[ ! -e "$STATE_DIR/overlay.backup" && ! -e "$STATE_DIR/overlay.created" ]]; then
  if [[ -e "$OVERLAY" ]]; then
    cp -p "$OVERLAY" "$STATE_DIR/overlay.backup"
  else
    : > "$STATE_DIR/overlay.created"
  fi
fi

cp "$PACKAGED_OVERLAY" "$OVERLAY"

if ! has_exact_line "$HYPRLAND_CONFIG" "$LOADER"; then
  if [[ "$HYPR_DIR" == "$HOME/.config/hypr" ]] && has_exact_line "$HYPRLAND_CONFIG" "$LEGACY_LOADER"; then
    : # The older loader is valid at the default location; adopt it unchanged.
  elif has_exact_line "$HYPRLAND_CONFIG" "$LEGACY_LOADER"; then
    python3 "$EDITOR" replace-line "$HYPRLAND_CONFIG" "$LEGACY_LOADER" "$LOADER"
    : > "$STATE_DIR/legacy-loader.replaced"
  else
    python3 "$EDITOR" add "$HYPRLAND_CONFIG" "$LOADER_BEGIN" "$LOADER_END" "$LOADER"
    : > "$STATE_DIR/loader.added"
  fi
fi

if ! has_exact_line "$AUTOSTART_CONFIG" "$RELOAD"; then
  python3 "$EDITOR" add "$AUTOSTART_CONFIG" "$AUTOSTART_BEGIN" "$AUTOSTART_END" "$RELOAD"
  : > "$STATE_DIR/autostart.added"
fi

hyprpm reload -n >/dev/null 2>&1 || true
hyprctl reload >/dev/null 2>&1 || true

printf '\n%s\n' '✓ Classic Windows is installed.'
printf '%s\n' '  Press Super+T on any window to switch between tiled and floating.'
printf '%s\n' '  Press Super+Ctrl+T to make newly opened windows float automatically.'
printf '%s\n' '  Double-click the title bar to maximize or restore a floating window.'
printf '%s\n' '  Drag a floating window edge or corner to resize it.'
printf '%s\n' '  Click the simple × to close it.'
printf '\n%s\n' 'One final step: log out of Omarchy and sign in again once.'
printf '%s\n' 'This starts a clean session with hyprbars loaded from the beginning.'
