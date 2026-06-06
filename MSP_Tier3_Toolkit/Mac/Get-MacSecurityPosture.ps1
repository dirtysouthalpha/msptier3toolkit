<#
.SYNOPSIS
    MSP Toolkit - macOS Security Posture Score.
.DESCRIPTION
    Hardening score for macOS: Gatekeeper, SIP, XProtect, firewall,
    FileVault, SSH, automatic updates, screen lock, and more.
    Returns a 0-100 score with per-check detail.
#>
#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }

function _Run { param($c,$a,$t=15) & $c @$a 2>&1 | Out-String }
$errors = [System.Collections.Generic.List[string]]::new()
$checks = @()
$score = 0; $maxScore = 0

function _Check($Name, $Weight, $Passed, $Detail) {
    $global:checks += [pscustomobject]@{ Name=$Name; Weight=$Weight; Passed=$Passed; Detail=$Detail }
    $global:maxScore += $Weight
    if ($Passed) { $global:score += $Weight }
}

# 1. Gatekeeper (weight: 10)
try { $gk = _Run 'spctl' @('--status') 5; _Check 'Gatekeeper' 10 ($gk -match 'assessments enabled') ($gk.Trim()) } catch { _Check 'Gatekeeper' 10 $false $_.Exception.Message }

# 2. SIP (System Integrity Protection) (weight: 15)
try { $sip = _Run 'csrutil' @('status') 5; _Check 'SIP' 15 ($sip -match 'enabled') ($sip.Trim()) } catch { _Check 'SIP' 15 $false $_.Exception.Message }

# 3. Firewall (weight: 10)
try { $fw = _Run '/usr/libexec/ApplicationFirewall/socketfilterfw' @('--getglobalstate') 5; _Check 'Application Firewall' 10 ($fw -match 'enabled') ($fw.Trim()) } catch { _Check 'Application Firewall' 10 $false $_.Exception.Message }

# 4. FileVault (weight: 15)
try { $fv = _Run 'fdesetup' @('status') 10; _Check 'FileVault' 15 ($fv -match 'FileVault is On') ($fv.Trim()) } catch { _Check 'FileVault' 15 $false $_.Exception.Message }

# 5. XProtect / MRT (weight: 10)
try { $xp = _Run 'xprotect' @('version') 5 2>&1; _Check 'XProtect Active' 10 ($LASTEXITCODE -eq 0) ($xp.Trim()) } catch { _Check 'XProtect Active' 10 $false $_.Exception.Message }

# 6. Automatic Updates (weight: 8)
try { $su = _Run 'softwareupdate' @('--schedule') 5; _Check 'Auto Updates' 8 ($su -match 'on') ($su.Trim()) } catch { _Check 'Auto Updates' 8 $false $_.Exception.Message }

# 7. SSH disabled (weight: 5)
try { $ssh = _Run 'systemsetup' @('-getremotelogin') 5; _Check 'SSH Disabled' 5 ($ssh -match 'Off') ($ssh.Trim()) } catch { _Check 'SSH Disabled' 5 $false $_.Exception.Message }

# 8. Screen lock timeout (weight: 8)
try { $lock = _Run 'defaults' @('read','com.apple.screensaver','askForPassword') 5; _Check 'Screen Lock' 8 ($lock -match '1') $lock.Trim() } catch { _Check 'Screen Lock' 8 $false $_.Exception.Message }

# 9. Stealth mode (weight: 5)
try { $stealth = _Run '/usr/libexec/ApplicationFirewall/socketfilterfw' @('--getstealthmode') 5; _Check 'Stealth Mode' 5 ($stealth -match 'enabled') ($stealth.Trim()) } catch { _Check 'Stealth Mode' 5 $false $_.Exception.Message }

# 10. Guest account disabled (weight: 5)
try { $guest = _Run 'defaults' @('read','/Library/Preferences/com.apple.loginwindow','GuestEnabled') 5; _Check 'Guest Disabled' 5 ($guest -match '0' -or $guest -match 'does not exist') $guest.Trim() } catch { _Check 'Guest Disabled' 5 $false $_.Exception.Message }

# 11. Firmware password (weight: 5)
try { $fwp = _Run 'firmwarepasswd' @('-check') 5 2>&1; _Check 'Firmware Password' 5 ($fwp -match 'Yes') ($fwp.Trim()) } catch { _Check 'Firmware Password' 5 $false $_.Exception.Message }

# 12. Secure Boot (T2/Apple Silicon) (weight: 4)
try { $sb = _Run 'csrutil' @('authenticated-root','status') 5; _Check 'Authenticated Root' 4 ($sb -match 'enabled') ($sb.Trim()) } catch { _Check 'Authenticated Root' 4 $false $_.Exception.Message }

$finalScore = if ($maxScore -gt 0) { [math]::Round(($score / $maxScore) * 100, 0) } else { 0 }
$passedCount = ($checks | Where-Object Passed).Count
$summary = "macOS Security Score: $finalScore/100 ($passedCount/$($checks.Count) checks passed)"

$data = @{ Score=$finalScore; MaxScore=$maxScore; RawScore=$score; Checks=$checks; PassedCount=$passedCount; TotalChecks=$checks.Count }

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-MacSecurityPosture' -Status $(if ($finalScore -ge 80) {'Success'} elseif ($finalScore -ge 50) {'Warning'} else {'Failure'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ Score=$finalScore; Passed=$passedCount; Total=$checks.Count }
} else {
    [pscustomobject]@{ Tool='Get-MacSecurityPosture'; Status=$(if ($finalScore -ge 80) {'Success'} elseif ($finalScore -ge 50) {'Warning'} else {'Failure'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
