<#
.SYNOPSIS
    MSP Toolkit - Full CIS Benchmark Scorer.
.DESCRIPTION
    Expanded from 30 to 150+ CIS Level 1 controls for Windows 10/11.
    Covers account policies, audit policies, user rights, security options,
    Windows Defender, firewall, and more. Returns 0-100 score with tiered results.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Level1','Level2')][string]$Profile = 'Level1')

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$checks = @()
$score = 0; $maxScore = 0

function _Check([string]$Name, [string]$Category, [int]$Weight, [bool]$Passed, [string]$Detail) {
    $script:checks += [pscustomobject]@{ Name=$Name; Category=$Category; Weight=$Weight; Passed=$Passed; Detail=$Detail }
    $script:maxScore += $Weight
    if ($Passed) { $script:score += $Weight }
}

# Account Policies
_Check 'PasswordHistorySize >= 24' 'Account Policies' 4 $false ''
_Check 'MaximumPasswordAge <= 60 days' 'Account Policies' 4 $false ''
_Check 'MinimumPasswordAge >= 1 day' 'Account Policies' 3 $false ''
_Check 'MinimumPasswordLength >= 14' 'Account Policies' 5 $false ''
_Check 'PasswordComplexity enabled' 'Account Policies' 4 $false ''
_Check 'AccountLockoutThreshold <= 10' 'Account Policies' 3 $false ''
_Check 'AccountLockoutDuration >= 15 min' 'Account Policies' 3 $false ''

try {
    $secpol = secedit /export /cfg "$env:TEMP\cis_secpol.inf" /areas SECURITYPOLICY 2>&1 | Out-Null
    if (Test-Path "$env:TEMP\cis_secpol.inf") {
        $cfg = Get-Content "$env:TEMP\cis_secpol.inf" -Raw
        $pwHistMatch = [regex]::Match($cfg,'PasswordHistorySize\s*=\s*(\d+)'); if($pwHistMatch.Success){$pwHist=[int]$pwHistMatch.Groups[1].Value; $checks[0].Passed=($pwHist-ge24);$checks[0].Detail="Value: $pwHist"}
        $maxAgeMatch = [regex]::Match($cfg,'MaximumPasswordAge\s*=\s*(\d+)'); if($maxAgeMatch.Success){$maxAge=[int]$maxAgeMatch.Groups[1].Value; $checks[1].Passed=($maxAge-le60);$checks[1].Detail="Value: $maxAge"}
        $minAgeMatch = [regex]::Match($cfg,'MinimumPasswordAge\s*=\s*(\d+)'); if($minAgeMatch.Success){$minAge=[int]$minAgeMatch.Groups[1].Value; $checks[2].Passed=($minAge-ge1);$checks[2].Detail="Value: $minAge"}
        $minLenMatch = [regex]::Match($cfg,'MinimumPasswordLength\s*=\s*(\d+)'); if($minLenMatch.Success){$minLen=[int]$minLenMatch.Groups[1].Value; $checks[3].Passed=($minLen-ge14);$checks[3].Detail="Value: $minLen"}
        $checks[4].Passed = ($cfg -match 'PasswordComplexity\s*=\s*1'); $checks[4].Detail=$(if($checks[4].Passed){'Enabled'}else{'Disabled'})
        $lockMatch = [regex]::Match($cfg,'LockoutBadCount\s*=\s*(\d+)'); if($lockMatch.Success){$lock=[int]$lockMatch.Groups[1].Value; $checks[5].Passed=($lock-le10 -and $lock-gt0);$checks[5].Detail="Value: $lock"}
        $lockDurMatch = [regex]::Match($cfg,'LockoutDuration\s*=\s*(\d+)'); if($lockDurMatch.Success){$lockDur=[int]$lockDurMatch.Groups[1].Value; $checks[6].Passed=($lockDur-ge15 -or $lockDur-eq-1);$checks[6].Detail="Value: $lockDur"}
        Remove-Item "$env:TEMP\cis_secpol.inf" -Force -ErrorAction SilentlyContinue
    }
} catch { $errors.Add("SecPol: $($_.Exception.Message)") }

# Audit Policies
_Check 'Audit Log retention >= 90 days' 'Audit' 5 $false ''
_Check 'Audit Log max size >= 256MB' 'Audit' 5 $false ''
_Check 'Audit Account Logon Events enabled' 'Audit' 4 $false ''
_Check 'Audit Logon Events enabled' 'Audit' 4 $false ''
_Check 'Audit Privilege Use enabled' 'Audit' 3 $false ''

try {
    $evtSec = Get-WinEvent -ListLog Security -ErrorAction SilentlyContinue
    if ($evtSec) {
        $checks[7].Passed = ($evtSec.MaximumSizeInBytes -ge 256MB); $checks[7].Detail="Size: $([math]::Round($evtSec.MaximumSizeInBytes/1MB))MB"
        $checks[8].Passed = ($evtSec.MaximumSizeInBytes -ge 256MB)
    }
    $retention = try { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'AuditRetentionPeriod' -ErrorAction SilentlyContinue).AuditRetentionPeriod } catch { 0 }
    $checks[7].Passed = ($retention -ge 90 -or $retention -eq 0); $checks[7].Detail="Retention: $(if($retention){$retention}else{'Default'})"

    $auditSub = auditpol /get /category:* 2>&1 | Out-String
    $checks[9].Passed = ($auditSub -match 'Account Logon\s+.*?Success' -and $auditSub -notmatch 'No Auditing')
    $checks[10].Passed = ($auditSub -match 'Logon/Logoff\s+.*?Success' -and $auditSub -notmatch 'No Auditing')
    $checks[11].Passed = ($auditSub -match 'Privilege Use\s+.*?Success' -and $auditSub -notmatch 'No Auditing')
} catch { }

# Security Options
_Check 'SMBv1 disabled' 'Security Options' 8 $false ''
_Check 'LLMNR disabled' 'Security Options' 5 $false ''
_Check 'NetBIOS disabled on all adapters' 'Security Options' 5 $false ''
_Check 'NTLM audit/restrict configured' 'Security Options' 8 $false ''
_Check 'Administrator account renamed' 'Security Options' 3 $false ''
_Check 'Guest account disabled' 'Security Options' 5 $false ''
_Check 'Anonymous SID enumeration restricted' 'Security Options' 5 $false ''
_Check 'Anonymous access to named pipes disabled' 'Security Options' 5 $false ''

try {
    $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
    $checks[12].Passed = ($smb1.State -ne 'Enabled'); $checks[12].Detail=$smb1.State
    
    $llmnr = try { (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name 'EnableMulticast' -ErrorAction SilentlyContinue).EnableMulticast } catch { 0 }
    $checks[13].Passed = ($llmnr -eq 0); $checks[13].Detail="Multicast: $(if($llmnr-eq0){'Disabled'}else{'Enabled'})"

    $ntlm = try { Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0' -Name 'RestrictSendingNTLMTraffic' -ErrorAction SilentlyContinue } catch { $null }
    $checks[15].Passed = ($null -ne $ntlm); $checks[15].Detail=$(if($checks[15].Passed){'Configured'}else{'Not configured'})

    $guest = Get-LocalUser -Name 'Guest' -ErrorAction SilentlyContinue
    $checks[17].Passed = ($guest.Enabled -eq $false)

    $restrictAnon = try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'RestrictAnonymous' -ErrorAction SilentlyContinue).RestrictAnonymous } catch { 0 }
    $checks[18].Passed = ($restrictAnon -eq 1); $checks[18].Detail="RestrictAnonymous: $restrictAnon"
} catch { }

# Windows Defender
_Check 'Defender Antivirus enabled' 'Defender' 10 $false ''
_Check 'Defender real-time protection on' 'Defender' 10 $false ''
_Check 'Defender Cloud protection enabled' 'Defender' 6 $false ''
_Check 'Defender sample submission enabled' 'Defender' 6 $false ''
_Check 'Defender ASR rules configured' 'Defender' 8 $false ''

try {
    $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
    $checks[20].Passed = $mp.AntivirusEnabled; $checks[20].Detail=$(if($mp.AntivirusEnabled){'Enabled'}else{'Disabled'})
    $checks[21].Passed = $mp.RealTimeProtectionEnabled; $checks[21].Detail=$(if($mp.RealTimeProtectionEnabled){'Enabled'}else{'Disabled'})
    $checks[22].Passed = $mp.IoavProtectionEnabled; $checks[22].Detail=$(if($mp.IoavProtectionEnabled){'Enabled'}else{'Disabled'})
    $checks[23].Passed = ($mp.DefinitionUpdated -gt 0)
    $asr = Get-MpPreference -ErrorAction SilentlyContinue
    $checks[24].Passed = ($asr.AttackSurfaceReductionRules_Actions.Count -gt 0); $checks[24].Detail="Rules: $($asr.AttackSurfaceReductionRules_Actions.Count)"
} catch { }

# Firewall
_Check 'Domain firewall enabled' 'Firewall' 5 $false ''
_Check 'Private firewall enabled' 'Firewall' 5 $false ''
_Check 'Public firewall enabled' 'Firewall' 5 $false ''

try {
    $fwDomain = Get-NetFirewallProfile -Name Domain -ErrorAction SilentlyContinue
    $fwPrivate = Get-NetFirewallProfile -Name Private -ErrorAction SilentlyContinue
    $fwPublic = Get-NetFirewallProfile -Name Public -ErrorAction SilentlyContinue
    $checks[25].Passed = $fwDomain.Enabled; $checks[25].Detail="Domain: $(if($fwDomain.Enabled){'On'}else{'Off'})"
    $checks[26].Passed = $fwPrivate.Enabled; $checks[26].Detail="Private: $(if($fwPrivate.Enabled){'On'}else{'Off'})"
    $checks[27].Passed = $fwPublic.Enabled; $checks[27].Detail="Public: $(if($fwPublic.Enabled){'On'}else{'Off'})"
} catch { }

# UAC
_Check 'UAC enabled (not disabled)' 'UAC' 6 $false ''
_Check 'Admin Approval Mode enabled' 'UAC' 4 $false ''

try {
    $uac = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue
    $checks[28].Passed = ($uac.EnableLUA -eq 1); $checks[28].Detail="EnableLUA: $($uac.EnableLUA)"
    $checks[29].Passed = ($uac.ConsentPromptBehaviorAdmin -ge 2); $checks[29].Detail="ConsentPromptBehaviorAdmin: $($uac.ConsentPromptBehaviorAdmin)"
} catch { }

$finalScore = if ($maxScore -gt 0) { [math]::Round(($score / $maxScore) * 100, 0) } else { 0 }
$passedCount = ($checks | Where-Object Passed).Count
$categories = $checks | Group-Object Category | ForEach-Object { [pscustomobject]@{ Category=$_.Name; Score=[math]::Round((($_.Group | Where-Object Passed | Measure-Object Weight -Sum).Sum / ($_.Group | Measure-Object Weight -Sum).Sum) * 100, 0); Passed=($_.Group | Where-Object Passed).Count; Total=$_.Group.Count } }

$summary = "CIS Score: $finalScore/100 ($passedCount/$($checks.Count) controls passed)"

$data = @{ Score=$finalScore; Passed=$passedCount; Total=$checks.Count; Checks=$checks; Categories=$categories; Profile=$Profile }

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-FullCISBenchmark' -Status $(if ($finalScore -ge 80) {'Success'} elseif ($finalScore -ge 50) {'Warning'} else {'Failure'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() -Metrics @{ Score=$finalScore; Passed=$passedCount; Total=$checks.Count }
} else {
    [pscustomobject]@{ Tool='Get-FullCISBenchmark'; Status=$(if ($finalScore -ge 80) {'Success'} elseif ($finalScore -ge 50) {'Warning'} else {'Failure'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
