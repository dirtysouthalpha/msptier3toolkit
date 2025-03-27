<#
.SYNOPSIS
Silently uninstalls a program by name.
#>

param(
    [string]$AppName
)

$programs = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*$AppName*" }
foreach ($app in $programs) {
    Write-Output "Uninstalling: $($app.Name)"
    $app.Uninstall()
}
