<#
.SYNOPSIS
    Free disk space safely by clearing well-known temp locations.
.DESCRIPTION
    Deletes files older than N days from a curated whitelist of folders. Built
    to be scheduled (Task Scheduler / Intune proactive remediation) without
    babysitting:
      - C:\Windows\Temp
      - C:\Users\*\AppData\Local\Temp (per-profile)
      - SoftwareDistribution\Download (after stopping wuauserv)
      - Windows error reports
      - Recycle bin (optional)
    Always supports -WhatIf so you can dry-run.
.PARAMETER DaysOld
    Delete files older than this many days. Default 7.
.PARAMETER EmptyRecycleBin
    Also empty Recycle Bin.
.EXAMPLE
    .\ScheduledTempCleanup.ps1 -WhatIf
.EXAMPLE
    .\ScheduledTempCleanup.ps1 -DaysOld 3 -EmptyRecycleBin
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
param(
    [ValidateRange(0, 365)]
    [int]$DaysOld = 7,
    [switch]$EmptyRecycleBin,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$cutoff      = (Get-Date).AddDays(-$DaysOld)
$errors      = New-Object System.Collections.Generic.List[string]
$freedBytes  = [long]0
$deletedCount= 0

$targets = New-Object System.Collections.Generic.List[string]
$targets.Add($env:TEMP)
$targets.Add('C:\Windows\Temp')
$targets.Add('C:\Windows\Prefetch')
$targets.Add('C:\ProgramData\Microsoft\Windows\WER\ReportQueue')
$targets.Add('C:\ProgramData\Microsoft\Windows\WER\ReportArchive')
Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $p = Join-Path $_.FullName 'AppData\Local\Temp'
    if (Test-Path $p) { $targets.Add($p) }
}

# Free space before
$beforeFree = (Get-PSDrive C).Free

foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t)) { continue }
    try {
        Get-ChildItem -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                $size = $_.Length
                if ($PSCmdlet.ShouldProcess($_.FullName, 'Delete')) {
                    try {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        $freedBytes += $size
                        $deletedCount++
                    } catch {
                        # file in use, skip silently
                    }
                }
            }
    } catch { $errors.Add("$t : $($_.Exception.Message)") }
}

# SoftwareDistribution\Download -- stop wuauserv first, restart after
$sdPath = 'C:\Windows\SoftwareDistribution\Download'
if (Test-Path $sdPath) {
    try {
        if ($PSCmdlet.ShouldProcess('wuauserv','Stop')) { Stop-Service wuauserv -Force -ErrorAction Stop }
        Get-ChildItem $sdPath -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                $size = $_.Length
                if ($PSCmdlet.ShouldProcess($_.FullName, 'Delete')) {
                    try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $freedBytes += $size; $deletedCount++ } catch { }
                }
            }
        if ($PSCmdlet.ShouldProcess('wuauserv','Start')) { Start-Service wuauserv }
    } catch { $errors.Add("SoftwareDistribution: $($_.Exception.Message)") }
}

if ($EmptyRecycleBin -and $PSCmdlet.ShouldProcess('Recycle Bin','Empty')) {
    try { Clear-RecycleBin -Force -ErrorAction Stop } catch { $errors.Add("RecycleBin: $($_.Exception.Message)") }
}

$afterFree = (Get-PSDrive C).Free

$status = if ($errors.Count) { 'Warning' } else { 'Success' }
$result = New-MSPResult `
    -Tool 'ScheduledTempCleanup' `
    -Status $status `
    -Summary "Deleted $deletedCount files, freed $(ConvertTo-MSPSize $freedBytes)." `
    -Data @{
        DaysOld        = $DaysOld
        Targets        = $targets.ToArray()
        FilesDeleted   = $deletedCount
        BytesFreed     = $freedBytes
        DiskFreeBefore = $beforeFree
        DiskFreeAfter  = $afterFree
    } `
    -Errors $errors.ToArray() `
    -Metrics @{ FilesDeleted = $deletedCount; BytesFreed = $freedBytes }

[void](Save-MSPResult -Result $result -Subfolder 'Maintenance')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
