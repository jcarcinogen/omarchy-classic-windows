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
LOADER_BEGIN="-- BEGIN omarchy-classic-windows"
LOADER_END="-- END omarchy-classic-windows"
AUTOSTART_BEGIN="-- BEGIN omarchy-classic-windows plugin reload"
AUTOSTART_END="-- END omarchy-classic-windows plugin reload"
ASSUME_YES=false

if [[ "${1:-}" == "--yes" ]]; then
  ASSUME_YES=true
elif [[ $# -gt 0 ]]; then
  printf 'Unknown option: %s\n' "$1" >&2
  printf 'Run %s with no options, or use --yes.\n' "$0" >&2
  exit 2
fi

if [[ "$ASSUME_YES" != true ]]; then
  printf '%s\n' 'This removes Classic Windows and restores the Hyprland files it replaced.'
  printf 'Remove Classic Windows now? [y/N] '
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || { printf 'Cancelled.\n'; exit 0; }
fi

KNOWN_STATE_FILES=(
  loader.added
  legacy-loader.replaced
  autostart.added
  overlay.backup
  overlay.created
  hyprbars.enabled
  repository.added
)
INSTALL_STATE_FOUND=false
for state_file in "${KNOWN_STATE_FILES[@]}"; do
  if [[ -e "$STATE_DIR/$state_file" ]]; then
    INSTALL_STATE_FOUND=true
    break
  fi
done

if [[ "$INSTALL_STATE_FOUND" != true ]]; then
  rmdir "$STATE_DIR" >/dev/null 2>&1 || true
  printf '\n%s\n' 'Classic Windows is not installed; nothing was changed.'
  exit 0
fi

if [[ -f "$HYPRLAND_CONFIG" && -e "$STATE_DIR/loader.added" ]]; then
  python3 "$EDITOR" remove "$HYPRLAND_CONFIG" "$LOADER_BEGIN" "$LOADER_END"
fi

if [[ -f "$HYPRLAND_CONFIG" && -e "$STATE_DIR/legacy-loader.replaced" ]]; then
  LOADER='local xdg_config = os.getenv("XDG_CONFIG_HOME"); dofile(((xdg_config ~= nil and xdg_config ~= "") and xdg_config or (os.getenv("HOME") .. "/.config")) .. "/hypr/classic-windows.lua")'
  LEGACY_LOADER='dofile(os.getenv("HOME") .. "/.config/hypr/classic-windows.lua")'
  if ! python3 "$EDITOR" replace-line "$HYPRLAND_CONFIG" "$LOADER" "$LEGACY_LOADER" 2>/dev/null; then
    printf '%s\n' 'Kept the changed loader in hyprland.lua instead of overwriting your edit.'
  fi
fi

if [[ -f "$AUTOSTART_CONFIG" && -e "$STATE_DIR/autostart.added" ]]; then
  python3 "$EDITOR" remove "$AUTOSTART_CONFIG" "$AUTOSTART_BEGIN" "$AUTOSTART_END"
fi

if [[ -f "$STATE_DIR/overlay.backup" ]]; then
  cp -p "$STATE_DIR/overlay.backup" "$OVERLAY"
elif [[ -e "$STATE_DIR/overlay.created" && -f "$OVERLAY" ]]; then
  if cmp -s "$OVERLAY" "$PACKAGED_OVERLAY"; then
    rm -f "$OVERLAY"
  else
    printf '%s\n' "Kept $OVERLAY because it was changed after installation."
  fi
fi

if [[ -e "$STATE_DIR/hyprbars.enabled" ]] && command -v hyprpm >/dev/null 2>&1; then
  hyprpm disable hyprbars >/dev/null 2>&1 || true
fi

for state_file in "${KNOWN_STATE_FILES[@]}"; do
  rm -f "$STATE_DIR/$state_file"
done
if ! rmdir "$STATE_DIR" >/dev/null 2>&1; then
  printf '%s\n' "Kept $STATE_DIR because it contains files not created by this installer."
fi

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
fi

printf '\n%s\n' '✓ Classic Windows has been removed.'
printf '%s\n' 'Your previous Hyprland configuration has been restored.'
printf '%s\n' 'The shared hyprland-plugins repository was left installed in case another plugin uses it.'
