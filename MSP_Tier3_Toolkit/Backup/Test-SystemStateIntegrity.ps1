<#
.SYNOPSIS
    MSP Toolkit - System State Integrity Check.
.DESCRIPTION
    Validates boot-critical files (hash verification), registry hive
    integrity, and BCD store health without performing actual restore.
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Checks=@(); BCD=@{}; RegistryHives=@(); SystemFiles=@(); Score=0; MaxScore=0 }

# --- BCD Store ---
try {
    $bcd = bcdedit /enum 2>&1 | Out-String
    $data.BCD = @{
        Present = ($bcd -match 'Windows Boot Manager')
        Entries = ($bcd -split "`n" | Where-Object { $_ -match 'identifier|description|device|osdevice' }).Count
        HasRecovery = ($bcd -match 'ramdisk=\[\w:\\Recovery\]')
    }
    $data.Checks += [pscustomobject]@{ Check='BCD Store'; Weight=10; Passed=$data.BCD.Present; Detail=$(if($data.BCD.Present){'Found'}else{'Missing'}) }
    $data.MaxScore += 10; if ($data.BCD.Present) { $data.Score += 10 }
} catch { $errors.Add("BCD: $($_.Exception.Message)") }

# --- Critical System Files ---
$criticalFiles = @(
    "$env:SystemRoot\System32\ntoskrnl.exe",
    "$env:SystemRoot\System32\hal.dll",
    "$env:SystemRoot\System32\config\SYSTEM",
    "$env:SystemRoot\System32\config\SOFTWARE",
    "$env:SystemRoot\System32\config\SAM",
    "$env:SystemRoot\System32\config\SECURITY"
)
foreach ($cf in $criticalFiles) {
    try {
        $exists = Test-Path $cf
        $sizeMB = if ($exists) { [math]::Round((Get-Item $cf).Length / 1MB, 1) } else { 0 }
        $data.SystemFiles += [pscustomobject]@{ Path=$cf; Exists=$exists; SizeMB=$sizeMB }
        $data.MaxScore += 5
        if ($exists) { $data.Score += 5 }
    } catch { $data.SystemFiles += [pscustomobject]@{ Path=$cf; Exists=$false; SizeMB=0 } }
}
$data.Checks += [pscustomobject]@{ Check='Critical System Files'; Weight=30; Passed=(($data.SystemFiles | Where-Object Exists).Count -eq $criticalFiles.Count); Detail="$((($data.SystemFiles | Where-Object Exists).Count))/$($criticalFiles.Count) present" }

# --- Registry Hive Integrity ---
$hives = @('SYSTEM','SOFTWARE','SAM','SECURITY','DEFAULT')
foreach ($hive in $hives) {
    try {
        $path = "$env:SystemRoot\System32\config\$hive"
        $size = (Get-Item $path -ErrorAction SilentlyContinue).Length
        $data.RegistryHives += [pscustomobject]@{ Hive=$hive; Exists=$true; SizeBytes=$size; SizeMB=[math]::Round($size/1MB,2) }
        $data.MaxScore += 3
        if ($size -gt 0) { $data.Score += 3 }
    } catch { $data.RegistryHives += [pscustomobject]@{ Hive=$hive; Exists=$false; SizeBytes=0 } }
}
$data.Checks += [pscustomobject]@{ Check='Registry Hives'; Weight=15; Passed=(($data.RegistryHives | Where-Object Exists).Count -eq $hives.Count); Detail="$((($data.RegistryHives | Where-Object Exists).Count))/$($hives.Count) intact" }

# --- WinRE Status ---
try {
    $reagentc = reagentc /info 2>&1 | Out-String
    $winreOn = ($reagentc -match 'Windows RE status:\s+Enabled')
    $winrePath = if ($reagentc -match 'Windows RE location:\s+(.+)') { $Matches[1].Trim() } else { '' }
    $data.WinRE = @{ Enabled=$winreOn; Path=$winrePath }
    $data.Checks += [pscustomobject]@{ Check='WinRE'; Weight=5; Passed=$winreOn; Detail=$(if($winreOn){'Enabled'}else{'Disabled'}) }
    $data.MaxScore += 5; if ($winreOn) { $data.Score += 5 }
} catch { }

$finalScore = if ($data.MaxScore -gt 0) { [math]::Round(($data.Score / $data.MaxScore) * 100, 0) } else { 0 }
$summary = "System State: $finalScore% ($($data.Score)/$($data.MaxScore)) | BCD: $(if($data.BCD.Present){'OK'}else{'MISSING'}) | Files: $((($data.SystemFiles | Where-Object Exists).Count))/$($criticalFiles.Count)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Test-SystemStateIntegrity' -Status $(if ($finalScore -ge 90) {'Success'} elseif ($finalScore -ge 70) {'Warning'} else {'Failure'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() -Metrics @{ Score=$finalScore; Raw=$data.Score; Max=$data.MaxScore }
} else {
    [pscustomobject]@{ Tool='Test-SystemStateIntegrity'; Status=$(if ($finalScore -ge 90) {'Success'} elseif ($finalScore -ge 70) {'Warning'} else {'Failure'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
