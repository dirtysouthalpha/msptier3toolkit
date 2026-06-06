<#
.SYNOPSIS
    MSP Toolkit - Append-only signed audit log.
.DESCRIPTION
    Every privileged or destructive operation records a tamper-evident
    entry in <Logs>\audit.jsonl. Tamper detection is via a per-entry
    HMAC-SHA256 chain:

      entry.hash = HMAC-SHA256( key, prev.hash + canonical_json(entry) )

    Verification recomputes the chain top-down -- any modification or
    insertion breaks it. The HMAC key is generated per-machine and
    stored DPAPI-encrypted; you can also pass a shared key for
    cross-host correlation.
#>

Set-StrictMode -Version Latest

$Script:AuditKeyCache = $null

function _GetAuditKey {
    if ($Script:AuditKeyCache) { return $Script:AuditKeyCache }
    $paths = Get-MSPPaths
    $keyFile = Join-Path $paths.Cache 'audit.key.xml'
    if (Test-Path $keyFile) {
        $sec = Import-Clixml -LiteralPath $keyFile
    } else {
        $bytes = New-Object byte[] 32
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $sec = ConvertTo-SecureString ([Convert]::ToBase64String($bytes)) -AsPlainText -Force
        $sec | Export-Clixml -LiteralPath $keyFile -Force
    }
    $Script:AuditKeyCache = $sec
    return $sec
}

function _AuditPath {
    $paths = Get-MSPPaths
    Join-Path $paths.Logs 'audit.jsonl'
}

function _Hmac([byte[]]$Key, [string]$Message) {
    $h = New-Object Security.Cryptography.HMACSHA256(,$Key)
    [BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Message))).Replace('-','').ToLower()
}

function Write-MSPAudit {
    <#
    .SYNOPSIS
        Record a tamper-evident audit entry.
    .EXAMPLE
        Write-MSPAudit -Action 'Reset-Password' -Subject 'alice@example.com' -Outcome 'Success'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Action,
        [Parameter(Mandatory)] [string]$Subject,
        [string]$Outcome = 'Success',
        [hashtable]$Detail = @{},
        [string]$TenantId
    )

    if (-not $TenantId -and (Get-Command Get-MSPCurrentTenant -ErrorAction SilentlyContinue)) {
        $cur = Get-MSPCurrentTenant
        if ($cur) { $TenantId = $cur.Id }
    }

    $path = _AuditPath
    $prevHash = ''
    if (Test-Path $path) {
        $last = Get-Content $path -Tail 1 -ErrorAction SilentlyContinue
        if ($last) {
            try { $prevHash = ($last | ConvertFrom-Json).hash } catch { }
        }
    }

    $entry = [ordered]@{
        ts        = (Get-Date).ToString('o')
        actor     = "$env:USERDOMAIN\$env:USERNAME"
        host      = $env:COMPUTERNAME
        tenant    = $TenantId
        action    = $Action
        subject   = $Subject
        outcome   = $Outcome
        detail    = $Detail
        prevHash  = $prevHash
    }
    $canonical = ($entry | ConvertTo-Json -Depth 8 -Compress)

    # Decrypt key
    $secKey = _GetAuditKey
    $plain = [System.Net.NetworkCredential]::new('', $secKey).Password
    $keyBytes = [Convert]::FromBase64String($plain)

    $entry['hash'] = _Hmac -Key $keyBytes -Message $canonical
    Add-Content -Path $path -Value (($entry | ConvertTo-Json -Compress)) -Encoding UTF8
}

function Test-MSPAuditChain {
    <#
    .SYNOPSIS
        Walk the audit log, recomputing each HMAC against its predecessor.
        Reports the first index at which the chain breaks (or 0 if clean).
    #>
    [CmdletBinding()]
    param()

    $path = _AuditPath
    if (-not (Test-Path $path)) { return [pscustomobject]@{ Ok=$true; Entries=0; FirstBadIndex=$null } }

    $secKey = _GetAuditKey
    $plain = [System.Net.NetworkCredential]::new('', $secKey).Password
    $keyBytes = [Convert]::FromBase64String($plain)

    $lines = Get-Content $path
    $prev = ''
    $i = 0
    foreach ($l in $lines) {
        $i++
        try {
            $e = $l | ConvertFrom-Json
            $hashStored = $e.hash
            $eClone = $e.PSObject.Copy()
            $eClone.PSObject.Properties.Remove('hash')
            # Reorder so canonical matches the original write
            $canonical = ([ordered]@{
                ts=$eClone.ts; actor=$eClone.actor; host=$eClone.host; tenant=$eClone.tenant
                action=$eClone.action; subject=$eClone.subject; outcome=$eClone.outcome
                detail=$eClone.detail; prevHash=$eClone.prevHash
            } | ConvertTo-Json -Depth 8 -Compress)
            $expected = _Hmac -Key $keyBytes -Message $canonical
            if ($expected -ne $hashStored -or $eClone.prevHash -ne $prev) {
                return [pscustomobject]@{ Ok=$false; Entries=$lines.Count; FirstBadIndex=$i; Reason="Chain break at $i" }
            }
            $prev = $hashStored
        } catch {
            return [pscustomobject]@{ Ok=$false; Entries=$lines.Count; FirstBadIndex=$i; Reason=$_.Exception.Message }
        }
    }
    [pscustomobject]@{ Ok=$true; Entries=$lines.Count; FirstBadIndex=$null }
}

Export-ModuleMember -Function 'Write-MSPAudit','Test-MSPAuditChain'
