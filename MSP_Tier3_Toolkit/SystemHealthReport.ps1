<#
.SYNOPSIS
Generates a basic health and inventory report of a workstation.
#>

$ComputerName = $env:COMPUTERNAME
$UserName = $env:USERNAME
$OS = Get-CimInstance -ClassName Win32_OperatingSystem
$CPU = Get-CimInstance -ClassName Win32_Processor
$RAM = [math]::round(($OS.TotalVisibleMemorySize / 1MB), 2)
$FreeDisk = Get-PSDrive C | Select-Object -ExpandProperty Free
$FreeDiskGB = [math]::round($FreeDisk / 1GB, 2)

$report = @"
Computer Name: $ComputerName
User: $UserName
OS: $($OS.Caption) $($OS.Version)
CPU: $($CPU.Name)
RAM (GB): $RAM
Free Disk Space (C:) GB: $FreeDiskGB
Last Boot Time: $($OS.LastBootUpTime)
"@

$report | Out-File -FilePath "$env:USERPROFILE\Desktop\SystemHealthReport.txt"
Write-Output "System Health Report saved to Desktop."
