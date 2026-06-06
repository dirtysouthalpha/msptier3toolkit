<#
.SYNOPSIS
    MSP Toolkit - macOS Startup Health Check.
.DESCRIPTION
    Audits LaunchAgents, LaunchDaemons, login items, kernel extensions,
    and startup items for anomalies and health.
#>
#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }

function _Run { param($c,$a,$t=15) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ LaunchDaemons=@(); LaunchAgents=@(); LoginItems=@(); KernelExtensions=@(); BrokenItems=@() }

# --- LaunchDaemons ---
try {
    $daemons = Get-ChildItem -Path '/Library/LaunchDaemons','/System/Library/LaunchDaemons' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $info = _Run 'launchctl' @('print',"system/$($_.BaseName)") 3
            $status = if ($info -match 'state\s*=\s*(\S+)') { $Matches[1] } else { 'unknown' }
            $pid = if ($info -match 'pid\s*=\s*(\d+)') { $Matches[1] } else { '' }
            [pscustomobject]@{ Name=$_.Name; Path=$_.FullName; Status=$status; PID=$pid }
        } catch { [pscustomobject]@{ Name=$_.Name; Path=$_.FullName; Status='error'; PID='' } }
    }
    $data.LaunchDaemons = @($daemons)
} catch { $errors.Add("LaunchDaemons: $($_.Exception.Message)") }

# --- LaunchAgents ---
try {
    $agents = Get-ChildItem -Path '/Library/LaunchAgents','/System/Library/LaunchAgents' -ErrorAction SilentlyContinue
    # Also user LaunchAgents
    $users = Get-ChildItem '/Users' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^\.|Shared|Deleted' }
    foreach ($u in $users) {
        $agentPath = "/Users/$($u.Name)/Library/LaunchAgents"
        if (Test-Path $agentPath) {
            $agents += Get-ChildItem $agentPath -ErrorAction SilentlyContinue
        }
    }
    $data.LaunchAgents = @($agents | ForEach-Object {
        [pscustomobject]@{ Name=$_.Name; Path=$_.FullName }
    })
} catch { $errors.Add("LaunchAgents: $($_.Exception.Message)") }

# --- Login Items ---
try {
    foreach ($u in $users) {
        $loginItems = _Run 'osascript' @('-e',"tell application `"System Events`" to get the name of every login item") 5
        if ($loginItems.Trim()) {
            $data.LoginItems += [pscustomobject]@{ User=$u.Name; Items=($loginItems.Trim() -split ', ') }
        }
    }
} catch { $errors.Add("LoginItems: $($_.Exception.Message)") }

# --- Kernel Extensions ---
try {
    $kexts = _Run 'kextstat' @() 10
    $lines = $kexts -split "`n" | Select-Object -Skip 1
    foreach ($line in $lines) {
        if ($line -match '^\s*\d+\s+\d+\s+0x[a-f0-9]+\s+0x[a-f0-9]+\s+(.+)\((\d+\.\d+\.?\d*)\)') {
            $data.KernelExtensions += [pscustomobject]@{ Name=$Matches[1].Trim(); Version=$Matches[2] }
        }
    }
} catch { $errors.Add("KernelExtensions: $($_.Exception.Message)") }

# --- Broken/Orphaned plists ---
try {
    $allPlists = @($data.LaunchDaemons) + @($data.LaunchAgents)
    foreach ($plist in $allPlists) {
        try {
            $xmlTest = [xml](_Run 'plutil' @('-convert','xml1','-o','-',$plist.Path) 3)
            if (-not $xmlTest.dict) { $data.BrokenItems += $plist.Name }
        } catch { $data.BrokenItems += $plist.Name }
    }
} catch { }

$totalItems = $data.LaunchDaemons.Count + $data.LaunchAgents.Count + $data.KernelExtensions.Count
$summary = "Daemons: $($data.LaunchDaemons.Count) | Agents: $($data.LaunchAgents.Count) | Kexts: $($data.KernelExtensions.Count) | Broken: $($data.BrokenItems.Count)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-MacStartupHealth' -Status $(if ($data.BrokenItems.Count -eq 0) {'Success'} else {'Warning'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ Daemons=$data.LaunchDaemons.Count; Agents=$data.LaunchAgents.Count; Kexts=$data.KernelExtensions.Count; Broken=$data.BrokenItems.Count }
} else {
    [pscustomobject]@{ Tool='Get-MacStartupHealth'; Status=$(if ($data.BrokenItems.Count -eq 0) {'Success'} else {'Warning'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
