#!/usr/bin/env bash
# debloat-brave installer
# Usage: curl -fsSL https://raw.githubusercontent.com/valetivivek/Debloat-Brave/main/install.sh | bash
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
warn() { printf '%s!%s %s\n' "$c_dim" "$c_reset" "$*"; }
err()  { printf '%s✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; }

[[ "$(uname -s)" == "Darwin" ]] || { err "macOS only."; exit 1; }
command -v curl >/dev/null || { err "curl required."; exit 1; }

info "Installing debloat-brave to ${DEST}"

tmp=$(mktemp -t debloat-brave.XXXXXX)
trap 'rm -f "$tmp"' EXIT

# Prefer local file only when this installer itself was run from a checkout.
script_path=${BASH_SOURCE[0]:-}
local_src=""
if [[ -n "$script_path" && ( "$script_path" == */* || -f "$script_path" ) ]]; then
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local_src="${script_dir}/${SRC_NAME}"
fi
if [[ -n "$local_src" && -f "$local_src" ]]; then
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
resolved="$(command -v debloat-brave 2>/dev/null || true)"
if [[ -n "$resolved" && "$resolved" != "$DEST" ]]; then
  warn "Your shell resolves debloat-brave to ${resolved}; update PATH or run ${DEST} directly."
elif [[ -n "$resolved" ]]; then
  ok "Shell resolves debloat-brave to: $resolved"
else
  warn "${PREFIX} is not on PATH yet; add it or run ${DEST} directly."
fi
warn "If an existing shell still runs an older copy, run: hash -r (bash) or rehash (zsh)."
ok "Run: ${c_cyan}debloat-brave${c_reset}"
