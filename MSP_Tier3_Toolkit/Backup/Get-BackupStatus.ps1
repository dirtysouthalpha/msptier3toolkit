<#
.SYNOPSIS
    MSP Toolkit - Backup Status Agent.
.DESCRIPTION
    Checks Windows Server Backup job history, last good backup age,
    next scheduled backup, and flags backups older than threshold.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([int]$WarningDays = 7, [int]$CriticalDays = 14)

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Jobs=@(); LastGoodBackup=$null; DaysSinceLast=0; NextScheduled=$null; Status='Unknown' }

try {
    # Windows Server Backup
    $wbJobs = Get-WBJob -Previous 10 -ErrorAction SilentlyContinue
    foreach ($job in $wbJobs) {
        $data.Jobs += [pscustomobject]@{
            JobID         = $job.JobId
            StartTime     = $job.StartTime
            EndTime       = $job.EndTime
            Status        = $job.JobState
            HResult       = $job.HResult
            ErrorMessage  = $job.ErrorDescription
            BackupType    = $job.BackupType
            Volumes       = $job.VolumeNames -join ', '
        }
    }

    $goodJobs = @($data.Jobs | Where-Object { $_.Status -eq 'Completed' -or $_.HResult -eq 0 })
    if ($goodJobs.Count -gt 0) {
        $last = $goodJobs | Sort-Object EndTime -Descending | Select-Object -First 1
        $data.LastGoodBackup = $last.EndTime
        $data.DaysSinceLast = [math]::Round(((Get-Date) - [DateTime]$last.EndTime).TotalDays, 1)
    }

    # Scheduled backup policy
    try {
        $policy = Get-WBPolicy -ErrorAction SilentlyContinue
        if ($policy) {
            $schedule = Get-WBSchedule -Policy $policy -ErrorAction SilentlyContinue
            if ($schedule) { $data.NextScheduled = ($schedule | Sort-Object | Select-Object -First 1).ToString() }
        }
    } catch { }

    if ($data.DaysSinceLast -ge $CriticalDays) { $data.Status = 'Critical' }
    elseif ($data.DaysSinceLast -ge $WarningDays) { $data.Status = 'Warning' }
    elseif ($data.DaysSinceLast -gt 0) { $data.Status = 'OK' }
    else { $data.Status = 'No backups found' }
} catch { $errors.Add("Backup query failed: $($_.Exception.Message)") }

# Fallback: check event log for backup events
if ($data.Jobs.Count -eq 0) {
    try {
        $evtBackups = Get-WinEvent -LogName 'Microsoft-Windows-Backup/Operational' -MaxEvents 5 -ErrorAction SilentlyContinue |
            Where-Object { $_.Id -in 4,14,17 } | ForEach-Object {
                [pscustomobject]@{ StartTime=$_.TimeCreated; Status=if($_.Id -eq 4){'Completed'}elseif($_.Id -eq 14){'Completed'}else{'Failed'}; Message=$_.Message.Substring(0, [Math]::Min(200, $_.Message.Length)) }
            }
        if ($evtBackups) {
            $lastEvt = $evtBackups | Where-Object Status -eq 'Completed' | Sort-Object StartTime -Descending | Select-Object -First 1
            if ($lastEvt) {
                $data.LastGoodBackup = $lastEvt.StartTime
                $data.DaysSinceLast = [math]::Round(((Get-Date) - $lastEvt.StartTime).TotalDays, 1)
            }
        }
    } catch { }
}

$summary = "Backup: $(if($data.LastGoodBackup){\"Last good $($data.DaysSinceLast)d ago ($($data.Status))\"}else{'No backups found'}) | Jobs: $($data.Jobs.Count)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-BackupStatus' -Status $(if ($data.Status -eq 'Critical') {'Failure'} elseif ($data.Status -eq 'Warning') {'Warning'} else {'Success'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ DaysSinceLast=$data.DaysSinceLast; JobsFound=$data.Jobs.Count; Status=$data.Status }
} else {
    [pscustomobject]@{ Tool='Get-BackupStatus'; Status=$(if ($data.Status -eq 'Critical') {'Failure'} elseif ($data.Status -eq 'Warning') {'Warning'} else {'Success'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
