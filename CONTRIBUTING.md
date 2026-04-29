# Contributing

## Adding a new toggle

Edit the `CAT_*` arrays in `debloat-brave.sh` and the `$Settings` registry in `debloat-brave.ps1`. The macOS entry format is `key|type|debloat_value|default_value|label`; the Windows entry should use the same key, values, label, and category.

## Testing locally

Run `shellcheck debloat-brave.sh install.sh uninstall.sh` and fix any warnings. Then run `debloat-brave --dry-run` and confirm the printed commands look correct. Run `debloat-brave --view` and confirm managed keys and current state read as expected. Exercise the Nexus dashboard and configuration matrix if you change interactive code.

For Windows changes, run these from PowerShell:

```powershell
.\debloat-brave.ps1 -DryRun -Quick -Yes
.\debloat-brave.ps1 -DryRun -Reset -Yes
.\debloat-brave.ps1 -View
```

## Pull requests

`shellcheck debloat-brave.sh install.sh uninstall.sh` must print zero warnings before you open a PR. CI will run the same check, plus PowerShell syntax and dry-run smoke checks.

## Linux JSON (v2) convention

Each `CAT_*` key is a Chromium policy name. A future v2 can ship a JSON file at `/etc/brave/policies/managed/debloat-brave.json`. In that file, set boolean `true` to disable a feature that the macOS `defaults` key disables when set to a debloat value.
