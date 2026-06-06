<#
.SYNOPSIS
    CIS Microsoft Windows benchmark score -- fast, opinionated, ~30 checks.
.DESCRIPTION
    A pragmatic subset of the CIS Microsoft Windows 10/11 Enterprise
    Benchmark. We test the ~30 controls that catch 80% of real-world
    config drift on workstations. Each control has a CIS reference ID,
    weight, current value, and remediation pointer.

    NOT a substitute for the full benchmark -- but gets you a usable
    score in 10 seconds instead of a 30-minute CIS-CAT scan.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$AsJson)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$checks = New-Object System.Collections.Generic.List[pscustomobject]
function Add($Id,$Name,[bool]$Pass,$Detail,$Fix,[int]$Weight=1){
    $checks.Add([pscustomobject]@{
        Id=$Id; Name=$Name; Pass=$Pass; Detail="$Detail"; Fix=$Fix; Weight=$Weight
    })
}
function GetReg($Path,$Name) {
    try { (Get-ItemProperty $Path -Name $Name -ErrorAction Stop).$Name } catch { $null }
}

# 1.1.1 Account lockout duration
$dur = (net accounts | Select-String 'Lockout duration').ToString() -replace '.*:\s*'
Add '1.1.1' 'Account lockout duration >= 15 min' ([int]($dur -replace '\D','') -ge 15) "Duration: $dur min" 'net accounts /lockoutduration:15' 2

# 1.1.2 Account lockout threshold
$thr = (net accounts | Select-String 'Lockout threshold').ToString() -replace '.*:\s*'
$thrN = if ($thr -match 'Never') { 0 } else { [int]($thr -replace '\D','') }
Add '1.1.2' 'Lockout threshold between 1 and 10' ($thrN -gt 0 -and $thrN -le 10) "Threshold: $thr" 'net accounts /lockoutthreshold:5' 2

# 2.3.1.1 Built-in admin disabled
$admin = Get-LocalUser -SID 'S-1-5-21-*-500' -ErrorAction SilentlyContinue
if ($admin) {
    Add '2.3.1.1' 'Built-in Administrator account disabled' (-not $admin.Enabled) "Enabled=$($admin.Enabled)" 'Disable-LocalUser -Name "Administrator"' 3
}

# 2.3.1.5 Guest disabled
$guest = Get-LocalUser -Name 'Guest' -ErrorAction SilentlyContinue
if ($guest) {
    Add '2.3.1.5' 'Guest account disabled' (-not $guest.Enabled) "Enabled=$($guest.Enabled)" 'Disable-LocalUser Guest' 3
}

# 2.3.2.1 Audit Force Subcategory
$forceSub = GetReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'SCENoApplyLegacyAuditPolicy'
Add '2.3.2.1' 'Force audit subcategory enabled' ($forceSub -eq 1) "SCENoApplyLegacyAuditPolicy=$forceSub" 'Set to 1' 1

# 2.3.4.1 Restrict CD-ROM access
$cd = GetReg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' 'AllocateCDRoms'
Add '2.3.4.1' 'Restrict CD-ROM to logged on user' ($cd -eq '1') "AllocateCDRoms=$cd" 'Set to 1' 1

# 2.3.6.1 Encrypt sec channel data
$enc = GetReg 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters' 'RequireSignOrSeal'
Add '2.3.6.1' 'Domain member: digitally encrypt secure channel data' ($enc -eq 1) "RequireSignOrSeal=$enc" 'Set to 1' 2

# 2.3.7.1 Don't display last user
$last = GetReg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DontDisplayLastUserName'
Add '2.3.7.1' 'Do not display last signed-in user' ($last -eq 1) "DontDisplayLastUserName=$last" 'Set to 1' 1

# 2.3.7.3 Smart card removal behavior
$sc = GetReg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' 'ScRemoveOption'
Add '2.3.7.3' 'Smart card removal locks workstation' ($sc -in '1','2','3') "ScRemoveOption=$sc" 'Set to 1' 1

# 2.3.8.1 Microsoft network client: Always digitally sign
$cliSign = GetReg 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' 'RequireSecuritySignature'
Add '2.3.8.1' 'SMB client always digitally sign' ($cliSign -eq 1) "RequireSecuritySignature=$cliSign" 'Set to 1' 2

# 2.3.9.1 SMB server: Always digitally sign
$srvSign = GetReg 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'RequireSecuritySignature'
Add '2.3.9.1' 'SMB server always digitally sign' ($srvSign -eq 1) "RequireSecuritySignature=$srvSign" 'Set to 1' 2

# 2.3.10.5 Restrict anonymous access to Named Pipes
$rp = GetReg 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'RestrictNullSessAccess'
Add '2.3.10.5' 'Restrict null-session named pipes' ($rp -eq 1) "RestrictNullSessAccess=$rp" 'Set to 1' 1

# 2.3.11.1 Allow Local System NULL session fallback
$nullFB = GetReg 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'AllowNullSessionFallback'
Add '2.3.11.1' 'No NULL session fallback' ($nullFB -eq 0 -or $null -eq $nullFB) "AllowNullSessionFallback=$nullFB" 'Set to 0' 2

# 2.3.11.5 Min session security NTLM SSP client
$ntlmCli = GetReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0' 'NTLMMinClientSec'
Add '2.3.11.5' 'NTLM minimum client security >= NTLMv2+128 bit' ($ntlmCli -ge 537395200) "NTLMMinClientSec=$ntlmCli" 'Set to 537395200' 2

# 9.1.x Firewall on
$fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue
$allFw = ($fw | Where-Object { -not $_.Enabled }).Count -eq 0
Add '9.x' 'Windows Firewall enabled on all profiles' $allFw (($fw | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ',') 'Set-NetFirewallProfile -All -Enabled True' 3

# 18.3.1 LAPS / LSA Protection
$ppl = GetReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPL'
Add '18.3.1' 'LSA Protection (RunAsPPL) >= 1' ($ppl -ge 1) "RunAsPPL=$ppl" 'Set to 1 + reboot' 3

# 18.8.4.1 Audit Account Lockout
# Not easily readable from registry -- skip.

# 18.9.x Defender ASR
if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
    $mp = Get-MpPreference
    Add 'D.1' 'Defender PUA protection enabled' ($mp.PUAProtection -ne 0) "PUAProtection=$($mp.PUAProtection)" 'Set-MpPreference -PUAProtection Enabled' 1
    Add 'D.2' 'Defender Network protection enabled' ($mp.EnableNetworkProtection -ne 0) "EnableNetworkProtection=$($mp.EnableNetworkProtection)" 'Set-MpPreference -EnableNetworkProtection Enabled' 1
    Add 'D.3' 'Defender Controlled Folder Access' ($mp.EnableControlledFolderAccess -ne 0) "EnableControlledFolderAccess=$($mp.EnableControlledFolderAccess)" 'Set-MpPreference -EnableControlledFolderAccess Enabled' 1
    Add 'D.4' 'Cloud protection enabled' ($mp.MAPSReporting -ne 0) "MAPSReporting=$($mp.MAPSReporting)" 'Set-MpPreference -MAPSReporting Advanced' 1
}

# 18.10.x BitLocker on OS drive
try {
    $os = Get-BitLockerVolume | Where-Object VolumeType -eq 'OperatingSystem' | Select-Object -First 1
    Add 'BL.1' 'BitLocker on OS drive' ("$($os.ProtectionStatus)" -eq 'On') "ProtectionStatus=$($os.ProtectionStatus)" 'manage-bde -on C:' 3
} catch { Add 'BL.1' 'BitLocker available' $false 'unavailable' 'Install BitLocker feature' 3 }

# SMBv1 disabled
$smb1 = (Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue).State
Add 'SMB.1' 'SMBv1 disabled' ($smb1 -ne 'Enabled') "State=$smb1" 'Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol' 3

# Macro signing - if Office is present, check VBAWarnings
$macroKey = 'HKCU:\Software\Microsoft\Office\16.0\Word\Security'
if (Test-Path $macroKey) {
    $vw = GetReg $macroKey 'VBAWarnings'
    Add 'M.1' 'Word macro security: disable except signed (4) or all (3)' ($vw -in 3,4) "VBAWarnings=$vw" 'Set VBAWarnings=4' 1
}

$max = ($checks | Measure-Object Weight -Sum).Sum
$got = ($checks | Where-Object Pass | Measure-Object Weight -Sum).Sum
$pct = if ($max) { [math]::Round(($got/$max) * 100) } else { 0 }
$failed = @($checks | Where-Object { -not $_.Pass })

$status = if ($pct -ge 85) { 'Success' } elseif ($pct -ge 65) { 'Warning' } else { 'Failure' }
$result = New-MSPResult `
    -Tool 'Get-CISBenchmarkScore' `
    -Status $status `
    -Summary "CIS subset score: $pct / 100 ($($checks.Count - $failed.Count) / $($checks.Count) controls passed)" `
    -Data @{ Score = $pct; Total = $checks.Count; Failed = $failed; AllChecks = $checks.ToArray() } `
    -Metrics @{ Score = $pct; ControlsTotal = $checks.Count; ControlsFailed = $failed.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Security')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
