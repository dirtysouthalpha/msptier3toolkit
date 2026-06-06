<#
.SYNOPSIS
    Single-pane security scorecard rolling up the most common MSP
    compliance checks into one 0-100 score.
.DESCRIPTION
    Each check is worth a defined weight; failing checks subtract. Output
    includes per-check pass/fail and the remediation hint so a Tier-2 can
    act on it without escalation.

    Checks:
      - BitLocker on OS drive
      - Defender real-time on, signatures < 7 days old
      - SmartScreen enabled
      - Firewall enabled on all profiles
      - Admin Approval Mode (UAC) on
      - Guest account disabled
      - LSA Protection (RunAsPPL) enabled
      - SMBv1 disabled
      - LLMNR disabled
      - NetBIOS over TCP disabled
      - Local password policy minimum length >= 14
      - Reboot pending (informational)

    Returns standard MSP result; status maps:
      Score >= 85: Success
      Score >= 65: Warning
      Else        : Failure
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$AsJson)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$checks = New-Object System.Collections.Generic.List[pscustomobject]
function Add-Check([string]$Name,[bool]$Pass,[int]$Weight,[string]$Detail,[string]$Fix) {
    $checks.Add([pscustomobject]@{ Name=$Name; Pass=$Pass; Weight=$Weight; Detail=$Detail; Fix=$Fix })
}

# BitLocker OS drive
try {
    $os = (Get-BitLockerVolume | Where-Object VolumeType -eq 'OperatingSystem' | Select-Object -First 1)
    Add-Check 'BitLocker OS drive on' ($os -and "$($os.ProtectionStatus)" -eq 'On') 15 "$($os.ProtectionStatus)" 'manage-bde -on C: -used'
} catch { Add-Check 'BitLocker OS drive on' $false 15 'unavailable' 'Install BitLocker feature.' }

# Defender
try {
    $d = Get-MpComputerStatus
    Add-Check 'Defender RealTime on'   ($d.RealTimeProtectionEnabled) 10 "RT=$($d.RealTimeProtectionEnabled)" 'Set-MpPreference -DisableRealtimeMonitoring $false'
    Add-Check 'Defender signatures fresh' ($d.AntivirusSignatureAge -le 7) 5 "AgeDays=$($d.AntivirusSignatureAge)" 'Update-MpSignature'
    Add-Check 'Tamper Protection on' ([bool]$d.IsTamperProtected) 5 "TP=$($d.IsTamperProtected)" 'Enable via Intune / Defender portal.'
} catch { Add-Check 'Defender available' $false 20 $_.Exception.Message 'Install/enable Defender.' }

# SmartScreen
try {
    $ss = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -ErrorAction SilentlyContinue).SmartScreenEnabled
    Add-Check 'SmartScreen enabled' ($ss -in 'Warn','Block','RequireAdmin') 5 "$ss" 'Set SmartScreenEnabled to RequireAdmin'
} catch { Add-Check 'SmartScreen enabled' $false 5 'n/a' 'Set SmartScreenEnabled' }

# Firewall
try {
    $fw = Get-NetFirewallProfile -ErrorAction Stop
    $allOn = ($fw | Where-Object { -not $_.Enabled }).Count -eq 0
    Add-Check 'Firewall on all profiles' $allOn 10 (($fw | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ',') 'Set-NetFirewallProfile -All -Enabled True'
} catch { Add-Check 'Firewall on all profiles' $false 10 $_.Exception.Message 'Enable firewall.' }

# UAC
try {
    $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction Stop).EnableLUA
    Add-Check 'UAC (EnableLUA) on' ($uac -eq 1) 5 "EnableLUA=$uac" 'Set EnableLUA=1, reboot.'
} catch { Add-Check 'UAC (EnableLUA) on' $false 5 'unknown' 'Set EnableLUA=1' }

# Guest disabled
try {
    $g = Get-LocalUser -Name 'Guest' -ErrorAction SilentlyContinue
    Add-Check 'Guest account disabled' ($g -and -not $g.Enabled) 5 "Enabled=$($g.Enabled)" 'Disable-LocalUser Guest'
} catch { Add-Check 'Guest account disabled' $true 5 'n/a' 'n/a' }

# LSA RunAsPPL
try {
    $ppl = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -ErrorAction Stop).RunAsPPL
    Add-Check 'LSA RunAsPPL on' ($ppl -ge 1) 5 "RunAsPPL=$ppl" 'Set RunAsPPL=1, reboot.'
} catch { Add-Check 'LSA RunAsPPL on' $false 5 'unset' 'Set RunAsPPL=1' }

# SMBv1
try {
    $smb1 = (Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue).State
    Add-Check 'SMBv1 disabled' ($smb1 -ne 'Enabled') 10 "State=$smb1" 'Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol'
} catch { Add-Check 'SMBv1 disabled' $true 10 'n/a' 'n/a' }

# LLMNR
try {
    $llmnr = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -ErrorAction SilentlyContinue).EnableMulticast
    Add-Check 'LLMNR disabled' ($llmnr -eq 0) 5 "EnableMulticast=$llmnr" 'Set EnableMulticast=0 via GPO'
} catch { Add-Check 'LLMNR disabled' $false 5 'unset' 'Set EnableMulticast=0' }

# NetBIOS over TCP
try {
    $nb = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE'
    $bad = @($nb | Where-Object { $_.TcpipNetbiosOptions -ne 2 })
    Add-Check 'NetBIOS over TCP disabled' ($bad.Count -eq 0) 5 "BadNICs=$($bad.Count)" 'Set NetBIOS = Disabled on each NIC (TcpipNetbiosOptions=2)'
} catch { Add-Check 'NetBIOS over TCP disabled' $false 5 $_.Exception.Message 'See KB' }

# Password length
try {
    $tmp = "$env:TEMP\secpol.cfg"
    & secedit /export /cfg $tmp /quiet | Out-Null
    $line = Get-Content $tmp | Where-Object { $_ -match 'MinimumPasswordLength' }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $len = if ($line -match '=\s*(\d+)') { [int]$matches[1] } else { 0 }
    Add-Check 'Min password length >= 14' ($len -ge 14) 5 "Len=$len" 'net accounts /minpwlen:14'
} catch { Add-Check 'Min password length >= 14' $false 5 'n/a' 'n/a' }

# Reboot pending -- informational, light penalty
$reboot = Test-MSPPendingReboot
Add-Check 'No pending reboot' (-not $reboot.PendingReboot) 5 ($reboot.Reasons -join ',') 'Reboot at next maintenance window.'

# Score
$maxScore = ($checks | Measure-Object Weight -Sum).Sum
$earned   = ($checks | Where-Object Pass | Measure-Object Weight -Sum).Sum
$score    = if ($maxScore) { [math]::Round(($earned / $maxScore) * 100) } else { 0 }

$status = if ($score -ge 85) { 'Success' } elseif ($score -ge 65) { 'Warning' } else { 'Failure' }

$result = New-MSPResult `
    -Tool 'Get-SecurityPostureScore' `
    -Status $status `
    -Summary "Score $score / 100 ($($checks | Where-Object Pass).Count / $($checks.Count) checks passed)." `
    -Data @{ Score = $score; Checks = $checks.ToArray() } `
    -Metrics @{ Score = $score; CheckCount = $checks.Count; Passed = ($checks | Where-Object Pass).Count }

[void](Save-MSPResult -Result $result -Subfolder 'Security')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
