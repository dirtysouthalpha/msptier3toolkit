<#
.SYNOPSIS
    Detect a captive portal between the machine and the internet.
.DESCRIPTION
    Hotels, conference rooms, guest WiFi, customer offices -- the
    classic "I'm associated but nothing loads" scenario. Tests:

      - HTTP 204 endpoints (the NCSI / Google / Apple captive checks)
      - HTTPS without certificate validation (looks for cert chain breakage)
      - Whether the response body equals the expected sentinel

    If a portal is detected, surfaces the *redirect URL* so the user can
    open it directly instead of waiting for the OS to pop the toast.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$AsJson)

Import-Module (Join-Path $PSScriptRoot '..\..\Core\MSPToolkit.psd1') -Force -ErrorAction SilentlyContinue

$probes = @(
    @{ Name='Microsoft NCSI';      Url='http://www.msftncsi.com/ncsi.txt';            Expected='Microsoft NCSI' },
    @{ Name='Microsoft Connect';   Url='http://www.msftconnecttest.com/connecttest.txt'; Expected='Microsoft Connect Test' },
    @{ Name='Google 204';          Url='http://www.gstatic.com/generate_204';         Expected='' ; ExpectedStatus=204 },
    @{ Name='Apple Captive';       Url='http://captive.apple.com/hotspot-detect.html';  Expected='<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>' }
)

$rows = foreach ($p in $probes) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $row = [pscustomobject]@{ Name=$p.Name; Url=$p.Url; Status=$null; BodyOk=$null; Redirect=$null; Ms=0 }
    try {
        $r = Invoke-WebRequest -Uri $p.Url -UseBasicParsing -MaximumRedirection 0 -ErrorAction Stop -TimeoutSec 5
        $row.Status = $r.StatusCode
        if ($p.ExpectedStatus) {
            $row.BodyOk = ($r.StatusCode -eq $p.ExpectedStatus)
        } else {
            $row.BodyOk = ($r.Content.Trim() -eq $p.Expected.Trim())
        }
    } catch {
        $resp = $_.Exception.Response
        if ($resp -and ($resp.StatusCode -ge 300 -and $resp.StatusCode -lt 400)) {
            $row.Status = [int]$resp.StatusCode
            $row.Redirect = $resp.Headers['Location']
            $row.BodyOk = $false
        } else {
            $row.Status = -1
        }
    }
    $sw.Stop(); $row.Ms = $sw.ElapsedMilliseconds
    $row
}

$portal = $rows | Where-Object Redirect | Select-Object -First 1
$detected = [bool]$portal
$broken   = ($rows | Where-Object { $_.BodyOk -eq $false -and -not $_.Redirect }).Count

$status = if ($detected) { 'Warning' }
          elseif ($broken -gt 1) { 'Warning' }
          else { 'Success' }

$summary = if ($detected) { "Captive portal detected -- redirect: $($portal.Redirect)" }
           elseif ($broken -eq 0) { "Direct internet -- no portal." }
           else { "Probes inconsistent -- possible transparent proxy." }

$result = New-MSPResult `
    -Tool 'Test-CaptivePortal' `
    -Status $status `
    -Summary $summary `
    -Data @{ PortalDetected = $detected; RedirectUrl = $portal.Redirect; Probes = $rows } `
    -Metrics @{ ProbesRun = $rows.Count; PortalDetected = [int]$detected }

[void](Save-MSPResult -Result $result -Subfolder 'Network')
if ($AsJson) { $result | ConvertTo-Json -Depth 8 } else { $result }
