<#
.SYNOPSIS
    MSP Toolkit - Restore Readiness Test.
.DESCRIPTION
    Simulates bare-metal restore readiness check: validates backup
    metadata integrity without performing actual restore operations.
    Checks WinRE, drivers, backup catalog.
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Checks=@(); Score=0; MaxScore=0; Ready=$false; Blockers=@() }

# 1. WinRE check
try {
    $reagentc = reagentc /info 2>&1 | Out-String
    $winreReady = ($reagentc -match 'Windows RE status:\s+Enabled' -and $reagentc -match 'Windows RE location:\s+.*:\\.*\\Recovery')
    $data.Checks += [pscustomobject]@{ Name='WinRE Enabled'; Passed=$winreReady; Detail=$(if($winreReady){'OK'}else{'WinRE disabled or not configured'}) }
    $data.MaxScore += 20; if ($winreReady) { $data.Score += 20 } else { $data.Blockers += 'WinRE not configured' }
} catch { $data.Checks += [pscustomobject]@{ Name='WinRE'; Passed=$false; Detail=$_.Exception.Message }; $data.Blockers += 'WinRE check failed' }

# 2. Backup catalog
try {
    $catalog = Get-WBCatalog -ErrorAction SilentlyContinue
    $catReady = ($null -ne $catalog)
    $data.Checks += [pscustomobject]@{ Name='Backup Catalog'; Passed=$catReady; Detail=$(if($catReady){'Catalog found'}else{'No backup catalog'}) }
    $data.MaxScore += 20; if ($catReady) { $data.Score += 20 } else { $data.Blockers += 'No backup catalog' }
} catch { $data.Checks += [pscustomobject]@{ Name='Catalog'; Passed=$false; Detail=$_.Exception.Message } }

# 3. Critical drivers included
try {
    $driverStore = "$env:SystemRoot\System32\DriverStore"
    $driversPresent = (Test-Path $driverStore)
    $driverCount = if ($driversPresent) { (Get-ChildItem $driverStore -Directory -ErrorAction SilentlyContinue).Count } else { 0 }
    $data.Checks += [pscustomobject]@{ Name='Driver Store'; Passed=$driverCount -gt 10; Detail="$driverCount driver packages" }
    $data.MaxScore += 15; if ($driverCount -gt 10) { $data.Score += 15 }
} catch { }

# 4. Disk layout readable
try {
    $diskLayout = Get-Disk -ErrorAction SilentlyContinue
    $disksFound = ($diskLayout | Measure-Object).Count
    $data.Checks += [pscustomobject]@{ Name='Disk Layout'; Passed=$disksFound -gt 0; Detail="$disksFound disks detected" }
    $data.MaxScore += 15; if ($disksFound -gt 0) { $data.Score += 15 }
} catch { $data.Checks += [pscustomobject]@{ Name='Disk Layout'; Passed=$false; Detail=$_.Exception.Message } }

# 5. VSS functioning
try {
    $vss = Get-Service -Name 'VSS' -ErrorAction SilentlyContinue
    $data.Checks += [pscustomobject]@{ Name='VSS Service'; Passed=($vss.Status -eq 'Running'); Detail="Status: $($vss.Status)" }
    $data.MaxScore += 10; if ($vss.Status -eq 'Running') { $data.Score += 10 }
} catch { }

# 6. System volume accessible
try {
    $sysVol = Get-Volume -DriveLetter $env:SystemDrive[0] -ErrorAction SilentlyContinue
    $data.Checks += [pscustomobject]@{ Name='System Volume'; Passed=($sysVol.HealthStatus -eq 'Healthy'); Detail=$sysVol.HealthStatus }
    $data.MaxScore += 10; if ($sysVol.HealthStatus -eq 'Healthy') { $data.Score += 10 }
} catch { }

# 7. EFI partition
try {
    $efi = Get-Partition | Where-Object { $_.Type -like '*System*' -or $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' } -ErrorAction SilentlyContinue
    $data.Checks += [pscustomobject]@{ Name='EFI Partition'; Passed=($null -ne $efi); Detail=$(if($efi){'Found'}else{'Not found'}) }
    $data.MaxScore += 10; if ($efi) { $data.Score += 10 }
} catch { }

$data.Ready = ($data.Blockers.Count -eq 0)
$score = if ($data.MaxScore -gt 0) { [math]::Round(($data.Score / $data.MaxScore) * 100, 0) } else { 0 }
$summary = "Restore Readiness: $score% | Blockers: $($data.Blockers.Count) $(if($data.Ready){'-- READY'}else{'- NOT READY'})"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Test-RestoreReadiness' -Status $(if ($data.Ready) {'Success'} else {'Failure'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() -Metrics @{ Score=$score; Blockers=$data.Blockers.Count; Ready=$data.Ready }
} else {
    [pscustomobject]@{ Tool='Test-RestoreReadiness'; Status=$(if ($data.Ready) {'Success'} else {'Failure'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
