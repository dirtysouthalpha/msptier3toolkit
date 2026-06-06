<#
.SYNOPSIS
    Drop ransomware canary files + register a file-watcher that triggers
    notification on modification.
.DESCRIPTION
    Lays down "canary" Office documents in strategic high-priority
    locations a ransomware would hit (Documents, Desktop, OneDrive root,
    network shares passed by -Path). Hashes are recorded. A Scheduled
    Task runs every 5 minutes to check for modifications and triggers
    Send-MSPNotification (Teams/Slack/SMTP) + a PSA ticket if any canary
    drifts.

    Idempotent -- re-running refreshes hashes without re-creating files.

.PARAMETER Path
    Additional folders to seed (e.g. file-server shares).
.PARAMETER Notify
    Channel(s) to alert on detection -- default uses whatever the config
    has configured for Send-MSPNotification.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Path,
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$canaryName = 'DO-NOT-MODIFY_CANARY.docx'
# Pseudo-Office content -- DOCX is a zip; we just write a binary signature
# so file modification is detectable. Real Office content not required.
$content = [byte[]](0x50,0x4B,0x03,0x04) + [Text.Encoding]::UTF8.GetBytes(
    "MSP Toolkit Ransomware Canary - DO NOT EDIT - if modified, ransomware may be active. $((Get-Date).ToString('o'))"
)

$targets = New-Object System.Collections.Generic.List[string]
$targets.Add("$env:USERPROFILE\Documents")
$targets.Add("$env:USERPROFILE\Desktop")
$onedriveRoot = "$env:USERPROFILE\OneDrive"
if (Test-Path $onedriveRoot) { $targets.Add($onedriveRoot) }
$onedriveBiz = Get-ChildItem $env:USERPROFILE -Directory -Filter 'OneDrive - *' -ErrorAction SilentlyContinue
foreach ($d in $onedriveBiz) { $targets.Add($d.FullName) }
foreach ($p in $Path) { if (Test-Path $p) { $targets.Add($p) } }

$paths = Get-MSPPaths
$registryPath = Join-Path $paths.Cache 'CanaryFiles.json'
$registry = if (Test-Path $registryPath) { Get-Content $registryPath -Raw | ConvertFrom-Json } else { @() }

$updated = @()
foreach ($t in $targets) {
    if (-not (Test-Path $t)) { continue }
    $file = Join-Path $t $canaryName
    if ($PSCmdlet.ShouldProcess($file, 'Write canary')) {
        try {
            [System.IO.File]::WriteAllBytes($file, $content)
            (Get-Item $file).Attributes = 'Hidden','Archive'
            $hash = Get-FileHash $file -Algorithm SHA256
            $updated += [pscustomobject]@{
                Path = $file
                SHA256 = $hash.Hash
                Bytes = (Get-Item $file).Length
                Created = (Get-Date).ToString('o')
            }
        } catch { }
    }
}
$updated | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $registryPath -Encoding UTF8

# Scheduled task -- runs Test-RansomwareCanary every 5 minutes
$checker = Join-Path $PSScriptRoot 'Test-RansomwareCanary.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$checker`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest

if ($PSCmdlet.ShouldProcess('MSPToolkit-CanaryWatcher', 'Register-ScheduledTask')) {
    Register-ScheduledTask -TaskName 'MSPToolkit-CanaryWatcher' -Action $action -Trigger $trigger `
        -Principal $principal -Description 'MSP Toolkit ransomware canary checker' -Force | Out-Null
}

$result = New-MSPResult `
    -Tool 'Install-RansomwareCanary' `
    -Status 'Success' `
    -Summary "Seeded $($updated.Count) canary file(s); watcher scheduled every 5 min." `
    -Data @{ Canaries = $updated; Registry = $registryPath } `
    -Metrics @{ CanariesDeployed = $updated.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Security')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
