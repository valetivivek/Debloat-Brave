#!/usr/bin/env bash
# debloat-brave uninstaller — restore Brave defaults and remove the binary.
set -euo pipefail

PREFIX="${PREFIX:-/usr/local/bin}"
DEST="${PREFIX}/debloat-brave"

c_cyan="" c_green="" c_red="" c_yellow="" c_reset=""
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  c_cyan=$(tput setaf 6); c_green=$(tput setaf 2)
  c_red=$(tput setaf 1); c_yellow=$(tput setaf 3); c_reset=$(tput sgr0)
fi
info() { printf '%s→%s %s\n' "$c_cyan" "$c_reset" "$*"; }
ok()   { printf '%s✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '%s!%s %s\n' "$c_yellow" "$c_reset" "$*"; }
err()  { printf '%s✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; }

[[ "$(uname -s)" == "Darwin" ]] || { err "macOS only."; exit 1; }

if [[ -x "$DEST" ]]; then
  info "Restoring Brave defaults via $DEST --reset --yes"
  "$DEST" --reset --yes || warn "Reset reported errors; continuing removal."
else
  warn "$DEST not found; skipping reset."
fi

if [[ -e "$DEST" ]]; then
  if [[ -w "$PREFIX" ]]; then
    rm -f "$DEST"
  else
    sudo rm -f "$DEST"
  fi
  ok "Removed $DEST"
else
  warn "Already absent: $DEST"
fi

ok "Uninstall complete."
