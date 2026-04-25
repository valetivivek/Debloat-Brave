# Debloat-Brave

[![ShellCheck](https://img.shields.io/github/actions/workflow/status/valetivivek/Debloat-Brave/shellcheck.yml?branch=main&label=shellcheck)](https://github.com/valetivivek/Debloat-Brave/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![macOS](https://img.shields.io/badge/macOS-12%2B-black?logo=apple&logoColor=white)](https://github.com/valetivivek/Debloat-Brave)

Interactive macOS debloater for Brave Browser. One Bash script, zero dependencies, arrow-key TUI to pick exactly which Brave bloat to disable (Rewards, Wallet, VPN, Leo AI, telemetry, autofill, and more).

```bash
curl -fsSL https://raw.githubusercontent.com/valetivivek/Debloat-Brave/main/install.sh | bash
debloat-brave
```

> Built on Brave's documented Chromium policy keys and Apple's `defaults` system, so every change is inspectable and reversible.

## Why

Brave ships with a lot of features most people never touch: BAT/Rewards, the crypto wallet, VPN promos, Leo AI sidebar, IPFS gateway, Tor private windows, news widgets on every new tab, six kinds of telemetry. There's no single switch to turn them all off.

This is that single switch. Pick what you want gone, leave the rest alone, restore Brave defaults any time.

## Features

* Pure Bash. No `brew install` first, no Python, no Go binary, no Electron app.
* Arrow-key TUI with checkbox toggles, vim bindings (`j/k/h/l`), and live status indicators.
* About 30 curated toggles across 5 categories (full list below).
* Quick-debloat preset for one-command sane defaults.
* Dry-run mode prints every command before running it.
* Reset restores Brave defaults, touching only the keys this tool manages.
* Optional system-wide mode (`--system`) writes to `/Library/Managed Preferences/` for full UI removal.
* Auto-backup of your current `com.brave.Browser` plist before the first apply.

## Install

One-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/valetivivek/Debloat-Brave/main/install.sh | bash
```

Or clone and install:

```bash
git clone https://github.com/valetivivek/Debloat-Brave.git
cd Debloat-Brave
bash install.sh
```

The installer drops `debloat-brave` into `/usr/local/bin` (override with `PREFIX=$HOME/.local/bin`). Then run it from anywhere:

```bash
debloat-brave
```

## Usage

```text
debloat-brave              # interactive TUI
debloat-brave --quick      # apply recommended preset, no menu
debloat-brave --view       # print current state of all managed keys
debloat-brave --reset      # restore Brave defaults (only keys we manage)
debloat-brave --system     # write to /Library/Managed Preferences (sudo, strongest enforcement)
debloat-brave --dry-run    # print the commands instead of running them
debloat-brave --yes        # assume "yes" to all prompts (good for scripts)
debloat-brave --help
```

### TUI keybindings

| Key | Action |
|-----|--------|
| `↑` / `k` | Cursor up |
| `↓` / `j` | Cursor down |
| `space` | Toggle highlighted row |
| `a` | Select all |
| `n` | Select none |
| `enter` | Apply / select |
| `q` or `esc` | Cancel / quit |

### Status icons

| Icon | Meaning |
|------|---------|
| `[x]` (green) | Set to debloat value |
| `[ ]` (dim)   | Brave default (key unset) |
| `!foreign` (red) | Set to a non-default, non-debloat value (something else changed it) |

## Options

### Brave features

* Brave Rewards (BAT, ads)
* Brave Wallet (crypto)
* Brave VPN promo
* Leo AI Chat sidebar
* Tor private windows
* Brave Talk
* Brave News on new tab
* Sync chain
* IPFS gateway / Web3

### Telemetry & analytics

* Usage statistics reporting (`MetricsReportingEnabled`)
* Privacy-preserving analytics (P3A)
* Daily stats ping
* Web Discovery Project
* In-product surveys
* URL-keyed anonymized data collection

### Privacy & security

* Built-in password manager
* Address autofill
* Credit-card autofill
* Search suggestions
* Force-block third-party cookies
* Send Do-Not-Track header
* WebRTC IP leak protection (`disable_non_proxied_udp`)
* SafeBrowsing level (standard vs enhanced)

### Performance & bloat

* Run in background after close
* Media recommendations
* Shopping list nag
* Page translation prompt
* Spellcheck
* Default-browser nag

### DNS

* DNS-over-HTTPS mode (`automatic`)

All keys map directly to documented Brave/Chromium policies. The single source of truth is the `CAT_*` arrays at the top of [`debloat-brave.sh`](./debloat-brave.sh).

## How it works

By default the tool writes to your **user-level** plist:

```bash
defaults write com.brave.Browser <Key> -bool true
```

This works without sudo and covers most preferences. A handful of Brave features (Wallet UI elements, Tor menu items) only fully disappear when written as **managed policy**. Pass `--system` to use `/Library/Managed Preferences/com.brave.Browser.plist` via `PlistBuddy` (requires sudo). After system writes, `cfprefsd` is flushed so Brave picks up changes immediately.

A backup of your current Brave defaults is exported to `~/.debloat-brave/backup-<timestamp>.plist` before the first apply, so you can always go back.

## Uninstall

```bash
bash uninstall.sh
```

This calls `debloat-brave --reset --yes` to restore Brave defaults, then removes the binary from `/usr/local/bin`.

To restore a single key manually:

```bash
defaults delete com.brave.Browser BraveRewardsDisabled
```

## FAQ

**Do I need to quit Brave first?**
Yes. The tool warns you. Some keys are read only at launch.

**Will this break Brave updates or my profile?**
No. We only flip documented policy keys. The binary, profile data (bookmarks, passwords, history), and Sparkle updater are not touched.

**Does this work on Brave Beta / Nightly?**
Not yet. v1 targets the release channel (`com.brave.Browser`). Channel support is on the v2 list.

**Why Bash and not a binary?**
Inspectability. Anyone can `cat debloat-brave.sh` before running it. No build step, no dependencies, no surprise.

**Does this conflict with [`slimbrave-macos`](https://github.com/vladandrei51/slimbrave-macos)?**
Same plist namespace, so running both writes to the same keys. Pick one.

**Can I run it in CI / unattended?**
Yes. `debloat-brave --quick --yes` runs without prompts. Use `--dry-run` first to confirm the plan.

## Roadmap (v2)

* Homebrew tap (`brew install valetivivek/debloat-brave/debloat-brave`)
* Per-channel support (Beta / Nightly / Dev)
* Profile JSON tweaks (`Preferences` file)
* Optional disable of `BraveSoftwareUpdate` launchd agent (with a very loud warning)
* Custom DoH template input

## Contributing

PRs welcome. Please run `shellcheck debloat-brave.sh install.sh uninstall.sh` before opening one. Add new keys to the `CAT_*` arrays in `debloat-brave.sh`, that's the single source of truth.

## License

MIT, see [LICENSE](./LICENSE).
