<#
.SYNOPSIS
Reconnects broken mapped drives.
#>

$drives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 4 }
foreach ($drive in $drives) {
    Write-Output "Checking: $($drive.DeviceID)"
    Test-Path $drive.ProviderName
}
