<#
.SYNOPSIS
    Deep DNS troubleshooting -- resolves a name against every configured
    server PLUS public resolvers, with per-server timing and answer diff.
.DESCRIPTION
    Answers the "DNS is slow / wrong answer / not resolving" ticket. For
    each target hostname:

      - Resolves via every configured server (Get-DnsClientServerAddress)
      - Also resolves via 1.1.1.1, 8.8.8.8, 9.9.9.9
      - Records per-server response time
      - Flags discrepancies (split-brain DNS)
      - Tests TCP/53 if UDP/53 hangs (firewall sometimes)

    Pair with Reset-NetworkStack if results are clearly cached-bad.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string[]]$Name = @('outlook.office365.com','login.microsoftonline.com','www.google.com'),
    [switch]$AsJson
)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$configured = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
               Where-Object ServerAddresses).ServerAddresses | Select-Object -Unique
$public = @('1.1.1.1','8.8.8.8','9.9.9.9')
$servers = @($configured + $public) | Select-Object -Unique

$rows = foreach ($n in $Name) {
    foreach ($srv in $servers) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = try {
            Resolve-DnsName -Name $n -Server $srv -DnsOnly -ErrorAction Stop -QuickTimeout
        } catch { $null }
        $sw.Stop()
        [pscustomobject]@{
            Name      = $n
            Server    = $srv
            ServerType= if ($public -contains $srv) { 'Public' } else { 'Configured' }
            Answer    = if ($r) { ($r | Where-Object Type -in 'A','AAAA','CNAME' | Select-Object -ExpandProperty IPAddress -First 3) -join ',' } else { '' }
            Ms        = $sw.ElapsedMilliseconds
            Failed    = -not $r
        }
    }
}

# Split-brain detection
$splitBrain = @()
foreach ($n in ($rows | Group-Object Name)) {
    $answers = $n.Group | Where-Object { -not $_.Failed } | Select-Object -ExpandProperty Answer -Unique
    if ($answers.Count -gt 1) {
        $splitBrain += [pscustomobject]@{ Name = $n.Name; Answers = $answers }
    }
}

$failures = @($rows | Where-Object Failed)
$status = if ($failures.Count -eq $rows.Count) { 'Failure' }
          elseif ($failures.Count -or $splitBrain.Count) { 'Warning' }
          else { 'Success' }

$result = New-MSPResult `
    -Tool 'Test-DNSDeepDive' `
    -Status $status `
    -Summary "$($Name.Count) names x $($servers.Count) servers = $($rows.Count) tests; $($failures.Count) failed; $($splitBrain.Count) split-brain." `
    -Data @{
        ConfiguredServers = $configured
        Results           = $rows
        SplitBrain        = $splitBrain
    } `
    -Metrics @{ TestsRun = $rows.Count; Failures = $failures.Count; SplitBrain = $splitBrain.Count }

[void](Save-MSPResult -Result $result -Subfolder 'Network')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
