#!/usr/bin/env bash
# debloat-brave installer
# Usage: curl -fsSL https://raw.githubusercontent.com/<user>/Debloat-Brave/main/install.sh | bash
#        or: bash install.sh
set -euo pipefail

REPO_URL="${DEBLOAT_BRAVE_REPO:-https://raw.githubusercontent.com/valetivivek/Debloat-Brave/main}"
PREFIX="${PREFIX:-/usr/local/bin}"
DEST="${PREFIX}/debloat-brave"
SRC_NAME="debloat-brave.sh"

c_cyan="" c_green="" c_red="" c_dim="" c_reset=""
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  c_cyan=$(tput setaf 6); c_green=$(tput setaf 2); c_red=$(tput setaf 1)
  c_dim=$(tput dim); c_reset=$(tput sgr0)
fi
info() { printf '%s→%s %s\n' "$c_cyan" "$c_reset" "$*"; }
ok()   { printf '%s✓%s %s\n' "$c_green" "$c_reset" "$*"; }
err()  { printf '%s✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; }

[[ "$(uname -s)" == "Darwin" ]] || { err "macOS only."; exit 1; }
command -v curl >/dev/null || { err "curl required."; exit 1; }

info "Installing debloat-brave to ${DEST}"

tmp=$(mktemp -t debloat-brave.XXXXXX)
trap 'rm -f "$tmp"' EXIT

# Prefer local file if running from cloned repo
local_src="$(cd "$(dirname "$0")" && pwd)/${SRC_NAME}"
if [[ -f "$local_src" ]]; then
  info "Using local source: ${local_src}"
  cp "$local_src" "$tmp"
else
  info "Downloading from ${REPO_URL}/${SRC_NAME}"
  curl -fsSL "${REPO_URL}/${SRC_NAME}" -o "$tmp"
fi

chmod +x "$tmp"

# Verify shebang/sanity
head -n1 "$tmp" | grep -q '^#!.*bash' || { err "Downloaded file is not a bash script."; exit 1; }

mkdir -p "$PREFIX" 2>/dev/null || true
if [[ -w "$PREFIX" ]]; then
  mv "$tmp" "$DEST"
else
  printf '%s%s%s sudo required to write to %s\n' "$c_dim" "→" "$c_reset" "$PREFIX"
  sudo mv "$tmp" "$DEST"
fi
trap - EXIT

ok "Installed: $DEST"
ok "Run: ${c_cyan}debloat-brave${c_reset}"
