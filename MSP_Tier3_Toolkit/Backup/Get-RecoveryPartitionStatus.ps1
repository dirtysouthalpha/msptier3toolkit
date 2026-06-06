<#
.SYNOPSIS
    MSP Toolkit - Recovery Partition Status.
.DESCRIPTION
    Validates WinRE recovery partition presence, reagentc status,
    partition sizing, and compares WinRE version to running OS.
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ WinRE=@{}; Partition=@{}; VersionMatch=$false; Score=0; MaxScore=0 }

# --- WinRE via reagentc ---
try {
    $reagentc = reagentc /info 2>&1 | Out-String
    $data.WinRE = @{
        Enabled  = ($reagentc -match 'Windows RE status:\s+Enabled')
        Location = if ($reagentc -match 'Windows RE location:\s+(.+)') { $Matches[1].Trim() } else { '' }
        BCDID    = if ($reagentc -match 'Boot Configuration Data ID:\s+(.+)') { $Matches[1].Trim() } else { '' }
        ImageIndex = if ($reagentc -match 'Recovery image index:\s+(\d+)') { $Matches[1] } else { '' }
        Description = if ($reagentc -match 'Recovery image description:\s+(.+)') { $Matches[1].Trim() } else { '' }
    }
    $data.MaxScore += 30; if ($data.WinRE.Enabled) { $data.Score += 30 }
} catch { $errors.Add("reagentc: $($_.Exception.Message)") }

# --- Recovery Partition ---
try {
    $recoveryPartitions = Get-Partition | Where-Object {
        $_.Type -like '*Recovery*' -or $_.GptType -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'
    } -ErrorAction SilentlyContinue
    
    if ($recoveryPartitions) {
        $rp = $recoveryPartitions | Select-Object -First 1
        $data.Partition = @{
            DiskNumber = $rp.DiskNumber
            PartitionNumber = $rp.PartitionNumber
            DriveLetter = $rp.DriveLetter
            SizeGB = [math]::Round($rp.Size / 1GB, 1)
            Type = $rp.Type
            GptType = $rp.GptType
            IsActive = ($rp.IsActive -eq $true)
        }
        $data.MaxScore += 20; if ($rp.Size -gt 300MB) { $data.Score += 20 } else { $data.Score += 10 }
    } else {
        $data.Partition = @{ Found = $false }
    }
} catch { $errors.Add("Partition: $($_.Exception.Message)") }

# --- Version Match ---
try {
    $osVer = [Environment]::OSVersion.Version
    if ($data.WinRE.Location -and (Test-Path $data.WinRE.Location)) {
        $winreExe = Join-Path (Split-Path $data.WinRE.Location) 'System32\winload.exe'
        if (Test-Path $winreExe) {
            $winreVer = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($winreExe).FileVersion
            $data.VersionMatch = ($winreVer -match [regex]::Escape("$($osVer.Major).$($osVer.Minor)"))
        }
    }
    $data.OSVersion = $osVer.ToString()
    $data.MaxScore += 10; if ($data.VersionMatch) { $data.Score += 10 }
} catch { }

# --- Disk layout summary ---
try {
    $allParts = Get-Partition -ErrorAction SilentlyContinue
    $data.TotalPartitions = $allParts.Count
    $data.DiskCount = (Get-Disk -ErrorAction SilentlyContinue).Count
    $data.MaxScore += 5; if ($data.DiskCount -gt 0) { $data.Score += 5 }
} catch { }

$score = if ($data.MaxScore -gt 0) { [math]::Round(($data.Score / $data.MaxScore) * 100, 0) } else { 0 }
$summary = "Recovery: $(if($data.WinRE.Enabled){'WinRE Enabled'}else{'WinRE Disabled'}) | Partition: $(if($data.Partition.SizeGB){\"$($data.Partition.SizeGB) GB\"}else{'Not found'}) | Version match: $(if($data.VersionMatch){'Yes'}else{'No'})"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-RecoveryPartitionStatus' -Status $(if ($data.WinRE.Enabled -and $data.Partition.SizeGB) {'Success'} elseif ($data.WinRE.Enabled) {'Warning'} else {'Failure'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() -Metrics @{ Score=$score; WinRE=$data.WinRE.Enabled; PartitionGB=[double]$data.Partition.SizeGB }
} else {
    [pscustomobject]@{ Tool='Get-RecoveryPartitionStatus'; Status=$(if ($data.WinRE.Enabled -and $data.Partition.SizeGB) {'Success'} elseif ($data.WinRE.Enabled) {'Warning'} else {'Failure'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
