#!/usr/bin/env bash
# debloat-brave — interactive macOS Brave Browser debloater
# https://github.com/valetivivek/Debloat-Brave  (replace with your fork)
# License: MIT

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly VERSION="1.0.0"
readonly BRAVE_BUNDLE="com.brave.Browser"
readonly MANAGED_PLIST="/Library/Managed Preferences/${BRAVE_BUNDLE}.plist"
readonly BRAVE_APP="/Applications/Brave Browser.app"
readonly BACKUP_DIR="${HOME}/.debloat-brave"

# Runtime flags
SYSTEM_MODE=false
DRY_RUN=false
QUICK=false
VIEW_ONLY=false
RESET=false
ASSUME_YES=false

# ---------------------------------------------------------------------------
# Setting registry
# Format: key|type|debloat_value|default_value|label
# type ∈ bool|integer|string
# ---------------------------------------------------------------------------
CAT_FEATURES_TITLE="Brave Features"
CAT_FEATURES=(
  "BraveRewardsDisabled|bool|true|false|Brave Rewards (BAT, ads)"
  "BraveWalletDisabled|bool|true|false|Brave Wallet (crypto)"
  "BraveVPNDisabled|bool|true|false|Brave VPN promo"
  "BraveAIChatEnabled|bool|false|true|Leo AI Chat sidebar"
  "TorDisabled|bool|true|false|Tor private windows"
  "BraveTalkDisabled|bool|true|false|Brave Talk video calls"
  "BraveNewsDisabled|bool|true|false|Brave News on new tab"
  "BraveSyncDisabled|bool|true|false|Sync chain"
  "BraveWeb3IPFSDisabled|bool|true|false|IPFS gateway / Web3"
)

CAT_TELEMETRY_TITLE="Telemetry & Analytics"
CAT_TELEMETRY=(
  "MetricsReportingEnabled|bool|false|true|Usage statistics reporting"
  "BraveP3AEnabled|bool|false|true|Privacy-preserving analytics (P3A)"
  "BraveStatsPingEnabled|bool|false|true|Daily stats ping"
  "BraveWebDiscoveryEnabled|bool|false|true|Web Discovery Project"
  "FeedbackSurveysEnabled|bool|false|true|In-product surveys"
  "UrlKeyedAnonymizedDataCollectionEnabled|bool|false|true|URL-keyed data collection"
)

CAT_PRIVACY_TITLE="Privacy & Security"
CAT_PRIVACY=(
  "PasswordManagerEnabled|bool|false|true|Built-in password manager"
  "AutofillAddressEnabled|bool|false|true|Address autofill"
  "AutofillCreditCardEnabled|bool|false|true|Credit card autofill"
  "SearchSuggestEnabled|bool|false|true|Search suggestions"
  "BlockThirdPartyCookies|bool|true|false|Force-block 3rd-party cookies"
  "EnableDoNotTrack|bool|true|false|Send Do-Not-Track header"
  "WebRtcIPHandling|string|disable_non_proxied_udp|default|WebRTC IP leak protection"
  "SafeBrowsingProtectionLevel|integer|1|2|SafeBrowsing level (1=standard, 2=enhanced)"
)

CAT_PERF_TITLE="Performance & Bloat"
CAT_PERF=(
  "BackgroundModeEnabled|bool|false|true|Run in background after close"
  "MediaRecommendationsEnabled|bool|false|true|Media recommendations"
  "ShoppingListEnabled|bool|false|true|Shopping list nag"
  "TranslateEnabled|bool|false|true|Page translation prompt"
  "SpellcheckEnabled|bool|false|true|Spellcheck"
  "DefaultBrowserSettingEnabled|bool|false|true|Default-browser nag"
)

CAT_DNS_TITLE="DNS"
CAT_DNS=(
  "DnsOverHttpsMode|string|automatic|off|DNS-over-HTTPS mode"
)

# Category dispatch table — names of arrays
ALL_CATEGORIES=(CAT_FEATURES CAT_TELEMETRY CAT_PRIVACY CAT_PERF CAT_DNS)
ALL_TITLES=("$CAT_FEATURES_TITLE" "$CAT_TELEMETRY_TITLE" "$CAT_PRIVACY_TITLE" "$CAT_PERF_TITLE" "$CAT_DNS_TITLE")

# ---------------------------------------------------------------------------
# Colors (tput, fall back to no-op when not a tty)
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  C_BOLD=$(tput bold)
  C_DIM=$(tput dim)
  C_RED=$(tput setaf 1)
  C_GREEN=$(tput setaf 2)
  C_YELLOW=$(tput setaf 3)
  C_BLUE=$(tput setaf 4)
  C_MAGENTA=$(tput setaf 5)
  C_CYAN=$(tput setaf 6)
  C_RESET=$(tput sgr0)
else
  C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA="" C_CYAN="" C_RESET=""
fi

# ---------------------------------------------------------------------------
# Terminal handling
# ---------------------------------------------------------------------------
restore_term() {
  tput cnorm 2>/dev/null || true
  stty echo 2>/dev/null || true
}
trap restore_term EXIT INT TERM

clear_screen() { printf '\033[2J\033[H'; }

press_any_key() {
  printf '\n%s' "${C_DIM}Press any key to continue...${C_RESET}"
  read -rsn1 _
  printf '\n'
}

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_info()  { printf '%s→%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
log_ok()    { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
log_err()   { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

# ---------------------------------------------------------------------------
# Brave detection
# ---------------------------------------------------------------------------
detect_brave() {
  if [[ ! -d "$BRAVE_APP" ]]; then
    log_err "Brave Browser not found at $BRAVE_APP"
    log_info "Install Brave first: https://brave.com/download/"
    exit 1
  fi
}

brave_version() {
  local plist="${BRAVE_APP}/Contents/Info.plist"
  if [[ -f "$plist" ]]; then
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

is_brave_running() {
  pgrep -f "Brave Browser" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Settings I/O
# ---------------------------------------------------------------------------
read_setting() {
  local key=$1
  defaults read "$BRAVE_BUNDLE" "$key" 2>/dev/null || echo "__UNSET__"
}

# Compare current value against desired debloat value
# Returns: "set" | "default" | "foreign"
setting_state() {
  local key=$1 type=$2 desired=$3
  local current
  current=$(read_setting "$key")
  if [[ "$current" == "__UNSET__" ]]; then
    echo "default"; return
  fi
  case "$type" in
    bool)
      # `defaults read` returns 0/1 for bools
      local want
      [[ "$desired" == "true" ]] && want=1 || want=0
      [[ "$current" == "$want" ]] && echo "set" || echo "foreign"
      ;;
    integer)
      [[ "$current" == "$desired" ]] && echo "set" || echo "foreign"
      ;;
    string)
      [[ "$current" == "$desired" ]] && echo "set" || echo "foreign"
      ;;
  esac
}

apply_setting() {
  local key=$1 type=$2 val=$3

  if $DRY_RUN; then
    if $SYSTEM_MODE; then
      printf '  [dry-run] sudo PlistBuddy -c "Add :%s %s %s" %q\n' "$key" "$type" "$val" "$MANAGED_PLIST"
    else
      printf '  [dry-run] defaults write %s %s -%s %s\n' "$BRAVE_BUNDLE" "$key" "$type" "$val"
    fi
    return 0
  fi

  if $SYSTEM_MODE; then
    sudo /usr/libexec/PlistBuddy -c "Delete :$key" "$MANAGED_PLIST" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Add :$key $type $val" "$MANAGED_PLIST"
  else
    defaults write "$BRAVE_BUNDLE" "$key" -"$type" "$val"
  fi
}

revert_setting() {
  local key=$1
  if $DRY_RUN; then
    if $SYSTEM_MODE; then
      printf '  [dry-run] sudo PlistBuddy -c "Delete :%s" %q\n' "$key" "$MANAGED_PLIST"
    else
      printf '  [dry-run] defaults delete %s %s\n' "$BRAVE_BUNDLE" "$key"
    fi
    return 0
  fi
  if $SYSTEM_MODE; then
    sudo /usr/libexec/PlistBuddy -c "Delete :$key" "$MANAGED_PLIST" 2>/dev/null || true
  else
    defaults delete "$BRAVE_BUNDLE" "$key" 2>/dev/null || true
  fi
}

ensure_managed_plist() {
  $SYSTEM_MODE || return 0
  $DRY_RUN && return 0
  if [[ ! -f "$MANAGED_PLIST" ]]; then
    sudo mkdir -p "$(dirname "$MANAGED_PLIST")"
    sudo /usr/libexec/PlistBuddy -c "Save" "$MANAGED_PLIST" 2>/dev/null || \
      echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict/></plist>' \
        | sudo tee "$MANAGED_PLIST" >/dev/null
  fi
}

flush_prefs_cache() {
  $SYSTEM_MODE || return 0
  $DRY_RUN && return 0
  sudo killall cfprefsd 2>/dev/null || true
}

backup_current() {
  $DRY_RUN && return 0
  mkdir -p "$BACKUP_DIR"
  local stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  local out="${BACKUP_DIR}/backup-${stamp}.plist"
  defaults export "$BRAVE_BUNDLE" "$out" 2>/dev/null || true
  log_info "Backup: $out"
}

# ---------------------------------------------------------------------------
# Row parsing helper
# ---------------------------------------------------------------------------
# Usage: parse_row "$row" key type desired default label
parse_row() {
  local row=$1
  IFS='|' read -r __key __type __desired __default __label <<<"$row"
}

# ---------------------------------------------------------------------------
# Array indirection (bash 3.2 compatible — no namerefs)
# Loads the rows of an array (by name) into a global __ROWS array.
# ---------------------------------------------------------------------------
load_rows() {
  local name=$1
  eval "__ROWS=( \"\${${name}[@]}\" )"
}

# ---------------------------------------------------------------------------
# Apply selections
# ---------------------------------------------------------------------------
apply_all_recommended() {
  local arr_name row
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    load_rows "$arr_name"
    for row in "${__ROWS[@]}"; do
      parse_row "$row"
      apply_setting "$__key" "$__type" "$__desired"
    done
  done
}

reset_all() {
  local arr_name row
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    load_rows "$arr_name"
    for row in "${__ROWS[@]}"; do
      parse_row "$row"
      revert_setting "$__key"
    done
  done
}

# ---------------------------------------------------------------------------
# Key reader (bash 3.2 compatible arrow-key support)
# Sets global KEY to: UP|DOWN|LEFT|RIGHT|ENTER|SPACE|A|N|Q|Y|ESC|OTHER:<char>
# ---------------------------------------------------------------------------
KEY=""
read_key() {
  local first rest1="" rest2="" saved=""
  IFS= read -rsn1 first
  if [[ "$first" == $'\x1b' ]]; then
    # ESC seen — read up to 2 more bytes with short timeout via stty
    saved=$(stty -g 2>/dev/null || true)
    [[ -n "$saved" ]] && stty -icanon min 0 time 1 2>/dev/null
    IFS= read -rsn1 rest1 2>/dev/null || rest1=""
    if [[ "$rest1" == "[" || "$rest1" == "O" ]]; then
      IFS= read -rsn1 rest2 2>/dev/null || rest2=""
    fi
    [[ -n "$saved" ]] && stty "$saved" 2>/dev/null
    case "${rest1}${rest2}" in
      '[A'|'OA') KEY=UP ;;
      '[B'|'OB') KEY=DOWN ;;
      '[C'|'OC') KEY=RIGHT ;;
      '[D'|'OD') KEY=LEFT ;;
      *)         KEY=ESC ;;
    esac
    return
  fi
  case "$first" in
    ''|$'\n'|$'\r') KEY=ENTER ;;
    ' ')            KEY=SPACE ;;
    j|J)            KEY=DOWN ;;
    k|K)            KEY=UP ;;
    h|H)            KEY=LEFT ;;
    l|L)            KEY=RIGHT ;;
    a|A)            KEY=A ;;
    n|N)            KEY=N ;;
    q|Q)            KEY=Q ;;
    y|Y)            KEY=Y ;;
    *)              KEY="OTHER:$first" ;;
  esac
}

# Generic arrow-driven menu. Sets ARROW_RESULT to selected index or -1 (quit).
ARROW_RESULT=-1
arrow_select() {
  local title=$1; shift
  local -a items=("$@")
  local n=${#items[@]} cursor=0 i
  tput civis 2>/dev/null || true
  while true; do
    draw_header
    printf '\n  %s%s%s\n\n' "$C_BOLD" "$title" "$C_RESET"
    for ((i=0; i<n; i++)); do
      if ((i == cursor)); then
        printf '  %s▶  %s%s%s\n' "$C_CYAN" "$C_BOLD" "${items[$i]}" "$C_RESET"
      else
        printf '     %s\n' "${items[$i]}"
      fi
    done
    printf '\n  %s↑/↓ or j/k · enter to select · q to quit%s\n' "$C_DIM" "$C_RESET"
    read_key
    case "$KEY" in
      UP)    cursor=$(( cursor > 0 ? cursor - 1 : n - 1 )) ;;
      DOWN)  cursor=$(( cursor < n - 1 ? cursor + 1 : 0 )) ;;
      ENTER) tput cnorm 2>/dev/null || true; ARROW_RESULT=$cursor; return ;;
      Q|ESC) tput cnorm 2>/dev/null || true; ARROW_RESULT=-1; return ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Header / banner
# ---------------------------------------------------------------------------
draw_header() {
  clear_screen
  local mode_label="user-level"
  $SYSTEM_MODE && mode_label="${C_RED}system-managed${C_RESET}"
  $DRY_RUN && mode_label="$mode_label ${C_YELLOW}(dry-run)${C_RESET}"
  cat <<EOF
${C_MAGENTA}${C_BOLD}
   ╔═══════════════════════════════════════════════╗
   ║         debloat-brave  ·  v${VERSION}              ║
   ║      Tame Brave Browser on macOS              ║
   ╚═══════════════════════════════════════════════╝${C_RESET}

${C_DIM}Brave version:${C_RESET} $(brave_version)   ${C_DIM}Mode:${C_RESET} ${mode_label}
EOF
}

# ---------------------------------------------------------------------------
# Main menu (arrow-driven)
# ---------------------------------------------------------------------------
main_menu() {
  local -a items=(
    "Quick debloat       — apply recommended preset to all keys"
    "Customize           — pick exactly which keys to toggle"
    "View current state  — show what's set right now"
    "Reset all           — restore Brave defaults (only keys we manage)"
    "Quit"
  )
  while true; do
    arrow_select "Main menu" "${items[@]}"
    case "$ARROW_RESULT" in
      0) mode_quick;  press_any_key ;;
      1) mode_custom ;;
      2) mode_view;   press_any_key ;;
      3) mode_reset;  press_any_key ;;
      4|-1) exit 0 ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Brave-running guard
# ---------------------------------------------------------------------------
guard_brave_running() {
  $DRY_RUN && return 0
  $VIEW_ONLY && return 0
  if is_brave_running; then
    log_warn "Brave is currently running."
    log_info "Quit Brave before applying changes (some keys won't take effect otherwise)."
    if ! $ASSUME_YES; then
      printf '  Continue anyway? [y/N] '
      local a; read -r a
      [[ "$a" =~ ^[yY]$ ]] || exit 1
    fi
  fi
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
mode_quick() {
  draw_header
  printf '\n  %sQuick debloat will apply the recommended preset to ALL %d keys.%s\n' \
    "$C_BOLD" "$(count_all_keys)" "$C_RESET"
  if ! $ASSUME_YES; then
    printf '\n  Proceed? [y/N] '
    local a; read -r a
    [[ "$a" =~ ^[yY]$ ]] || { log_info "Cancelled."; return 0; }
  fi
  guard_brave_running
  backup_current
  ensure_managed_plist
  log_info "Applying preset..."
  apply_all_recommended
  flush_prefs_cache
  log_ok "Done. Relaunch Brave for changes to take effect."
}

mode_view() {
  draw_header
  printf '\n'
  local i=0 row arr_name
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    local title=${ALL_TITLES[$i]}
    printf '  %s%s%s\n' "$C_BOLD" "$title" "$C_RESET"
    load_rows "$arr_name"
    for row in "${__ROWS[@]}"; do
      parse_row "$row"
      local state icon
      state=$(setting_state "$__key" "$__type" "$__desired")
      case "$state" in
        set)     icon="${C_GREEN}[x]${C_RESET}" ;;
        default) icon="${C_DIM}[ ]${C_RESET}" ;;
        foreign) icon="${C_RED}[!]${C_RESET}" ;;
      esac
      printf '    %s %s %s%s%s\n' "$icon" "$__label" "$C_DIM" "($__key)" "$C_RESET"
    done
    printf '\n'
    ((i++))
  done
  printf '  %sLegend:%s [x] debloat-applied  [ ] Brave default  [!] non-default foreign value\n' \
    "$C_DIM" "$C_RESET"
}

mode_reset() {
  draw_header
  printf '\n  %sReset will remove ALL keys this tool manages (restores Brave defaults).%s\n' \
    "$C_BOLD" "$C_RESET"
  if ! $ASSUME_YES; then
    printf '\n  Proceed? [y/N] '
    local a; read -r a
    [[ "$a" =~ ^[yY]$ ]] || { log_info "Cancelled."; return 0; }
  fi
  guard_brave_running
  log_info "Resetting..."
  reset_all
  flush_prefs_cache
  log_ok "Done. Relaunch Brave."
}

mode_custom() {
  flat_picker
  press_any_key
}

count_all_keys() {
  local total=0 arr_name len
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    eval "len=\${#${arr_name}[@]}"
    total=$((total + len))
  done
  echo "$total"
}

# ---------------------------------------------------------------------------
# Flat picker — single scrollable list across all categories
# Headers are non-selectable; cursor skips them. [x]/[ ] checkbox toggles.
# ---------------------------------------------------------------------------
flat_picker() {
  local -a entries     # "header|Title" or "row|<row-data>"
  local -a is_row      # 1 if selectable row, 0 if header
  local -a selected    # 0/1 per entry (only meaningful for rows)
  local i j cat_idx=0 arr_name title row state

  # Build flat list
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    title=${ALL_TITLES[$cat_idx]}
    entries+=( "header|${title}" )
    is_row+=( 0 )
    selected+=( 0 )
    load_rows "$arr_name"
    for row in "${__ROWS[@]}"; do
      entries+=( "row|${row}" )
      is_row+=( 1 )
      parse_row "$row"
      state=$(setting_state "$__key" "$__type" "$__desired")
      if [[ "$state" == "set" ]]; then
        selected+=( 1 )
      else
        selected+=( 0 )
      fi
    done
    ((cat_idx++))
  done

  local n=${#entries[@]}
  local cursor=0
  for ((i=0; i<n; i++)); do
    if [[ "${is_row[$i]}" == "1" ]]; then cursor=$i; break; fi
  done

  tput civis 2>/dev/null || true
  while true; do
    draw_header
    printf '\n  %sCustomize%s   %s↑/↓ or j/k move · space toggle · a all · n none · enter apply · q cancel%s\n' \
      "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"

    for ((i=0; i<n; i++)); do
      local entry=${entries[$i]}
      if [[ "${is_row[$i]}" == "0" ]]; then
        local hdr=${entry#header|}
        printf '\n  %s%s▎ %s%s\n' "$C_BOLD" "$C_MAGENTA" "$hdr" "$C_RESET"
      else
        local row_data=${entry#row|}
        parse_row "$row_data"
        local mark="[ ]" color=$C_DIM
        if [[ "${selected[$i]}" == "1" ]]; then
          mark="[x]"; color=$C_GREEN
        fi
        local cur_state hint=""
        cur_state=$(setting_state "$__key" "$__type" "$__desired")
        [[ "$cur_state" == "foreign" ]] && hint="  ${C_RED}!foreign${C_RESET}"
        if (( i == cursor )); then
          printf '  %s▶%s %s%s%s  %s%s\n' "$C_CYAN" "$C_RESET" "$color" "$mark" "$C_RESET" "$__label" "$hint"
        else
          printf '    %s%s%s  %s%s\n' "$color" "$mark" "$C_RESET" "$__label" "$hint"
        fi
      fi
    done

    read_key
    case "$KEY" in
      UP)
        local newpos=$cursor
        for ((j=cursor-1; j>=0; j--)); do
          if [[ "${is_row[$j]}" == "1" ]]; then newpos=$j; break; fi
        done
        if [[ $newpos -eq $cursor ]]; then
          for ((j=n-1; j>cursor; j--)); do
            if [[ "${is_row[$j]}" == "1" ]]; then newpos=$j; break; fi
          done
        fi
        cursor=$newpos
        ;;
      DOWN)
        local newpos=$cursor
        for ((j=cursor+1; j<n; j++)); do
          if [[ "${is_row[$j]}" == "1" ]]; then newpos=$j; break; fi
        done
        if [[ $newpos -eq $cursor ]]; then
          for ((j=0; j<cursor; j++)); do
            if [[ "${is_row[$j]}" == "1" ]]; then newpos=$j; break; fi
          done
        fi
        cursor=$newpos
        ;;
      SPACE)
        if [[ "${selected[$cursor]}" == "1" ]]; then
          selected[$cursor]=0
        else
          selected[$cursor]=1
        fi
        ;;
      A)
        for ((i=0; i<n; i++)); do
          [[ "${is_row[$i]}" == "1" ]] && selected[$i]=1
        done
        ;;
      N)
        for ((i=0; i<n; i++)); do
          [[ "${is_row[$i]}" == "1" ]] && selected[$i]=0
        done
        ;;
      ENTER)
        tput cnorm 2>/dev/null || true
        guard_brave_running
        backup_current
        ensure_managed_plist
        for ((i=0; i<n; i++)); do
          if [[ "${is_row[$i]}" == "1" ]]; then
            local row_data=${entries[$i]#row|}
            parse_row "$row_data"
            if [[ "${selected[$i]}" == "1" ]]; then
              apply_setting "$__key" "$__type" "$__desired"
            else
              revert_setting "$__key"
            fi
          fi
        done
        flush_prefs_cache
        log_ok "Applied. Relaunch Brave for changes to take effect."
        return 0
        ;;
      Q|ESC)
        tput cnorm 2>/dev/null || true
        log_info "Cancelled — no changes made."
        return 0
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
debloat-brave v${VERSION} — interactive macOS Brave debloater

Usage: debloat-brave [options]

Options:
  --quick         Apply recommended preset (no menu)
  --view          Print current state of all managed keys, then exit
  --reset         Remove all keys this tool manages
  --system        Write to /Library/Managed Preferences (sudo). Strongest enforcement
  --dry-run       Print commands instead of executing
  -y, --yes       Assume "yes" to all prompts
  -v, --version   Print version
  -h, --help      Print this help

With no flags: launches interactive TUI.

Repository: https://github.com/valetivivek/Debloat-Brave
EOF
}

parse_flags() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quick)    QUICK=true ;;
      --view)     VIEW_ONLY=true ;;
      --reset)    RESET=true ;;
      --system)   SYSTEM_MODE=true ;;
      --dry-run)  DRY_RUN=true ;;
      -y|--yes)   ASSUME_YES=true ;;
      -v|--version) echo "debloat-brave v${VERSION}"; exit 0 ;;
      -h|--help)  usage; exit 0 ;;
      *)
        log_err "Unknown option: $1"
        usage
        exit 2
        ;;
    esac
    shift
  done
}

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------
main() {
  parse_flags "$@"
  detect_brave

  if $VIEW_ONLY; then
    mode_view
    exit 0
  fi
  if $RESET; then
    guard_brave_running
    reset_all
    flush_prefs_cache
    log_ok "Reset complete."
    exit 0
  fi
  if $QUICK; then
    guard_brave_running
    backup_current
    ensure_managed_plist
    apply_all_recommended
    flush_prefs_cache
    log_ok "Quick debloat applied. Relaunch Brave."
    exit 0
  fi

  # Interactive
  main_menu
}

main "$@"
