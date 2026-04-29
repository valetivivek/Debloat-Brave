param(
  [switch]$Quick,
  [switch]$View,
  [switch]$Reset,
  [switch]$System,
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$Version,
  [switch]$Help
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.1.0'
$UserPolicyPath = 'HKCU:\Software\Policies\BraveSoftware\Brave'
$SystemPolicyPath = 'HKLM:\Software\Policies\BraveSoftware\Brave'

$Settings = @(
  [pscustomobject]@{ Key = 'BraveRewardsDisabled'; Type = 'DWord'; DebloatValue = 1; DefaultValue = 0; Label = 'Brave Rewards (BAT, ads)'; Category = 'Brave Features' }
  [pscustomobject]@{ Key = 'BraveWalletDisabled'; Type = 'DWord'; DebloatValue = 1; DefaultValue = 0; Label = 'Brave Wallet (crypto)'; Category = 'Brave Features' }
  [pscustomobject]@{ Key = 'BraveVPNDisabled'; Type = 'DWord'; DebloatValue = 1; DefaultValue = 0; Label = 'Brave VPN promo'; Category = 'Brave Features' }
  [pscustomobject]@{ Key = 'BraveAIChatEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Leo AI Chat sidebar'; Category = 'Brave Features' }
  [pscustomobject]@{ Key = 'TorDisabled'; Type = 'DWord'; DebloatValue = 1; DefaultValue = 0; Label = 'Tor private windows'; Category = 'Brave Features' }
  [pscustomobject]@{ Key = 'BraveTalkDisabled'; Type = 'DWord'; DebloatValue = 1; DefaultValue = 0; Label = 'Brave Talk video calls'; Category = 'Brave Features' }
  [pscustomobject]@{ Key = 'BraveNewsDisabled'; Type = 'DWord'; DebloatValue = 1; DefaultValue = 0; Label = 'Brave News on new tab'; Category = 'Brave Features' }
  [pscustomobject]@{ Key = 'BraveSyncDisabled'; Type = 'DWord'; DebloatValue = 1; DefaultValue = 0; Label = 'Sync chain'; Category = 'Brave Features' }
  [pscustomobject]@{ Key = 'BraveWeb3IPFSDisabled'; Type = 'DWord'; DebloatValue = 1; DefaultValue = 0; Label = 'IPFS gateway / Web3'; Category = 'Brave Features' }

  [pscustomobject]@{ Key = 'MetricsReportingEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Usage statistics reporting'; Category = 'Telemetry & Analytics' }
  [pscustomobject]@{ Key = 'BraveP3AEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Privacy-preserving analytics (P3A)'; Category = 'Telemetry & Analytics' }
  [pscustomobject]@{ Key = 'BraveStatsPingEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Daily stats ping'; Category = 'Telemetry & Analytics' }
  [pscustomobject]@{ Key = 'BraveWebDiscoveryEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Web Discovery Project'; Category = 'Telemetry & Analytics' }
  [pscustomobject]@{ Key = 'FeedbackSurveysEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'In-product surveys'; Category = 'Telemetry & Analytics' }
  [pscustomobject]@{ Key = 'UrlKeyedAnonymizedDataCollectionEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'URL-keyed data collection'; Category = 'Telemetry & Analytics' }

  [pscustomobject]@{ Key = 'PasswordManagerEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Built-in password manager'; Category = 'Privacy & Security' }
  [pscustomobject]@{ Key = 'AutofillAddressEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Address autofill'; Category = 'Privacy & Security' }
  [pscustomobject]@{ Key = 'AutofillCreditCardEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Credit card autofill'; Category = 'Privacy & Security' }
  [pscustomobject]@{ Key = 'SearchSuggestEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Search suggestions'; Category = 'Privacy & Security' }
  [pscustomobject]@{ Key = 'BlockThirdPartyCookies'; Type = 'DWord'; DebloatValue = 1; DefaultValue = 0; Label = 'Force-block 3rd-party cookies'; Category = 'Privacy & Security' }
  [pscustomobject]@{ Key = 'EnableDoNotTrack'; Type = 'DWord'; DebloatValue = 1; DefaultValue = 0; Label = 'Send Do-Not-Track header'; Category = 'Privacy & Security' }
  [pscustomobject]@{ Key = 'WebRtcIPHandling'; Type = 'String'; DebloatValue = 'disable_non_proxied_udp'; DefaultValue = 'default'; Label = 'WebRTC IP leak protection'; Category = 'Privacy & Security' }
  [pscustomobject]@{ Key = 'SafeBrowsingProtectionLevel'; Type = 'DWord'; DebloatValue = 1; DefaultValue = 2; Label = 'SafeBrowsing level (1=standard, 2=enhanced)'; Category = 'Privacy & Security' }

  [pscustomobject]@{ Key = 'BackgroundModeEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Run in background after close'; Category = 'Performance & Bloat' }
  [pscustomobject]@{ Key = 'MediaRecommendationsEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Media recommendations'; Category = 'Performance & Bloat' }
  [pscustomobject]@{ Key = 'ShoppingListEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Shopping list nag'; Category = 'Performance & Bloat' }
  [pscustomobject]@{ Key = 'TranslateEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Page translation prompt'; Category = 'Performance & Bloat' }
  [pscustomobject]@{ Key = 'SpellcheckEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Spellcheck'; Category = 'Performance & Bloat' }
  [pscustomobject]@{ Key = 'DefaultBrowserSettingEnabled'; Type = 'DWord'; DebloatValue = 0; DefaultValue = 1; Label = 'Default-browser nag'; Category = 'Performance & Bloat' }

  [pscustomobject]@{ Key = 'DnsOverHttpsMode'; Type = 'String'; DebloatValue = 'automatic'; DefaultValue = 'off'; Label = 'DNS-over-HTTPS mode'; Category = 'DNS' }
)

function Show-Usage {
  @"
debloat-brave.ps1 v$ScriptVersion - Windows Brave policy debloater

Usage: .\debloat-brave.ps1 [options]

Options:
  -Quick       Apply recommended preset
  -View        Show current policy values
  -Reset       Remove all managed policy keys
  -System      Use HKLM machine policy instead of HKCU user policy
  -DryRun      Print registry operations instead of executing
  -Yes         Assume yes to prompts
  -Version     Print version
  -Help        Print this help

Examples:
  .\debloat-brave.ps1 -DryRun -Quick -Yes
  .\debloat-brave.ps1 -Quick
  .\debloat-brave.ps1 -System -Quick
"@
}

function Get-PolicyPath {
  if ($System) {
    return $SystemPolicyPath
  }
  return $UserPolicyPath
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-CanWritePolicy {
  if ($System -and -not $DryRun -and -not (Test-IsAdministrator)) {
    throw 'System mode writes HKLM and must be run from an elevated PowerShell session.'
  }
}

function Get-CurrentValue {
  param([string]$Key)

  $path = Get-PolicyPath
  try {
    $item = Get-ItemProperty -Path $path -Name $Key -ErrorAction Stop
    return [pscustomobject]@{ IsSet = $true; Value = $item.$Key }
  } catch {
    return [pscustomobject]@{ IsSet = $false; Value = $null }
  }
}

function Convert-PolicyValue {
  param($Setting, $Value)

  if ($Setting.Type -eq 'DWord') {
    return [int]$Value
  }
  return [string]$Value
}

function Get-SettingState {
  param($Setting)

  $current = Get-CurrentValue -Key $Setting.Key
  if (-not $current.IsSet) {
    return 'DEFAULT'
  }

  $desired = Convert-PolicyValue -Setting $Setting -Value $Setting.DebloatValue
  if ([string]$current.Value -eq [string]$desired) {
    return 'DISABLED'
  }
  return 'FOREIGN'
}

function Set-DebloatPolicy {
  param($Setting)

  $path = Get-PolicyPath
  $value = Convert-PolicyValue -Setting $Setting -Value $Setting.DebloatValue
  if ($DryRun) {
    Write-Output "[dry-run] New-Item -Path '$path' -Force"
    Write-Output "[dry-run] New-ItemProperty -Path '$path' -Name '$($Setting.Key)' -PropertyType $($Setting.Type) -Value '$value' -Force"
    return
  }

  New-Item -Path $path -Force | Out-Null
  New-ItemProperty -Path $path -Name $Setting.Key -PropertyType $Setting.Type -Value $value -Force | Out-Null
}

function Remove-DebloatPolicy {
  param($Setting)

  $path = Get-PolicyPath
  if ($DryRun) {
    Write-Output "[dry-run] Remove-ItemProperty -Path '$path' -Name '$($Setting.Key)'"
    return
  }

  Remove-ItemProperty -Path $path -Name $Setting.Key -ErrorAction SilentlyContinue
}

function Confirm-Action {
  param([string]$Message)

  if ($Yes) {
    return $true
  }

  $answer = Read-Host "$Message [y/N]"
  return $answer -match '^[yY]$'
}

function Show-State {
  $path = Get-PolicyPath
  Write-Output "Policy path: $path"
  foreach ($category in ($Settings.Category | Select-Object -Unique)) {
    Write-Output ''
    Write-Output $category
    foreach ($setting in ($Settings | Where-Object { $_.Category -eq $category })) {
      $state = Get-SettingState -Setting $setting
      "{0,-9} {1,-42} {2}" -f $state, $setting.Label, $setting.Key
    }
  }
}

function Invoke-Quick {
  Assert-CanWritePolicy
  if (-not (Confirm-Action -Message "Apply recommended Brave debloat policies to $(Get-PolicyPath)?")) {
    Write-Output 'No changes made.'
    return
  }

  foreach ($setting in $Settings) {
    Set-DebloatPolicy -Setting $setting
  }
  Write-Output 'Applied recommended Brave policies. Relaunch Brave to see changes.'
}

function Invoke-Reset {
  Assert-CanWritePolicy
  if (-not (Confirm-Action -Message "Remove all Debloat Brave policy keys from $(Get-PolicyPath)?")) {
    Write-Output 'No changes made.'
    return
  }

  foreach ($setting in $Settings) {
    Remove-DebloatPolicy -Setting $setting
  }
  Write-Output 'Removed Debloat Brave policy keys. Relaunch Brave to see changes.'
}

function Show-Menu {
  while ($true) {
    Write-Output ''
    Write-Output "Debloat Brave Windows v$ScriptVersion"
    Write-Output "Policy scope: $(Get-PolicyPath)"
    Write-Output '1) Quick Debloat'
    Write-Output '2) View State'
    Write-Output '3) Reset Defaults'
    Write-Output '4) Quit'
    $choice = Read-Host 'Select'

    switch ($choice) {
      '1' { Invoke-Quick }
      '2' { Show-State }
      '3' { Invoke-Reset }
      '4' { return }
      default { Write-Output 'Choose 1, 2, 3, or 4.' }
    }
  }
}

if ($Help) {
  Show-Usage
  exit 0
}

if ($Version) {
  Write-Output "debloat-brave.ps1 v$ScriptVersion"
  exit 0
}

if ($View) {
  Show-State
  exit 0
}

if ($Reset) {
  Invoke-Reset
  exit 0
}

if ($Quick) {
  Invoke-Quick
  exit 0
}

Show-Menu
