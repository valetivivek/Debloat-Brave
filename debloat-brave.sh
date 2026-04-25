#!/usr/bin/env bash
# debloat-brave — interactive macOS Brave Browser debloater
# https://github.com/valetivivek/Debloat-Brave  (replace with your fork)
# License: MIT

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly VERSION="1.1.0"
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
  C_REV=$(tput rev)
  C_RESET=$(tput sgr0)
else
  C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA="" C_CYAN="" C_REV="" C_RESET=""
fi

# Theme aliases
C_ACCENT="$C_CYAN"
C_HEADING="$C_MAGENTA"
C_OK="$C_GREEN"
C_WARN="$C_YELLOW"
C_DANGER="$C_RED"

# ---------------------------------------------------------------------------
# Terminal sizing
# ---------------------------------------------------------------------------
TERM_COLS=80
update_term_size() {
  local c
  c=$(tput cols 2>/dev/null || echo 80)
  (( c < 60 )) && c=60
  (( c > 100 )) && c=100
  TERM_COLS=$c
}
update_term_size

# Repeat a single character N times. Usage: rep '─' 30
rep() {
  local ch=$1 n=$2 out=""
  local i
  for ((i=0; i<n; i++)); do out+="$ch"; done
  printf '%s' "$out"
}

# Pad string with spaces to reach target visible width
pad_right() {
  local s=$1 width=$2
  local len=${#s}
  local diff=$((width - len))
  (( diff < 0 )) && diff=0
  printf '%s%*s' "$s" "$diff" ''
}

# Move cursor home without clearing (reduces flicker vs `clear`)
cursor_home() { printf '\033[H'; }
clear_below()  { printf '\033[J'; }
clear_eol()    { printf '\033[K'; }

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
    '?')            KEY=HELP ;;
    '/')            KEY=SLASH ;;
    *)              KEY="OTHER:$first" ;;
  esac
}

# Render a footer hint bar (single line) at the bottom of a frame.
draw_hint_bar() {
  local hints=$1
  local sep
  sep=$(rep '─' "$TERM_COLS")
  printf '\n  %s%s%s\n' "$C_DIM" "$sep" "$C_RESET"
  printf '  %s%s%s\n' "$C_DIM" "$hints" "$C_RESET"
}

# Generic arrow-driven menu. Sets ARROW_RESULT to selected index or -1 (quit).
ARROW_RESULT=-1
arrow_select() {
  local title=$1; shift
  local -a items=("$@")
  local n=${#items[@]} cursor=0 i
  local row_w=$((TERM_COLS - 6))
  tput civis 2>/dev/null || true
  while true; do
    draw_header
    printf '\n  %s%s%s%s\n\n' "$C_BOLD" "$C_HEADING" "$title" "$C_RESET"
    for ((i=0; i<n; i++)); do
      local content
      content=$(pad_right "  ${items[$i]}" "$row_w")
      if ((i == cursor)); then
        printf '  %s▌%s%s%s%s\n' "$C_ACCENT" "$C_RESET" "$C_REV" "$content" "$C_RESET"
      else
        printf '   %s\n' "${items[$i]}"
      fi
    done
    draw_hint_bar "  ↑↓ / jk move    ⏎ select    q quit"
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
  update_term_size
  cursor_home
  clear_below

  local inner=$((TERM_COLS - 4))
  local title="debloat-brave  ${VERSION}"
  local bv mode
  bv=$(brave_version)
  if $SYSTEM_MODE; then
    mode="system"
  else
    mode="user"
  fi
  $DRY_RUN && mode="${mode}·dry-run"
  local right="Brave ${bv}   ${mode}"
  local left_padded
  left_padded=$(pad_right "$title" $((inner - ${#right})))

  printf '\n'
  printf '  %s%s╭%s╮%s\n' "$C_HEADING" "$C_BOLD" "$(rep '─' $((inner+2)))" "$C_RESET"
  printf '  %s%s│%s %s%s %s│%s\n' \
    "$C_HEADING" "$C_BOLD" "$C_RESET" \
    "${C_BOLD}${left_padded}${C_RESET}${C_DIM}${right}${C_RESET}" \
    "" "$C_HEADING$C_BOLD" "$C_RESET"
  printf '  %s%s╰%s╯%s\n' "$C_HEADING" "$C_BOLD" "$(rep '─' $((inner+2)))" "$C_RESET"
}

# ---------------------------------------------------------------------------
# Help overlay, spinner, toast
# ---------------------------------------------------------------------------
show_help() {
  draw_header
  cat <<EOF

  ${C_BOLD}${C_HEADING}Keyboard shortcuts${C_RESET}

    ${C_ACCENT}↑ ↓${C_RESET} or ${C_ACCENT}k j${C_RESET}    Move cursor up / down
    ${C_ACCENT}space${C_RESET}          Toggle highlighted row
    ${C_ACCENT}a${C_RESET}              Select all
    ${C_ACCENT}n${C_RESET}              Select none
    ${C_ACCENT}enter${C_RESET}          Apply / confirm
    ${C_ACCENT}?${C_RESET}              Show this help
    ${C_ACCENT}q${C_RESET} or ${C_ACCENT}esc${C_RESET}      Cancel / back

  ${C_BOLD}${C_HEADING}Status icons${C_RESET}

    ${C_OK}✓${C_RESET}              Set to debloat value
    ${C_DIM}○${C_RESET}              Brave default (key unset)
    ${C_DANGER}!${C_RESET}              Foreign value (something else changed it)

EOF
  draw_hint_bar "  press any key to return"
  read_key
}

# Animated braille spinner that runs apply across all categories.
# Usage: spinner_apply_all
spinner_apply_all() {
  if $DRY_RUN; then
    apply_all_recommended
    return 0
  fi
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0 row arr_name
  tput civis 2>/dev/null || true
  printf '\n'
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    load_rows "$arr_name"
    for row in "${__ROWS[@]}"; do
      parse_row "$row"
      printf '\r  %s%s%s  applying  %s%s%s' \
        "$C_ACCENT" "${frames[$((i % 10))]}" "$C_RESET" \
        "$C_DIM" "$__key" "$C_RESET"
      clear_eol
      apply_setting "$__key" "$__type" "$__desired"
      i=$((i + 1))
    done
  done
  tput cnorm 2>/dev/null || true
  printf '\r'; clear_eol
}

# Spinner across an explicit list of rows + selection map.
# Usage: spinner_apply_selected entries_var is_row_var selected_var
spinner_apply_selected() {
  if $DRY_RUN; then
    local i row_data
    eval "local n=\${#$1[@]}"
    for ((i=0; i<n; i++)); do
      eval "local is_r=\${$2[$i]}"
      [[ "$is_r" != "1" ]] && continue
      eval "row_data=\${$1[$i]#row|}"
      parse_row "$row_data"
      eval "local sel=\${$3[$i]}"
      if [[ "$sel" == "1" ]]; then
        apply_setting "$__key" "$__type" "$__desired"
      else
        revert_setting "$__key"
      fi
    done
    return 0
  fi
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i row_data idx=0
  eval "local n=\${#$1[@]}"
  tput civis 2>/dev/null || true
  printf '\n'
  for ((i=0; i<n; i++)); do
    eval "local is_r=\${$2[$i]}"
    [[ "$is_r" != "1" ]] && continue
    eval "row_data=\${$1[$i]#row|}"
    parse_row "$row_data"
    eval "local sel=\${$3[$i]}"
    local action="applying"
    [[ "$sel" != "1" ]] && action="reverting"
    printf '\r  %s%s%s  %s  %s%s%s' \
      "$C_ACCENT" "${frames[$((idx % 10))]}" "$C_RESET" \
      "$action" "$C_DIM" "$__key" "$C_RESET"
    clear_eol
    if [[ "$sel" == "1" ]]; then
      apply_setting "$__key" "$__type" "$__desired"
    else
      revert_setting "$__key"
    fi
    idx=$((idx + 1))
  done
  tput cnorm 2>/dev/null || true
  printf '\r'; clear_eol
}

toast_ok() {
  local msg=$1
  printf '\n  %s%s ✓ %s%s\n' "$C_BOLD" "$C_OK" "$msg" "$C_RESET"
}
toast_warn() {
  local msg=$1
  printf '\n  %s%s ! %s%s\n' "$C_BOLD" "$C_WARN" "$msg" "$C_RESET"
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
  printf '\n  %s%sQuick debloat%s   apply recommended preset to all %d keys\n' \
    "$C_BOLD" "$C_HEADING" "$C_RESET" "$(count_all_keys)"
  if ! $ASSUME_YES; then
    printf '\n  Proceed? [y/N] '
    local a; read -r a
    [[ "$a" =~ ^[yY]$ ]] || { toast_warn "Cancelled."; return 0; }
  fi
  guard_brave_running
  backup_current
  ensure_managed_plist
  spinner_apply_all
  flush_prefs_cache
  toast_ok "Applied $(count_all_keys) keys. Relaunch Brave to see changes."
}

mode_view() {
  draw_header
  local i=0 row arr_name set_count=0 total=0
  # First pass: count
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    load_rows "$arr_name"
    for row in "${__ROWS[@]}"; do
      parse_row "$row"
      local s
      s=$(setting_state "$__key" "$__type" "$__desired")
      [[ "$s" == "set" ]] && set_count=$((set_count + 1))
      total=$((total + 1))
    done
  done
  printf '\n  %s%sCurrent state%s   %s%d of %d debloated%s\n' \
    "$C_BOLD" "$C_HEADING" "$C_RESET" "$C_ACCENT" "$set_count" "$total" "$C_RESET"

  i=0
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    local title=${ALL_TITLES[$i]}
    printf '\n  %s▎ %s%s%s\n' "$C_HEADING" "$C_BOLD" "$title" "$C_RESET"
    load_rows "$arr_name"
    for row in "${__ROWS[@]}"; do
      parse_row "$row"
      local state icon
      state=$(setting_state "$__key" "$__type" "$__desired")
      case "$state" in
        set)     icon="${C_OK}✓${C_RESET}" ;;
        default) icon="${C_DIM}○${C_RESET}" ;;
        foreign) icon="${C_DANGER}!${C_RESET}" ;;
      esac
      printf '    %s  %s   %s%s%s\n' "$icon" "$__label" "$C_DIM" "$__key" "$C_RESET"
    done
    ((i++))
  done
  draw_hint_bar "  ${C_OK}✓${C_DIM} debloat-applied   ${C_DIM}○ Brave default   ${C_DANGER}!${C_DIM} foreign value"
}

mode_reset() {
  draw_header
  printf '\n  %s%sReset all%s   restore Brave defaults (only keys we manage)\n' \
    "$C_BOLD" "$C_HEADING" "$C_RESET"
  if ! $ASSUME_YES; then
    printf '\n  Proceed? [y/N] '
    local a; read -r a
    [[ "$a" =~ ^[yY]$ ]] || { toast_warn "Cancelled."; return 0; }
  fi
  guard_brave_running
  if $DRY_RUN; then
    reset_all
  else
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0 row arr_name
    tput civis 2>/dev/null || true
    printf '\n'
    for arr_name in "${ALL_CATEGORIES[@]}"; do
      load_rows "$arr_name"
      for row in "${__ROWS[@]}"; do
        parse_row "$row"
        printf '\r  %s%s%s  reverting  %s%s%s' \
          "$C_ACCENT" "${frames[$((i % 10))]}" "$C_RESET" \
          "$C_DIM" "$__key" "$C_RESET"
        clear_eol
        revert_setting "$__key"
        i=$((i + 1))
      done
    done
    tput cnorm 2>/dev/null || true
    printf '\r'; clear_eol
  fi
  flush_prefs_cache
  toast_ok "Reset complete. Relaunch Brave."
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
  local i j cat_idx=0 arr_name title row state row_total=0

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
      row_total=$((row_total + 1))
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

    # Count current selections
    local sel_count=0
    for ((i=0; i<n; i++)); do
      [[ "${is_row[$i]}" == "1" && "${selected[$i]}" == "1" ]] && sel_count=$((sel_count + 1))
    done

    local title_text="Customize"
    local counter="${sel_count} of ${row_total} selected"
    local left_w=$((TERM_COLS - ${#counter} - 4))
    printf '\n  %s%s%s%s%s%s%s\n' \
      "$C_BOLD" "$C_HEADING" "$(pad_right "$title_text" "$left_w")" "$C_RESET" \
      "$C_ACCENT" "$counter" "$C_RESET"

    for ((i=0; i<n; i++)); do
      local entry=${entries[$i]}
      if [[ "${is_row[$i]}" == "0" ]]; then
        local hdr=${entry#header|}
        printf '\n  %s▎ %s%s%s\n' "$C_HEADING" "$C_BOLD" "$hdr" "$C_RESET"
      else
        local row_data=${entry#row|}
        parse_row "$row_data"
        local check="○" check_color=$C_DIM
        if [[ "${selected[$i]}" == "1" ]]; then
          check="✓"; check_color=$C_OK
        fi
        local cur_state foreign=""
        cur_state=$(setting_state "$__key" "$__type" "$__desired")
        [[ "$cur_state" == "foreign" ]] && foreign=" ⚠"

        if (( i == cursor )); then
          # Full-width highlight bar with reverse video
          local content="  ${check}  ${__label}${foreign}"
          local pad_w=$((TERM_COLS - 4))
          local padded
          padded=$(pad_right "$content" "$pad_w")
          printf '  %s▌%s%s%s%s\n' "$C_ACCENT" "$C_RESET" "$C_REV" "$padded" "$C_RESET"
        else
          if [[ -n "$foreign" ]]; then
            printf '    %s%s%s  %s  %s%s%s\n' "$check_color" "$check" "$C_RESET" "$__label" "$C_DANGER" "$foreign" "$C_RESET"
          else
            printf '    %s%s%s  %s\n' "$check_color" "$check" "$C_RESET" "$__label"
          fi
        fi
      fi
    done

    draw_hint_bar "  ↑↓/jk move    ⎵ toggle    a all    n none    ? help    ⏎ apply    q cancel"
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
      HELP)
        show_help
        ;;
      ENTER)
        tput cnorm 2>/dev/null || true
        guard_brave_running
        backup_current
        ensure_managed_plist
        spinner_apply_selected entries is_row selected
        flush_prefs_cache
        toast_ok "Applied ${sel_count} of ${row_total}. Relaunch Brave."
        return 0
        ;;
      Q|ESC)
        tput cnorm 2>/dev/null || true
        toast_warn "Cancelled. No changes made."
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
