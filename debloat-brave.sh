#!/usr/bin/env bash
# debloat-brave - interactive macOS Brave Browser debloater
# https://github.com/valetivivek/Debloat-Brave
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

SYSTEM_MODE=false
DRY_RUN=false
QUICK=false
VIEW_ONLY=false
RESET=false
ASSUME_YES=false

# ---------------------------------------------------------------------------
# Setting registry
# Format: key|type|debloat_value|default_value|label
# type: bool|integer|string
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

ALL_CATEGORIES=(CAT_FEATURES CAT_TELEMETRY CAT_PRIVACY CAT_PERF CAT_DNS)
ALL_TITLES=("$CAT_FEATURES_TITLE" "$CAT_TELEMETRY_TITLE" "$CAT_PRIVACY_TITLE" "$CAT_PERF_TITLE" "$CAT_DNS_TITLE")

# ---------------------------------------------------------------------------
# Color and terminal helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  CLR_RESET=$(tput sgr0 2>/dev/null || true)
  CLR_BOLD=$(tput bold 2>/dev/null || true)
  CLR_DIM=$(tput dim 2>/dev/null || true)
  CLR_ACCENT=$(tput setaf 6 2>/dev/null || true)
  CLR_WARN=$(tput setaf 3 2>/dev/null || true)
  CLR_OK=$(tput setaf 2 2>/dev/null || true)
  CLR_ERR=$(tput setaf 1 2>/dev/null || true)
  CLR_TEXT=$(tput setaf 7 2>/dev/null || true)
  CLR_REV=$(tput rev 2>/dev/null || true)
  CLR_FOOTER=$(tput smso 2>/dev/null || tput rev 2>/dev/null || true)
else
  CLR_RESET=''
  CLR_BOLD=''
  CLR_DIM=''
  CLR_ACCENT=''
  CLR_WARN=''
  CLR_OK=''
  CLR_ERR=''
  CLR_TEXT=''
  CLR_REV=''
  CLR_FOOTER=''
fi

TERM_COLS=80
TERM_LINES=24

update_term_size() {
  local cols lines
  cols=$(tput cols 2>/dev/null || echo 80)
  lines=$(tput lines 2>/dev/null || echo 24)
  ((cols < 72)) && cols=72
  ((cols > 120)) && cols=120
  ((lines < 22)) && lines=22
  TERM_COLS=$cols
  TERM_LINES=$lines
}

rep() {
  local ch=$1
  local n=$2
  local out=""
  while ((n > 0)); do
    out="${out}${ch}"
    n=$((n - 1))
  done
  printf '%s' "$out"
}

trunc() {
  local text=$1
  local width=$2
  if ((${#text} <= width)); then
    printf '%s' "$text"
  elif ((width > 1)); then
    printf '%s…' "${text:0:$((width - 1))}"
  fi
}

pad_right() {
  local text=$1
  local width=$2
  local short
  short=$(trunc "$text" "$width")
  printf '%-*s' "$width" "$short"
}

tui_move() { tput cup "$1" "$2" 2>/dev/null || true; }
tui_clear() { tput clear 2>/dev/null || printf '\033c'; }
tui_cleol() { tput el 2>/dev/null || true; }
tui_hide_cursor() { tput civis 2>/dev/null || true; }
tui_show_cursor() { tput cnorm 2>/dev/null || true; }

restore_term() {
  tui_show_cursor
  printf '%s' "$CLR_RESET"
}

log_info() { printf '%s->%s %s\n' "$CLR_ACCENT" "$CLR_RESET" "$*"; }
log_warn() { printf '%s!%s %s\n' "$CLR_WARN" "$CLR_RESET" "$*"; }
log_err() { printf '%sERR%s %s\n' "$CLR_ERR" "$CLR_RESET" "$*" >&2; }

progress_bar() {
  local current=$1
  local total=$2
  local width=${3:-20}
  local filled empty
  ((total < 1)) && total=1
  filled=$((current * width / total))
  ((filled > width)) && filled=$width
  empty=$((width - filled))
  printf '%s%s' "$(rep '▓' "$filled")" "$(rep '░' "$empty")"
}

# ---------------------------------------------------------------------------
# Registry helpers
# ---------------------------------------------------------------------------
__ROWS=()
__key=''
__type=''
__desired=''
__default=''
__label=''

load_rows() {
  case "$1" in
    CAT_FEATURES) __ROWS=("${CAT_FEATURES[@]}") ;;
    CAT_TELEMETRY) __ROWS=("${CAT_TELEMETRY[@]}") ;;
    CAT_PRIVACY) __ROWS=("${CAT_PRIVACY[@]}") ;;
    CAT_PERF) __ROWS=("${CAT_PERF[@]}") ;;
    CAT_DNS) __ROWS=("${CAT_DNS[@]}") ;;
    *) __ROWS=() ;;
  esac
}

parse_row() {
  local row=$1
  IFS='|' read -r __key __type __desired __default __label <<< "$row"
}

count_all_keys() {
  local total=0
  local arr_name
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    load_rows "$arr_name"
    total=$((total + ${#__ROWS[@]}))
  done
  echo "$total"
}

normalize_bool() {
  case "$1" in
    1|true|TRUE|True|YES|Yes|yes) echo "true" ;;
    0|false|FALSE|False|NO|No|no) echo "false" ;;
    *) echo "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# Brave preference operations
# ---------------------------------------------------------------------------
detect_brave() {
  [[ -d "$BRAVE_APP" ]] || return 0
}

brave_version() {
  local plist="${BRAVE_APP}/Contents/Info.plist"
  if [[ -f "$plist" ]]; then
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || echo "unknown"
  else
    echo "not detected"
  fi
}

is_brave_running() {
  pgrep -f "Brave Browser" >/dev/null 2>&1
}

read_setting() {
  local key=$1
  local value
  if $SYSTEM_MODE && [[ -f "$MANAGED_PLIST" ]]; then
    if value=$(/usr/libexec/PlistBuddy -c "Print :${key}" "$MANAGED_PLIST" 2>/dev/null); then
      echo "$value"
      return 0
    fi
  fi
  if value=$(defaults read "$BRAVE_BUNDLE" "$key" 2>/dev/null); then
    echo "$value"
  else
    echo "__UNSET__"
  fi
}

setting_state() {
  local key=$1
  local type=$2
  local desired=$3
  local current
  current=$(read_setting "$key")
  if [[ "$current" == "__UNSET__" ]]; then
    echo "default"
    return 0
  fi
  case "$type" in
    bool)
      [[ "$(normalize_bool "$current")" == "$(normalize_bool "$desired")" ]] && echo "set" || echo "foreign"
      ;;
    integer|string)
      [[ "$current" == "$desired" ]] && echo "set" || echo "foreign"
      ;;
    *)
      echo "foreign"
      ;;
  esac
}

apply_setting() {
  local key=$1
  local type=$2
  local value=$3
  if $DRY_RUN; then
    if $SYSTEM_MODE; then
      printf '  [dry-run] sudo PlistBuddy -c "Delete :%s" %q\n' "$key" "$MANAGED_PLIST"
      printf '  [dry-run] sudo PlistBuddy -c "Add :%s %s %s" %q\n' "$key" "$type" "$value" "$MANAGED_PLIST"
    else
      printf '  [dry-run] defaults write %s %s -%s %s\n' "$BRAVE_BUNDLE" "$key" "$type" "$value"
    fi
    return 0
  fi
  if $SYSTEM_MODE; then
    sudo /usr/libexec/PlistBuddy -c "Delete :${key}" "$MANAGED_PLIST" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Add :${key} ${type} ${value}" "$MANAGED_PLIST"
  else
    defaults write "$BRAVE_BUNDLE" "$key" "-${type}" "$value"
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
    sudo /usr/libexec/PlistBuddy -c "Delete :${key}" "$MANAGED_PLIST" 2>/dev/null || true
  else
    defaults delete "$BRAVE_BUNDLE" "$key" 2>/dev/null || true
  fi
}

ensure_managed_plist() {
  $SYSTEM_MODE || return 0
  $DRY_RUN && return 0
  if [[ ! -f "$MANAGED_PLIST" ]]; then
    sudo mkdir -p "$(dirname "$MANAGED_PLIST")"
    printf '%s\n' \
      '<?xml version="1.0" encoding="UTF-8"?>' \
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
      '<plist version="1.0">' \
      '<dict/>' \
      '</plist>' | sudo tee "$MANAGED_PLIST" >/dev/null
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
  local out
  stamp=$(date +%Y%m%d-%H%M%S)
  out="${BACKUP_DIR}/backup-${stamp}.plist"
  defaults export "$BRAVE_BUNDLE" "$out" 2>/dev/null || true
  log_info "Backup: $out"
}

guard_brave_running() {
  local title=${1:-BRAVE RUNNING}
  local answer
  $DRY_RUN && return 0
  $VIEW_ONLY && return 0
  if is_brave_running; then
    if [[ -t 0 && -t 1 ]]; then
      draw_nexus_shell "$title" "Brave is currently running."
      printf '\n  %sBrave Browser is currently open.%s\n\n' "$CLR_WARN$CLR_BOLD" "$CLR_RESET"
      printf '  Quit Brave before applying changes so every preference is read on next launch.\n'
      printf '  You can continue anyway, but some changes may not appear until Brave restarts.\n\n'
    else
      log_warn "Brave is currently running."
      log_info "Quit Brave before applying changes; some keys are read at launch."
    fi
    if $ASSUME_YES; then
      return 0
    fi
    printf '  Continue anyway? [y/N] '
    read -r answer || answer=""
    [[ "$answer" =~ ^[yY]$ ]] || return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Keyboard input
# ---------------------------------------------------------------------------
KEY=""

read_key() {
  local first seq="" next="" saved=""
  KEY=""
  IFS= read -rsn1 first || return 1
  if [[ "$first" == $'\x1b' ]]; then
    saved=$(stty -g 2>/dev/null || true)
    [[ -n "$saved" ]] && stty -icanon min 0 time 1 2>/dev/null || true
    while IFS= read -rsn1 next 2>/dev/null; do
      [[ -z "$next" ]] && break
      seq="${seq}${next}"
      [[ "$next" =~ [A-D] ]] && break
      ((${#seq} >= 8)) && break
    done
    [[ -n "$saved" ]] && stty "$saved" 2>/dev/null || true
    case "$seq" in
      *A) KEY="UP" ;;
      *B) KEY="DOWN" ;;
      *C) KEY="RIGHT" ;;
      *D) KEY="LEFT" ;;
      *) KEY="ESC" ;;
    esac
    return 0
  fi
  case "$first" in
    "")
      KEY="ENTER"
      ;;
    " ")
      KEY="SPACE"
      ;;
    "?")
      KEY="HELP"
      ;;
    a|A)
      KEY="A"
      ;;
    n|N)
      KEY="N"
      ;;
    q|Q)
      KEY="Q"
      ;;
    j|J)
      KEY="DOWN"
      ;;
    k|K)
      KEY="UP"
      ;;
    h|H)
      KEY="LEFT"
      ;;
    l|L)
      KEY="RIGHT"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Manus-inspired shared UI
# ---------------------------------------------------------------------------
screen_width() {
  update_term_size
  echo "$TERM_COLS"
}

draw_rule() {
  local width=$1
  printf '├'
  rep '─' "$((width - 2))"
  printf '┤'
}

draw_top_frame() {
  local title=$1
  local right=$2
  local width inner left_text pad
  width=$(screen_width)
  inner=$((width - 2))
  left_text=" ${title}"
  pad=$((inner - ${#left_text} - ${#right} - 1))
  ((pad < 1)) && pad=1
  printf '%s┌' "$CLR_ACCENT"
  rep '─' "$inner"
  printf '┐%s\n' "$CLR_RESET"
  printf '%s│%s%s%s%*s%s%s │%s\n' \
    "$CLR_ACCENT" "$CLR_BOLD" "$left_text" "$CLR_RESET" \
    "$pad" "" "$CLR_DIM" "$right" "$CLR_RESET"
  printf '%s' "$CLR_ACCENT"
  draw_rule "$width"
  printf '%s\n' "$CLR_RESET"
}

draw_bottom_frame() {
  local log_line=$1
  local width inner
  width=$(screen_width)
  inner=$((width - 2))
  printf '%s' "$CLR_ACCENT"
  draw_rule "$width"
  printf '%s\n' "$CLR_RESET"
  printf '%s│%s %s%-*s %s│%s\n' \
    "$CLR_ACCENT" "$CLR_DIM" "$CLR_RESET" "$((inner - 2))" "$(trunc "$log_line" "$((inner - 2))")" "$CLR_ACCENT" "$CLR_RESET"
  printf '%s└' "$CLR_ACCENT"
  rep '─' "$inner"
  printf '┘%s\n' "$CLR_RESET"
}

draw_footer_bar() {
  local row=$1
  local text=$2
  local width
  width=$(screen_width)
  tui_move "$row" 0
  printf '%s' "$CLR_FOOTER"
  pad_right "  ${text}" "$width"
  printf '%s' "$CLR_RESET"
}

clear_region() {
  local row=$1
  local col=$2
  local width=$3
  ((width < 1)) && return 0
  tui_move "$row" "$col"
  printf '%*s' "$width" ''
}

clear_body_region() {
  local start_row=${1:-2}
  local end_row=${2:-$((TERM_LINES - 2))}
  local row
  ((end_row < start_row)) && return 0
  for ((row = start_row; row <= end_row; row++)); do
    clear_region "$row" 1 "$((TERM_COLS - 2))"
  done
}

draw_side_rails() {
  local start_row=${1:-2}
  local end_row=${2:-$((TERM_LINES - 2))}
  local width row
  width=$(screen_width)
  ((end_row < start_row)) && return 0
  for ((row = start_row; row <= end_row; row++)); do
    tui_move "$row" 0
    printf '%s│%s' "$CLR_ACCENT" "$CLR_RESET"
    tui_move "$row" "$((width - 1))"
    printf '%s│%s' "$CLR_ACCENT" "$CLR_RESET"
  done
}

mode_label() {
  local mode
  if $SYSTEM_MODE; then
    mode="system"
  else
    mode="user"
  fi
  $DRY_RUN && mode="${mode} dry-run"
  echo "$mode"
}

draw_nexus_shell() {
  local title=$1
  local log_line=$2
  local right bv
  bv=$(brave_version)
  if [[ "$bv" == "not detected" ]]; then
    right="BRAVE not detected | $(mode_label)"
  else
    right="BRAVE v${bv} | $(mode_label)"
  fi
  tui_clear
  draw_top_frame "DEBLOAT BRAVE // ${title}" "$right"
  tui_move "$((TERM_LINES - 3))" 0
  tui_cleol
  printf '%s' "$CLR_DIM"
  pad_right "[LOG] ${log_line}" "$TERM_COLS"
  printf '%s' "$CLR_RESET"
}

confirm_action() {
  local title=$1
  local message=$2
  local answer
  $ASSUME_YES && return 0
  if [[ -t 0 && -t 1 ]]; then
    draw_nexus_shell "$title" "Awaiting confirmation."
    printf '\n  %s%s%s\n\n' "$CLR_BOLD" "$message" "$CLR_RESET"
    printf '  Proceed? [y/N] '
  else
    printf '%s\n' "$message"
    printf 'Proceed? [y/N] '
  fi
  read -r answer || answer=""
  [[ "$answer" =~ ^[yY]$ ]]
}

show_notice() {
  local title=$1
  local message=$2
  if [[ -t 1 ]]; then
    draw_nexus_shell "$title" "$message"
    printf '\n  %s%s%s\n' "$CLR_BOLD" "$message" "$CLR_RESET"
  else
    printf '%s\n' "$message"
  fi
}

press_any_key() {
  [[ -t 0 && -t 1 ]] || return 0
  printf '\n  %sPress any key to continue...%s' "$CLR_DIM" "$CLR_RESET"
  read_key || true
}

# ---------------------------------------------------------------------------
# Execution overlay
# ---------------------------------------------------------------------------
execution_step() {
  local title=$1
  local current=$2
  local total=$3
  local action=$4
  local key=$5
  local percent
  percent=$((current * 100 / total))
  [[ -t 1 && "$DRY_RUN" == "false" ]] || return 0
  draw_nexus_shell "$title" "${action}: ${key}"
  printf '\n\n'
  printf '                     ┌───────────────────────────────────┐\n'
  printf '                     │ %s[ EXECUTION PROTOCOL ]%s            │\n' "$CLR_WARN" "$CLR_RESET"
  printf '                     │                                   │\n'
  printf '                     │ %-33s │\n' "$(pad_right "${action}..." 33)"
  printf '                     │ %s[%s]%s %3d%%              │\n' \
    "$CLR_ACCENT" "$(progress_bar "$current" "$total" 18)" "$CLR_RESET" "$percent"
  printf '                     │                                   │\n'
  printf '                     │ > %-31s │\n' "$(pad_right "$key" 31)"
  printf '                     └───────────────────────────────────┘\n'
}

apply_all_recommended() {
  local arr_name row total i=0
  total=$(count_all_keys)
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    load_rows "$arr_name"
    for row in "${__ROWS[@]}"; do
      parse_row "$row"
      i=$((i + 1))
      execution_step "EXECUTION PROTOCOL" "$i" "$total" "Applying configuration" "$__key"
      apply_setting "$__key" "$__type" "$__desired"
    done
  done
}

reset_all() {
  local arr_name row total i=0
  total=$(count_all_keys)
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    load_rows "$arr_name"
    for row in "${__ROWS[@]}"; do
      parse_row "$row"
      i=$((i + 1))
      execution_step "RESTORE PROTOCOL" "$i" "$total" "Restoring defaults" "$__key"
      revert_setting "$__key"
    done
  done
}

# ---------------------------------------------------------------------------
# Nexus main menu
# ---------------------------------------------------------------------------
MENU_RESULT=-1
MENU_ROW=5
MENU_COL=0
MENU_BOX_W=43
MENU_CONTENT_W=39

menu_action() {
  case "$1" in
    0) echo "ACTIVATE" ;;
    1) echo "CONFIGURE" ;;
    2) echo "ANALYZE" ;;
    3) echo "RESTORE" ;;
    *) echo "EXIT" ;;
  esac
}

menu_label() {
  case "$1" in
    0) echo "Quick Debloat" ;;
    1) echo "Customize" ;;
    2) echo "View State" ;;
    3) echo "Reset Defaults" ;;
    *) echo "Quit" ;;
  esac
}

draw_nexus_menu_item() {
  local idx=$1
  local cursor=$2
  local action label line
  action=$(menu_action "$idx")
  label=$(menu_label "$idx")
  tui_move "$((MENU_ROW + 1 + idx))" "$MENU_COL"
  if ((idx == cursor)); then
    line=$(printf '> [ %-9s ]  %s' "$action" "$label")
    printf '│ %s%-*s%s │' "$CLR_REV" "$MENU_CONTENT_W" "$line" "$CLR_RESET"
  else
    line=$(printf '  [ %-9s ]  %s' "$action" "$label")
    printf '│ %-*s │' "$MENU_CONTENT_W" "$line"
  fi
  tui_cleol
}

draw_nexus_menu() {
  local cursor=$1
  local i
  update_term_size
  MENU_COL=$(((TERM_COLS - MENU_BOX_W) / 2))
  ((MENU_COL < 2)) && MENU_COL=2
  MENU_CONTENT_W=$((MENU_BOX_W - 4))
  draw_nexus_shell "SYSTEM STATUS [ONLINE]" "System ready. Awaiting command."
  tui_move "$MENU_ROW" "$MENU_COL"
  printf '┌'
  rep '─' "$((MENU_BOX_W - 2))"
  printf '┐'
  for ((i = 0; i < 5; i++)); do
    draw_nexus_menu_item "$i" "$cursor"
  done
  tui_move "$((MENU_ROW + 6))" "$MENU_COL"
  printf '└'
  rep '─' "$((MENU_BOX_W - 2))"
  printf '┘'
  draw_footer_bar "$((TERM_LINES - 1))" "↑↓ or j/k navigate   enter select   q quit"
}

nexus_menu() {
  local cursor=0
  local max=4
  local old
  tui_hide_cursor
  draw_nexus_menu "$cursor"
  while true; do
    read_key || continue
    case "$KEY" in
      UP)
        old=$cursor
        ((cursor > 0)) && cursor=$((cursor - 1)) || cursor=$max
        draw_nexus_menu_item "$old" "$cursor"
        draw_nexus_menu_item "$cursor" "$cursor"
        ;;
      DOWN)
        old=$cursor
        ((cursor < max)) && cursor=$((cursor + 1)) || cursor=0
        draw_nexus_menu_item "$old" "$cursor"
        draw_nexus_menu_item "$cursor" "$cursor"
        ;;
      ENTER)
        MENU_RESULT=$cursor
        return 0
        ;;
      Q)
        MENU_RESULT=4
        return 0
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# View mode
# ---------------------------------------------------------------------------
mode_view() {
  local arr_name row cat_idx=0 set_count=0 total=0
  local state icon
  if [[ -t 1 ]]; then
    draw_nexus_shell "STATE ANALYSIS" "Reading current Brave preference state."
  fi
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    load_rows "$arr_name"
    for row in "${__ROWS[@]}"; do
      parse_row "$row"
      state=$(setting_state "$__key" "$__type" "$__desired")
      [[ "$state" == "set" ]] && set_count=$((set_count + 1))
      total=$((total + 1))
    done
  done
  printf '\n  %s%sCurrent state%s   %s%d of %d debloated%s\n' \
    "$CLR_BOLD" "$CLR_ACCENT" "$CLR_RESET" "$CLR_ACCENT" "$set_count" "$total" "$CLR_RESET"
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    printf '\n  %s%s%s\n' "$CLR_BOLD$CLR_ACCENT" "${ALL_TITLES[$cat_idx]}" "$CLR_RESET"
    load_rows "$arr_name"
    for row in "${__ROWS[@]}"; do
      parse_row "$row"
      state=$(setting_state "$__key" "$__type" "$__desired")
      case "$state" in
        set) icon="${CLR_OK}◉${CLR_RESET}" ;;
        foreign) icon="${CLR_WARN}!${CLR_RESET}" ;;
        *) icon="${CLR_DIM}○${CLR_RESET}" ;;
      esac
      printf '    %s  %-38s %s%s%s\n' "$icon" "$__label" "$CLR_DIM" "$__key" "$CLR_RESET"
    done
    cat_idx=$((cat_idx + 1))
  done
}

# ---------------------------------------------------------------------------
# Configuration matrix
# ---------------------------------------------------------------------------
ROW_DATA=()
ROW_CAT=()
ROW_POS=()
SELECTED=()
CAT_START=()
CAT_LEN=()
CAT_ROW=()
CAT_COL=()
ITEM_ROW=()
ITEM_COL=()
MATRIX_SELECTED_COUNT=0
MATRIX_FOREIGN_COUNT=0
MATRIX_DEFAULT_COUNT=0
MATRIX_COL_W=24

matrix_columns() {
  local cols=2
  update_term_size
  ((TERM_COLS >= 96)) && cols=3
  echo "$cols"
}

matrix_col_width() {
  local cols
  cols=$(matrix_columns)
  echo "$(((TERM_COLS - 4) / cols))"
}

matrix_build() {
  local arr_name row cat_idx=0 pos state
  ROW_DATA=()
  ROW_CAT=()
  ROW_POS=()
  SELECTED=()
  CAT_START=()
  CAT_LEN=()
  for arr_name in "${ALL_CATEGORIES[@]}"; do
    CAT_START[cat_idx]=${#ROW_DATA[@]}
    pos=0
    load_rows "$arr_name"
    for row in "${__ROWS[@]}"; do
      ROW_DATA+=("$row")
      ROW_CAT+=("$cat_idx")
      ROW_POS+=("$pos")
      parse_row "$row"
      state=$(setting_state "$__key" "$__type" "$__desired")
      if [[ "$state" == "set" ]]; then
        SELECTED+=(1)
      else
        SELECTED+=(0)
      fi
      pos=$((pos + 1))
    done
    CAT_LEN[cat_idx]=$pos
    cat_idx=$((cat_idx + 1))
  done
}

matrix_layout() {
  local cols col_w cat_idx col k shortest_col shortest_row
  local col_rows=()
  update_term_size
  cols=$(matrix_columns)
  col_w=$(((TERM_COLS - 4) / cols))
  for ((col = 0; col < cols; col++)); do
    col_rows[col]=4
  done
  for ((cat_idx = 0; cat_idx < ${#ALL_CATEGORIES[@]}; cat_idx++)); do
    shortest_col=0
    shortest_row=${col_rows[0]}
    for ((k = 1; k < cols; k++)); do
      if ((${col_rows[$k]} < shortest_row)); then
        shortest_col=$k
        shortest_row=${col_rows[$k]}
      fi
    done
    CAT_ROW[cat_idx]=$shortest_row
    CAT_COL[cat_idx]=$((2 + shortest_col * col_w))
    col_rows[shortest_col]=$((shortest_row + CAT_LEN[cat_idx] + 1))
  done
  for ((k = 0; k < ${#ROW_DATA[@]}; k++)); do
    cat_idx=${ROW_CAT[$k]}
    ITEM_ROW[k]=$((CAT_ROW[cat_idx] + 1 + ROW_POS[k]))
    ITEM_COL[k]=${CAT_COL[cat_idx]}
  done
}

matrix_recount() {
  local i state
  MATRIX_SELECTED_COUNT=0
  MATRIX_FOREIGN_COUNT=0
  MATRIX_DEFAULT_COUNT=0
  for ((i = 0; i < ${#ROW_DATA[@]}; i++)); do
    [[ "${SELECTED[$i]}" == "1" ]] && MATRIX_SELECTED_COUNT=$((MATRIX_SELECTED_COUNT + 1))
    parse_row "${ROW_DATA[$i]}"
    state=$(setting_state "$__key" "$__type" "$__desired")
    case "$state" in
      foreign) MATRIX_FOREIGN_COUNT=$((MATRIX_FOREIGN_COUNT + 1)) ;;
      default) MATRIX_DEFAULT_COUNT=$((MATRIX_DEFAULT_COUNT + 1)) ;;
    esac
  done
}

matrix_item_at_cat_pos() {
  local cat_idx=$1
  local pos=$2
  local len=${CAT_LEN[$cat_idx]}
  ((len < 1)) && return 1
  ((pos >= len)) && pos=$((len - 1))
  echo "$((${CAT_START[$cat_idx]} + pos))"
}

matrix_draw_item() {
  local idx=$1
  local cursor=$2
  local col_w=$3
  local state marker label_width status_color status_text status_block prefix
  local cell_width row col
  parse_row "${ROW_DATA[$idx]}"
  state=$(setting_state "$__key" "$__type" "$__desired")
  if [[ "${SELECTED[$idx]}" == "1" ]]; then
    marker="${CLR_OK}◉${CLR_RESET}"
  else
    marker="${CLR_DIM}○${CLR_RESET}"
  fi
  case "$state" in
    set) status_color=$CLR_OK; status_text="DISABLED" ;;
    foreign) status_color=$CLR_WARN; status_text="FOREIGN" ;;
    *) status_color=$CLR_DIM; status_text="DEFAULT" ;;
  esac
  cell_width=$((col_w - 2))
  ((cell_width < 18)) && cell_width=18
  status_block="[${status_text}]"
  label_width=$((cell_width - ${#status_block} - 5))
  ((label_width < 10)) && label_width=10
  row=${ITEM_ROW[$idx]}
  col=${ITEM_COL[$idx]}
  clear_region "$row" "$col" "$cell_width"
  tui_move "$row" "$col"
  if ((idx == cursor)); then
    prefix="${CLR_ACCENT}>${CLR_RESET}"
    printf '%s %s %s%s%s %s%s%s' \
      "$prefix" "$marker" "$CLR_BOLD$CLR_TEXT" "$(pad_right "$__label" "$label_width")" "$CLR_RESET" \
      "$status_color" "$status_block" "$CLR_RESET"
  else
    printf '  %s %s %s%s%s' \
      "$marker" "$(pad_right "$__label" "$label_width")" "$status_color" "$status_block" "$CLR_RESET"
  fi
}

matrix_draw() {
  local cursor=$1
  local cat_idx i col_w status_line
  matrix_layout
  matrix_recount
  col_w=$(matrix_col_width)
  MATRIX_COL_W=$col_w
  status_line="[STATUS] ${MATRIX_SELECTED_COUNT} DISABLED | ${MATRIX_FOREIGN_COUNT} FOREIGN | ${MATRIX_DEFAULT_COUNT} DEFAULT"
  draw_nexus_shell "CONFIGURATION MATRIX" "$status_line"
  clear_body_region 2 "$((TERM_LINES - 2))"
  draw_side_rails 2 "$((TERM_LINES - 2))"
  tui_move 2 2
  printf '%s%s%s' "$CLR_ACCENT" "$status_line" "$CLR_RESET"
  for ((cat_idx = 0; cat_idx < ${#ALL_CATEGORIES[@]}; cat_idx++)); do
    tui_move "${CAT_ROW[$cat_idx]}" "${CAT_COL[$cat_idx]}"
    printf '%s%s%s' "$CLR_BOLD$CLR_ACCENT" "$(trunc "${ALL_TITLES[$cat_idx]}" "$((col_w - 2))")" "$CLR_RESET"
  done
  for ((i = 0; i < ${#ROW_DATA[@]}; i++)); do
    matrix_draw_item "$i" "$cursor" "$col_w"
  done
  matrix_draw_info "$cursor"
  draw_footer_bar "$((TERM_LINES - 1))" "↑↓←→ or hjkl navigate   space toggle   a all   n none   enter apply   q cancel"
}

matrix_draw_status() {
  local status_line
  matrix_recount
  status_line="[STATUS] ${MATRIX_SELECTED_COUNT} DISABLED | ${MATRIX_FOREIGN_COUNT} FOREIGN | ${MATRIX_DEFAULT_COUNT} DEFAULT"
  clear_region 2 2 "$((TERM_COLS - 4))"
  tui_move 2 2
  printf '%s%s%s' "$CLR_ACCENT" "$status_line" "$CLR_RESET"
}

matrix_draw_info() {
  local cursor=$1
  local info_line
  parse_row "${ROW_DATA[$cursor]}"
  info_line="[INFO] ${__label}: ${__key}"
  clear_region 3 2 "$((TERM_COLS - 4))"
  tui_move 3 2
  printf '%s%s%s' "$CLR_DIM" "$(pad_right "$info_line" "$((TERM_COLS - 4))")" "$CLR_RESET"
}

matrix_redraw_cursor_move() {
  local old=$1
  local cursor=$2
  matrix_draw_item "$old" "$cursor" "$MATRIX_COL_W"
  matrix_draw_item "$cursor" "$cursor" "$MATRIX_COL_W"
  matrix_draw_info "$cursor"
}

matrix_redraw_all_items() {
  local cursor=$1
  local i
  for ((i = 0; i < ${#ROW_DATA[@]}; i++)); do
    matrix_draw_item "$i" "$cursor" "$MATRIX_COL_W"
  done
  matrix_draw_status
  matrix_draw_info "$cursor"
}

matrix_picker() {
  local cursor=0
  local i old cursor_cat cursor_pos target_cat target
  local last_idx
  matrix_build
  last_idx=$((${#ROW_DATA[@]} - 1))
  tui_hide_cursor
  matrix_draw "$cursor"
  while true; do
    read_key || continue
    case "$KEY" in
      UP)
        old=$cursor
        ((cursor > 0)) && cursor=$((cursor - 1)) || cursor=$last_idx
        matrix_redraw_cursor_move "$old" "$cursor"
        ;;
      DOWN)
        old=$cursor
        ((cursor < last_idx)) && cursor=$((cursor + 1)) || cursor=0
        matrix_redraw_cursor_move "$old" "$cursor"
        ;;
      LEFT)
        old=$cursor
        cursor_cat=${ROW_CAT[$cursor]}
        cursor_pos=${ROW_POS[$cursor]}
        target_cat=$((cursor_cat > 0 ? cursor_cat - 1 : ${#ALL_CATEGORIES[@]} - 1))
        target=$(matrix_item_at_cat_pos "$target_cat" "$cursor_pos")
        cursor=$target
        matrix_redraw_cursor_move "$old" "$cursor"
        ;;
      RIGHT)
        old=$cursor
        cursor_cat=${ROW_CAT[$cursor]}
        cursor_pos=${ROW_POS[$cursor]}
        target_cat=$((cursor_cat < ${#ALL_CATEGORIES[@]} - 1 ? cursor_cat + 1 : 0))
        target=$(matrix_item_at_cat_pos "$target_cat" "$cursor_pos")
        cursor=$target
        matrix_redraw_cursor_move "$old" "$cursor"
        ;;
      SPACE)
        if [[ "${SELECTED[$cursor]}" == "1" ]]; then
          SELECTED[cursor]=0
        else
          SELECTED[cursor]=1
        fi
        matrix_draw_item "$cursor" "$cursor" "$MATRIX_COL_W"
        matrix_draw_status
        ;;
      A)
        for ((i = 0; i < ${#SELECTED[@]}; i++)); do
          SELECTED[i]=1
        done
        matrix_redraw_all_items "$cursor"
        ;;
      N)
        for ((i = 0; i < ${#SELECTED[@]}; i++)); do
          SELECTED[i]=0
        done
        matrix_redraw_all_items "$cursor"
        ;;
      ENTER)
        return 0
        ;;
      Q)
        return 1
        ;;
    esac
  done
}

apply_matrix_selection() {
  local total=${#ROW_DATA[@]}
  local i action
  for ((i = 0; i < total; i++)); do
    parse_row "${ROW_DATA[$i]}"
    if [[ "${SELECTED[$i]}" == "1" ]]; then
      action="Applying configuration"
      execution_step "EXECUTION PROTOCOL" "$((i + 1))" "$total" "$action" "$__key"
      apply_setting "$__key" "$__type" "$__desired"
    else
      action="Restoring default"
      execution_step "EXECUTION PROTOCOL" "$((i + 1))" "$total" "$action" "$__key"
      revert_setting "$__key"
    fi
  done
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
mode_quick() {
  guard_brave_running "ACTIVATE" || {
    show_notice "CANCELLED" "No changes made. Quit Brave and run Quick Debloat again."
    return 0
  }
  confirm_action "ACTIVATE" "Apply the recommended debloat preset to all $(count_all_keys) keys?" || {
    show_notice "CANCELLED" "No changes made."
    return 0
  }
  backup_current
  ensure_managed_plist
  apply_all_recommended
  flush_prefs_cache
  show_notice "COMPLETE" "Applied $(count_all_keys) keys. Relaunch Brave to see changes."
}

mode_reset() {
  guard_brave_running "RESTORE" || {
    show_notice "CANCELLED" "No changes made. Quit Brave and run Reset Defaults again."
    return 0
  }
  confirm_action "RESTORE" "Restore Brave defaults for every key this tool manages?" || {
    show_notice "CANCELLED" "No changes made."
    return 0
  }
  reset_all
  flush_prefs_cache
  show_notice "COMPLETE" "Reset complete. Relaunch Brave."
}

mode_custom() {
  guard_brave_running "CONFIGURE" || {
    show_notice "CANCELLED" "No changes made. Quit Brave and open Customize again."
    return 0
  }
  if matrix_picker; then
    backup_current
    ensure_managed_plist
    apply_matrix_selection
    flush_prefs_cache
    show_notice "COMPLETE" "Configuration applied. Relaunch Brave."
  else
    show_notice "CANCELLED" "No changes made."
  fi
}

main_menu() {
  while true; do
    nexus_menu
    case "$MENU_RESULT" in
      0) mode_quick; press_any_key ;;
      1) mode_custom; press_any_key ;;
      2) mode_view; press_any_key ;;
      3) mode_reset; press_any_key ;;
      4) return 0 ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
debloat-brave v${VERSION} - interactive macOS Brave debloater

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

With no flags: launches the Manus-inspired Nexus dashboard.

Repository: https://github.com/valetivivek/Debloat-Brave
EOF
}

parse_flags() {
  while (($# > 0)); do
    case "$1" in
      --quick) QUICK=true ;;
      --view) VIEW_ONLY=true ;;
      --reset) RESET=true ;;
      --system) SYSTEM_MODE=true ;;
      --dry-run) DRY_RUN=true ;;
      -y|--yes) ASSUME_YES=true ;;
      -v|--version)
        echo "debloat-brave v${VERSION}"
        exit 0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
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
  trap restore_term EXIT INT TERM
  parse_flags "$@"
  detect_brave

  if $VIEW_ONLY; then
    mode_view
    exit 0
  fi

  if $RESET; then
    mode_reset
    exit 0
  fi

  if $QUICK; then
    mode_quick
    exit 0
  fi

  if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
    log_err "The interactive TUI must run in a real terminal (need TTY on stdin and stdout)."
    log_info "Non-interactive options: debloat-brave --view, --quick --dry-run --yes, or --help"
    exit 1
  fi

  main_menu
}

main "$@"