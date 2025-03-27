<#
.SYNOPSIS
Analyzes boot time from Event Logs.
#>

$boot = Get-WinEvent -FilterHashtable @{LogName='System';ID=6005} | Select-Object -First 1 -ExpandProperty TimeCreated
$shutdown = Get-WinEvent -FilterHashtable @{LogName='System';ID=6006} | Select-Object -First 1 -ExpandProperty TimeCreated
"Last Boot: $boot"
"Last Shutdown: $shutdown"
