<#
.SYNOPSIS
Attempts to fix Windows Update issues.
#>

Stop-Service wuauserv -Force
Remove-Item -Recurse -Force C:\Windows\SoftwareDistribution
Start-Service wuauserv
wuauclt /detectnow
