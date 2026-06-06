<#
.SYNOPSIS
    Validate OneDrive client state, folder redirection, and sync health.
.DESCRIPTION
    Most user-facing tickets in M365 shops involve OneDrive: stuck sync,
    missing folder backup, paused account. This script gathers:
      - OneDrive process state (per user)
      - Configured accounts from HKCU\Software\Microsoft\OneDrive\Accounts
      - Known Folder Move (KFM) coverage (Desktop / Documents / Pictures)
      - Last error from the OneDrive registry "LastError" field
      - Disk free at the OneDrive root

    Runs in the context of the *current interactive user*. For per-user
    checks against another account, run remotely with their token.
.EXAMPLE
    .\OneDriveSyncHealthCheck.ps1
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$AsJson)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$accounts = @()
$errors   = New-Object System.Collections.Generic.List[string]

try {
    $running = @(Get-Process OneDrive -ErrorAction SilentlyContinue)
    $accountsKey = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
    if (Test-Path $accountsKey) {
        $accounts = Get-ChildItem $accountsKey | ForEach-Object {
            $a = Get-ItemProperty $_.PSPath
            $folder = $a.UserFolder
            $kfm = @{
                Desktop   = $false
                Documents = $false
                Pictures  = $false
            }
            $scope = Get-ItemProperty (Join-Path $_.PSPath 'ScopeIdToMountPointPathCache') -ErrorAction SilentlyContinue
            $userShellFolders = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
            if ($userShellFolders) {
                if ($userShellFolders.Desktop  -and $userShellFolders.Desktop.StartsWith($folder, [StringComparison]::OrdinalIgnoreCase))  { $kfm.Desktop   = $true }
                if ($userShellFolders.Personal -and $userShellFolders.Personal.StartsWith($folder, [StringComparison]::OrdinalIgnoreCase)) { $kfm.Documents = $true }
                if ($userShellFolders.'My Pictures' -and $userShellFolders.'My Pictures'.StartsWith($folder, [StringComparison]::OrdinalIgnoreCase)) { $kfm.Pictures = $true }
            }
            $freeGB = $null
            if ($folder -and (Test-Path $folder)) {
                try {
                    $drive = (Get-Item $folder).PSDrive
                    $freeGB = [math]::Round((Get-PSDrive $drive.Name).Free / 1GB, 1)
                } catch { }
            }
            [pscustomobject]@{
                AccountKey   = $_.PSChildName
                UserEmail    = $a.UserEmail
                DisplayName  = $a.DisplayName
                Business     = ($_.PSChildName -like 'Business*')
                UserFolder   = $folder
                LastError    = $a.LastError
                ServiceEP    = $a.ServiceEndpointUri
                KFM          = [pscustomobject]$kfm
                FreeGBOnDrive= $freeGB
            }
        }
    }

    $errors2 = @($accounts | Where-Object { $_.LastError -and $_.LastError -ne 0 })
    $kfmGaps = @($accounts | Where-Object Business |
                    Where-Object { -not ($_.KFM.Desktop -and $_.KFM.Documents -and $_.KFM.Pictures) })
}
catch { $errors.Add($_.Exception.Message) }

$status = if ($errors.Count) { 'Failure' }
          elseif ($accounts.Count -eq 0) { 'Warning' }
          elseif ($errors2.Count -or $running.Count -eq 0) { 'Warning' }
          else { 'Success' }

$summary = if ($accounts.Count -eq 0) { 'No OneDrive accounts configured for current user.' }
           elseif ($running.Count -eq 0) { 'OneDrive client not running.' }
           elseif ($kfmGaps.Count) { "$($kfmGaps.Count) account(s) missing Known Folder Move coverage." }
           else { "$($accounts.Count) account(s) syncing, $($running.Count) process(es) running." }

$result = New-MSPResult `
    -Tool 'OneDriveSyncHealthCheck' `
    -Status $status `
    -Summary $summary `
    -Data @{ Accounts = $accounts; Processes = $running.Count } `
    -Errors $errors.ToArray() `
    -Metrics @{ AccountCount = $accounts.Count; KFMGaps = $kfmGaps.Count; LastErrors = $errors2.Count }

[void](Save-MSPResult -Result $result -Subfolder 'M365')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
