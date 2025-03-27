<#
.SYNOPSIS
Exports client-facing system summary.
#>

$sysInfo = Get-ComputerInfo | Select-Object CsName, OsName, WindowsVersion, CsProcessors, CsTotalPhysicalMemory
$sysInfo | ConvertTo-Html -Title "System Summary" | Out-File "$env:USERPROFILE\Desktop\SystemSummary.html"
