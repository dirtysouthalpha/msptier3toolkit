<#
.SYNOPSIS
Clears stuck print spooler jobs.
#>

try {
    Stop-Service spooler -Force
    Remove-Item "C:\Windows\System32\spool\PRINTERS\*" -Recurse -Force
    Start-Service spooler
    Write-Output "Print spooler cleaned and restarted."
} catch {
    Write-Output "Error clearing spooler: $_"
}
