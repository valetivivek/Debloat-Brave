# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.0] - 2026-04-29

### Added

- Manus-inspired Nexus dashboard as the default interactive entry point
- Configuration matrix with category columns and arrow-key navigation
- Execution overlay for apply and reset progress
- Flicker-free TUI using tput cursor positioning instead of full redraws
- Status badges per item: DISABLED, DEFAULT, FOREIGN
- Live progress line showing disabled, foreign, and default counts
- Full color variable system using tput only, no hardcoded ANSI strings
- Redesigned header with Brave version detection inline
- Reverse-video footer bar
- Bounded matrix layout with left/right rails for compact terminals
- Installer diagnostics for PATH resolution and stale shell command caches
- Native Windows PowerShell support using Brave policy registry keys
- README screenshots for the Nexus dashboard and configuration matrix

### Fixed

- Piped installer no longer prefers an unrelated `debloat-brave.sh` from the caller's directory
- macOS uninstaller resets both user preferences and system managed policies before removing the binary

## [1.0.0] - 2024

### Added

- Initial release
- 30 toggles across 5 categories
- Interactive arrow-key TUI with checkbox toggles
- `--quick` preset flag
- `--dry-run` flag
- `--reset` flag
- `--system` flag for managed policy via PlistBuddy
- `--view` flag
- `--yes` flag for unattended use
- ShellCheck CI via GitHub Actions
- Auto-backup of plist before first apply
- MIT license
