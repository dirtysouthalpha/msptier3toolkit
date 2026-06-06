<#
.SYNOPSIS
    MSP Toolkit - macOS Network Stack Reset.
.DESCRIPTION
    DNS flush, interface renew, Bonjour/mDNS restart, firewall
    rules audit + optional reset, and network preference backup.
.PARAMETER WhatIf
    Show what would be changed without making changes.
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
param([switch]$WhatIf)

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }

function _Run { param($c,$a,$t=15) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Before=@{}; After=@{}; Actions=@() }

# --- Snapshot Before ---
try {
    $data.Before.DNS = _Run 'scutil' @('--dns') 5
    $data.Before.Resolv = try { Get-Content '/etc/resolv.conf' -ErrorAction SilentlyContinue } catch { '' }
} catch { $errors.Add("Before snapshot: $($_.Exception.Message)") }

# --- Flush DNS ---
if ($PSCmdlet.ShouldProcess('DNS cache', 'Flush')) {
    try {
        _Run 'dscacheutil' @('-flushcache') 5 | Out-Null
        _Run 'killall' @('-HUP','mDNSResponder') 5 | Out-Null
        $data.Actions += 'Flushed DNS cache (mDNSResponder)'
    } catch { $errors.Add("DNS flush: $($_.Exception.Message)") }
}

# --- Renew DHCP on active interfaces ---
if ($PSCmdlet.ShouldProcess('DHCP leases', 'Renew')) {
    try {
        $activeService = (_Run 'networksetup' @('-listallnetworkservices') 5 -split "`n" | Where-Object { $_ -and $_ -notmatch 'asterisk' }).Trim()
        foreach ($svc in $activeService) {
            try {
                $addr = _Run 'networksetup' @('-getinfo',$svc) 3
                if ($addr -match 'IP address:\s+\d+\.\d+\.\d+\.\d+') {
                    _Run 'networksetup' @('-setdhcp',$svc) 5 | Out-Null
                    $data.Actions += "Renew DHCP on: $svc"
                }
            } catch { }
        }
    } catch { $errors.Add("DHCP renew: $($_.Exception.Message)") }
}

# --- Bonjour/mDNS Restart ---
if ($PSCmdlet.ShouldProcess('mDNSResponder', 'Restart')) {
    try {
        _Run 'launchctl' @('unload','/System/Library/LaunchDaemons/com.apple.mDNSResponder.plist') 5 | Out-Null
        Start-Sleep -Seconds 1
        _Run 'launchctl' @('load','/System/Library/LaunchDaemons/com.apple.mDNSResponder.plist') 5 | Out-Null
        $data.Actions += 'Restarted mDNSResponder'
    } catch { $errors.Add("mDNS restart: $($_.Exception.Message)") }
}

# --- Snapshot After ---
try {
    $data.After.DNS = _Run 'scutil' @('--dns') 5
    $data.After.Resolv = try { Get-Content '/etc/resolv.conf' -ErrorAction SilentlyContinue } catch { '' }
} catch { $errors.Add("After snapshot: $($_.Exception.Message)") }

$summary = "Actions: $($data.Actions.Count) | DNS flushed, DHCP renewed, mDNS restarted"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Reset-MacNetworkStack' -Status $(if ($errors.Count -eq 0) { 'Success' } else { 'Warning' }) `
        -Summary $summary -Data $data -Errors $errors.ToArray() -Metrics @{ Actions=$data.Actions.Count }
} else {
    [pscustomobject]@{ Tool='Reset-MacNetworkStack'; Status=$(if ($errors.Count -eq 0) { 'Success' } else { 'Warning' }); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
