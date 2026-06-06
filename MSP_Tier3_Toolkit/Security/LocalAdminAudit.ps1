<#
.SYNOPSIS
    List every user / group with local Administrator rights.
.DESCRIPTION
    Reads the Administrators group via Get-LocalGroupMember when available
    (PS 5.1+ with Microsoft.PowerShell.LocalAccounts), falling back to
    `net localgroup administrators` parsing on Server Core / minimal SKUs
    where the cmdlet may be unavailable.
.EXAMPLE
    .\LocalAdminAudit.ps1
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$AsJson)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$errors  = New-Object System.Collections.Generic.List[string]
$members = @()

try {
    if (Get-Command Get-LocalGroupMember -ErrorAction SilentlyContinue) {
        $members = Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop |
            ForEach-Object {
                [pscustomobject]@{
                    Name         = $_.Name
                    Source       = "$($_.PrincipalSource)"
                    ObjectClass  = "$($_.ObjectClass)"
                    SID          = "$($_.SID)"
                }
            }
    } else {
        # Fallback: parse `net localgroup`
        $raw = & net localgroup administrators
        $start = ($raw | Select-String '^---').LineNumber
        $end   = ($raw | Select-String '^The command completed').LineNumber - 1
        if ($start -and $end -gt $start) {
            $members = $raw[$start..($end-1)] | Where-Object { $_.Trim() } |
                ForEach-Object {
                    [pscustomobject]@{
                        Name = $_.Trim(); Source = 'unknown'; ObjectClass = 'unknown'; SID = $null
                    }
                }
        }
    }
}
catch { $errors.Add($_.Exception.Message) }

$nonBuiltin = @($members | Where-Object {
    $_.Name -notmatch '\\(Administrator|Domain Admins|Enterprise Admins)$'
})

$status = if ($errors.Count) { 'Failure' }
          elseif ($nonBuiltin.Count -gt 3) { 'Warning' }
          else { 'Success' }

$result = New-MSPResult `
    -Tool 'LocalAdminAudit' `
    -Status $status `
    -Summary "$($members.Count) local Administrator member(s); $($nonBuiltin.Count) non-builtin." `
    -Data @{ Members = $members; NonBuiltin = $nonBuiltin } `
    -Errors $errors.ToArray() `
    -Metrics @{ MemberCount = $members.Count; NonBuiltinCount = $nonBuiltin.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Security')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
