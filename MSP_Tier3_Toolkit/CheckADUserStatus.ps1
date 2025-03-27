<#
.SYNOPSIS
Checks AD user lockout and password status.
#>

param (
    [Parameter(Mandatory)]
    [string]$Username
)

Import-Module ActiveDirectory

$user = Get-ADUser $Username -Properties LockedOut, PasswordLastSet, BadLogonCount, LastBadPasswordAttempt
$user | Select-Object SamAccountName, LockedOut, PasswordLastSet, BadLogonCount, LastBadPasswordAttempt | Format-List
