<#
.SYNOPSIS
    MSPToolkit Reporting -- Dashboards, BI, SLA tracking, cost optimization,
    and compliance reporting engine.
.DESCRIPTION
    Generates HTML dashboards, tracks SLA metrics, analyzes cost optimization
    opportunities, builds compliance pack reports, and exports multi-format
    (HTML, CSV, JSON, PDF) results.
    Exported functions:
      New-MSPDashboard          -- Generate an executive HTML dashboard
      Get-MSPSLAMetrics         -- Track SLA compliance across tickets/tenants
      Invoke-MSPCostOptimizer   -- Identify cost-saving opportunities (licenses, VMs)
      New-MSPComplianceReport   -- Build compliance pack report (CIS, HIPAA, etc.)
      Export-MSPReport          -- Export report to HTML/CSV/JSON/PDF
      Get-MSPTenantScorecard    -- Per-tenant health scorecard
      Get-MSPUtilizationTrend   -- Trend analysis for CPU/Mem/Disk/Network
.NOTES
    v17.0 -- Business Intelligence & Reporting
#>
#Requires -Version 5.1

# ============================================================================
#  Dashboard
# ============================================================================

function New-MSPDashboard {
    [CmdletBinding()]
    param(
        [string]$OutputPath = ('{0}\MSP_Dashboard.html' -f $env:TEMP),
        [switch]$IncludeTenant
    )

    $sysInfo = Get-MSPSystemInfo -ErrorAction SilentlyContinue
    $facts = Get-MSPOSFacts -ErrorAction SilentlyContinue
    $disk = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Used -gt 0 }
    $reboot = Test-MSPPendingReboot -ErrorAction SilentlyContinue
    $services = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Running' -and $_.StartType -eq 'Automatic' }

    $cpuLoad = try { (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue).CounterSamples.CookedValue } catch { 0 }
    $memInfo = if ($facts) { $facts.MemoryInfo } else { [pscustomobject]@{TotalGB = 0; FreeGB = 0; UsagePercent = 0} }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>MSP Executive Dashboard -- $(Get-Date -Format 'yyyy-MM-dd HH:mm')</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0f172a;color:#e2e8f0;padding:24px}
h1{font-size:24px;margin-bottom:8px;color:#38bdf8}
.subtitle{color:#94a3b8;font-size:13px;margin-bottom:24px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px}
.card{background:#1e293b;border-radius:12px;padding:20px;border:1px solid #334155}
.card h2{font-size:14px;color:#94a3b8;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:12px}
.card .value{font-size:32px;font-weight:700;color:#38bdf8}
.card .label{font-size:12px;color:#64748b}
.card .status-ok{color:#22c55e}
.card .status-warn{color:#f59e0b}
.card .status-bad{color:#ef4444}
.progress-bg{background:#334155;border-radius:6px;height:8px;margin-top:8px;overflow:hidden}
.progress-fill{height:100%;border-radius:6px;transition:width 0.3s}
.table{width:100%;border-collapse:collapse;margin-top:12px;font-size:13px}
.table th{text-align:left;color:#64748b;padding:6px 8px;border-bottom:1px solid #334155}
.table td{padding:6px 8px;border-bottom:1px solid #1e293b}
.footer{margin-top:24px;font-size:11px;color:#475569;text-align:center}
</style>
</head>
<body>
<h1>MSP Tier 3 Toolkit -- Executive Dashboard</h1>
<div class="subtitle">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz') | Host: $env:COMPUTERNAME</div>
<div class="grid">
  <div class="card">
    <h2>System Health</h2>
    <div class="value">$(if($reboot.PendingReboot){'Warning'}else{'OK'})</div>
    <div class="label">Pending Reboot: $(if($reboot.PendingReboot){'Yes'}else{'No'})</div>
    <div class="label">OS: $($facts.OSName) $($facts.OSVersion)</div>
  </div>
  <div class="card">
    <h2>CPU Usage</h2>
    <div class="value">$([math]::Round($cpuLoad))%</div>
    <div class="progress-bg"><div class="progress-fill" style="width:$([math]::Round($cpuLoad))%;background:$(if($cpuLoad -gt 80){'#ef4444'}elseif($cpuLoad -gt 60){'#f59e0b'}else{'#22c55e'})"></div></div>
  </div>
  <div class="card">
    <h2>Memory</h2>
    <div class="value">$([math]::Round($memInfo.UsagePercent))%</div>
    <div class="label">$([math]::Round($memInfo.FreeGB,1)) GB free of $([math]::Round($memInfo.TotalGB,1)) GB</div>
    <div class="progress-bg"><div class="progress-fill" style="width:$([math]::Round($memInfo.UsagePercent))%;background:$(if($memInfo.UsagePercent -gt 85){'#ef4444'}elseif($memInfo.UsagePercent -gt 65){'#f59e0b'}else{'#22c55e'})"></div></div>
  </div>
  <div class="card">
    <h2>Disk Overview</h2>
    $(($disk | ForEach-Object { '<div class=label>' + $_.Name + ': ' + [math]::Round($_.Used/1GB,1) + '/' + [math]::Round(($_.Used+$_.Free)/1GB,1) + ' GB (' + [math]::Round($_.Used/($_.Used+$_.Free)*100,1) + '%)</div>' }) -join "`n")
  </div>
  <div class="card">
    <h2>Failed Services</h2>
    <div class="value $(if($services.Count -gt 0){'status-bad'}else{'status-ok'})">$($services.Count)</div>
    <div class="label">Auto-start services not running</div>
  </div>
  <div class="card">
    <h2>Uptime</h2>
    <div class="value">$($facts.UptimeDays) d</div>
    <div class="label">$($facts.UptimeHours) hours since last boot</div>
  </div>
  $(if($IncludeTenant){'<div class="card"><h2>Multi-Tenant</h2><div class="label">Run Get-MSPTenantScorecard for details</div></div>'})
</div>
<div class="footer">MSP Tier 3 Toolkit v17 | Generated by New-MSPDashboard</div>
</body></html>
"@

    Set-Content -Path $OutputPath -Value $html -Encoding UTF8
    Write-Host "Dashboard written to $OutputPath" -ForegroundColor Green
    return [pscustomobject]@{ Path = $OutputPath; SizeKB = [math]::Round((Get-Item $OutputPath).Length/1KB,1) }
}

# ============================================================================
#  SLA Metrics
# ============================================================================

function Get-MSPSLAMetrics {
    [CmdletBinding()]
    param(
        [string]$TicketLogPath,
        [int]$ResponseSLAHours = 4,
        [int]$ResolutionSLAHours = 24
    )

    $data = [pscustomobject]@{
        Timestamp         = (Get-Date).ToString('o')
        TotalTickets      = 0
        ResponseOK        = 0
        ResolutionOK      = 0
        AvgResponseHours  = 0
        AvgResolutionHours= 0
        ResponseSLAPct    = 0
        ResolutionSLAPct  = 0
        BreachTickets     = @()
        Checks            = @()
        Score             = 0
        MaxScore          = 0
        Summary           = ''
    }

    if (-not $TicketLogPath) {
        $data.Summary = 'No ticket log path provided'
        return $data
    }

    try {
        $tickets = if ($TicketLogPath -match '\.csv$') {
            Import-Csv $TicketLogPath
        } elseif ($TicketLogPath -match '\.json$') {
            Get-Content $TicketLogPath -Raw | ConvertFrom-Json
        } else { $null }

        if (-not $tickets) { throw 'No tickets loaded' }
        $data.TotalTickets = ($tickets | Measure-Object).Count

        $totalResponseHours = 0; $totalResolutionHours = 0; $responseCount = 0; $resolutionCount = 0

        foreach ($t in $tickets) {
            $created = [DateTime]$t.CreatedAt
            $responded = if ($t.FirstResponseAt) { [DateTime]$t.FirstResponseAt }
            $resolved = if ($t.ResolvedAt) { [DateTime]$t.ResolvedAt }

            if ($responded) {
                $respHours = ($responded - $created).TotalHours
                $totalResponseHours += $respHours; $responseCount++
                if ($respHours -le $ResponseSLAHours) { $data.ResponseOK++ }
            }
            if ($resolved) {
                $resHours = ($resolved - $created).TotalHours
                $totalResolutionHours += $resHours; $resolutionCount++
                if ($resHours -le $ResolutionSLAHours) { $data.ResolutionOK++ }
                else {
                    $data.BreachTickets += [pscustomobject]@{ Id=$t.Id; Title=$t.Title; ResolveHours=[math]::Round($resHours,1) }
                }
            }
        }

        if ($responseCount -gt 0) { $data.AvgResponseHours = [math]::Round($totalResponseHours / $responseCount, 1) }
        if ($resolutionCount -gt 0) { $data.AvgResolutionHours = [math]::Round($totalResolutionHours / $resolutionCount, 1) }
        $data.ResponseSLAPct = if ($responseCount -gt 0) { [math]::Round($data.ResponseOK / $responseCount * 100, 1) } else { 0 }
        $data.ResolutionSLAPct = if ($resolutionCount -gt 0) { [math]::Round($data.ResolutionOK / $resolutionCount * 100, 1) } else { 0 }

        $data.Checks += [pscustomobject]@{ Name='Response SLA >= 90%'; Pass=($data.ResponseSLAPct -ge 90); Detail=('{0}%' -f $data.ResponseSLAPct) }
        $data.Checks += [pscustomobject]@{ Name='Resolution SLA >= 80%'; Pass=($data.ResolutionSLAPct -ge 80); Detail=('{0}%' -f $data.ResolutionSLAPct) }
    } catch {
        $data.Checks += [pscustomobject]@{ Name='Ticket Data'; Pass=$false; Detail=('Error: {0}' -f $_.Exception.Message) }
    }

    $data.MaxScore = $data.Checks.Count * 20
    $data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
    $data.Summary = ('SLA: Response {0}% | Resolution {1}% | {2} breaches' -f $data.ResponseSLAPct,$data.ResolutionSLAPct,$data.BreachTickets.Count)
    return $data
}

# ============================================================================
#  Cost Optimizer
# ============================================================================

function Invoke-MSPCostOptimizer {
    [CmdletBinding()]
    param()

    $data = [pscustomobject]@{
        Timestamp             = (Get-Date).ToString('o')
        UnusedLicenses        = 0
        UnusedLicenseSavings  = 0
        OversizedResources    = @()
        EstimatedTotalSavings = 0
        Opportunities         = @()
        Checks                = @()
        Score                 = 0
        MaxScore              = 0
        Summary               = ''
    }

    try {
        $licenses = Invoke-MSPGraph -Resource 'subscribedSkus' -ErrorAction Stop
        if ($licenses.value) {
            foreach ($l in $licenses.value) {
                $used = $l.consumedUnits
                $total = $l.prepaidUnits.enabled
                $unused = $total - $used
                if ($unused -gt 0) {
                    $data.UnusedLicenses += $unused
                    $estCost = switch -Regex ($l.skuPartNumber) {
                        'ENTERPRISEPACK' { 35 }; 'ENTERPRISEPREMIUM' { 57 }
                        'BUSINESS_PREMIUM' { 22 }; 'BUSINESS_STANDARD' { 12.50 }
                        default { 8 }
                    }
                    $savings = $unused * $estCost
                    $data.UnusedLicenseSavings += $savings
                    $data.Opportunities += [pscustomobject]@{ Type='Unused License'; Detail=$l.skuPartNumber; Count=$unused; MonthlySavings=$savings }
                }
            }
        }
        $data.Checks += [pscustomobject]@{ Name='License Analysis'; Pass=$true; Detail='Graph available' }
    } catch {
        $data.Checks += [pscustomobject]@{ Name='License Analysis'; Pass=$false; Detail='Graph unavailable' }
    }

    try {
        $users = Invoke-MSPGraph -Resource ('users?`$select=userPrincipalName,assignedLicenses,signInActivity') -ErrorAction SilentlyContinue
        if ($users.value) {
            $inactive = $users.value | Where-Object {
                $_.assignedLicenses.Count -gt 0 -and
                $_.signInActivity.lastSignInDateTime -and
                [DateTime]$_.signInActivity.lastSignInDateTime -lt (Get-Date).AddDays(-90)
            }
            if ($inactive.Count -gt 0) {
                $data.Opportunities += [pscustomobject]@{ Type='Inactive Licensed User'; Detail=('{0} users inactive 90+ days' -f $inactive.Count); Count=$inactive.Count; MonthlySavings=$inactive.Count * 8 }
            }
        }
    } catch { }

    $data.EstimatedTotalSavings = ($data.Opportunities | Measure-Object -Property MonthlySavings -Sum).Sum
    $data.Checks += [pscustomobject]@{ Name='Savings Identified'; Pass=($data.EstimatedTotalSavings -gt 0); Detail=('`${0}/mo' -f [math]::Round($data.EstimatedTotalSavings,2)) }

    $data.MaxScore = $data.Checks.Count * 20
    $data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
    $data.Summary = ('Cost Optimizer: `${0} identified -- {1} unused licenses' -f [math]::Round($data.EstimatedTotalSavings),$data.UnusedLicenses)
    return $data
}

# ============================================================================
#  Compliance Report
# ============================================================================

function New-MSPComplianceReport {
    [CmdletBinding()]
    param(
        [ValidateSet('CIS8','HIPAA','Custom')]
        [string]$Framework = 'CIS8',
        [string]$OutputPath = ('{0}\MSP_ComplianceReport.html' -f $env:TEMP)
    )

    $benchmark = & ('{0}\..\MSP_Tier3_Toolkit\Security\Get-FullCISBenchmark.ps1' -f $PSScriptRoot) -ErrorAction SilentlyContinue

    $html = @"
<!DOCTYPE html>
<html><head><meta charset=utf-8><title>Compliance Report -- $Framework</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0f172a;color:#e2e8f0;padding:24px}
h1{color:#38bdf8}.pass{color:#22c55e}.fail{color:#ef4444}.warn{color:#f59e0b}
table{width:100%;border-collapse:collapse;margin-top:16px}
th{background:#1e293b;color:#94a3b8;padding:8px 12px;text-align:left}
td{padding:8px 12px;border-bottom:1px solid #1e293b}
</style></head>
<body>
<h1>Compliance Report -- $Framework</h1>
<p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | Host: $env:COMPUTERNAME</p>
<h2>Overall Score: $($benchmark.Score)/$($benchmark.MaxScore)</h2>
$(if ($benchmark.Categories) { ('<table><tr><th>Category</th><th>Score</th><th>Status</th></tr>{0}</table>' -f ($benchmark.Categories | ForEach-Object { [string]$row = '<tr><td>' + $_.Category + '</td><td>' + $_.Score + '/' + $_.MaxScore + '</td><td class=' + $(if($_.Score -ge $_.MaxScore*0.8){'pass'}else{'fail'}) + '>' + [math]::Round($_.Score/$_.MaxScore*100) + '%</td></tr>'; $row })) })
<p style="margin-top:24px;color:#475569">MSP Tier 3 Toolkit v17 | New-MSPComplianceReport</p>
</body></html>
"@
    Set-Content -Path $OutputPath -Value $html -Encoding UTF8
    return [pscustomobject]@{ Framework=$Framework; Path=$OutputPath; Score=$benchmark.Score }
}

# ============================================================================
#  Report exporter
# ============================================================================

function Export-MSPReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        $InputObject,
        [ValidateSet('HTML','CSV','JSON','PDF')]
        [string]$Format = 'JSON',
        [string]$OutputPath
    )

    if (-not $OutputPath) {
        $ext = @{HTML='.html';CSV='.csv';JSON='.json';PDF='.html'}
        $OutputPath = ('{0}\MSP_Report_{1}{2}' -f $env:TEMP,(Get-Date -Format 'yyyyMMdd_HHmmss'),$ext[$Format])
    }

    switch ($Format) {
        'JSON' {
            $InputObject | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
        }
        'CSV' {
            $InputObject | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        }
        'HTML' {
            $body = $InputObject | ConvertTo-Html -Fragment
            $html = '<!DOCTYPE html><html><head><meta charset=utf-8><title>MSP Report</title><style>body{font-family:sans-serif;padding:20px}table{border-collapse:collapse}td,th{padding:6px 10px;border:1px solid #ccc}</style></head><body><h1>MSP Report</h1>' + $body + '</body></html>'
            Set-Content -Path $OutputPath -Value $html -Encoding UTF8
        }
        'PDF' {
            Export-MSPReport -InputObject $InputObject -Format HTML -OutputPath $OutputPath
            Write-Warning 'PDF export falls back to HTML. Install wkhtmltopdf for native PDF.'
        }
    }

    return [pscustomobject]@{ Format=$Format; Path=$OutputPath; SizeKB=[math]::Round((Get-Item $OutputPath).Length/1KB,1) }
}

# ============================================================================
#  Tenant scorecard
# ============================================================================

function Get-MSPTenantScorecard {
    [CmdletBinding()]
    param()

    $data = [pscustomobject]@{
        Timestamp  = (Get-Date).ToString('o')
        Tenants    = @()
    }

    $tenantList = Get-MSPTenant -ErrorAction SilentlyContinue
    if ($tenantList) {
        foreach ($t in $tenantList) {
            Select-MSPTenant -Name $t.Name -ErrorAction SilentlyContinue | Out-Null
            $score = [pscustomobject]@{
                TenantName = $t.Name
                SecurityScore = (& ('{0}\..\MSP_Tier3_Toolkit\Security\Get-SecurityPostureScore.ps1' -f $PSScriptRoot) -ErrorAction SilentlyContinue).Score
                PatchCompliance = (& ('{0}\..\MSP_Tier3_Toolkit\Security\Get-PatchCompliance.ps1' -f $PSScriptRoot) -ErrorAction SilentlyContinue).CompliancePct
            }
            $data.Tenants += $score
        }
    }

    return $data
}

# ============================================================================
#  Utilization trends
# ============================================================================

function Get-MSPUtilizationTrend {
    [CmdletBinding()]
    param(
        [int]$DurationMinutes = 5,
        [int]$SampleIntervalSec = 30
    )

    $samples = @()
    $endTime = (Get-Date).AddMinutes($DurationMinutes)
    while ((Get-Date) -lt $endTime) {
        $cpu = try { (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue).CounterSamples.CookedValue } catch { 0 }
        $mem = try { $os = Get-CimInstance Win32_OperatingSystem; [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1) } catch { 0 }
        $disk = try { $d = Get-Counter '\LogicalDisk(_Total)\% Free Space' -ErrorAction SilentlyContinue; [math]::Round(100 - $d.CounterSamples.CookedValue, 1) } catch { 0 }
        $net = try { $n = Get-Counter '\Network Interface(_Total)\Bytes Total/sec' -ErrorAction SilentlyContinue; [math]::Round($n.CounterSamples.CookedValue / 1MB, 2) } catch { 0 }

        $samples += [pscustomobject]@{
            Time=(Get-Date).ToString('HH:mm:ss')
            CPU=$cpu
            Memory=$mem
            DiskUsedPct=$disk
            NetworkMBps=$net
        }
        Start-Sleep -Seconds $SampleIntervalSec
    }

    return [pscustomobject]@{
        DurationMinutes=$DurationMinutes
        SampleCount=$samples.Count
        AvgCPU=[math]::Round(($samples | Measure-Object -Property CPU -Average).Average, 1)
        AvgMemory=[math]::Round(($samples | Measure-Object -Property Memory -Average).Average, 1)
        AvgDisk=[math]::Round(($samples | Measure-Object -Property DiskUsedPct -Average).Average, 1)
        AvgNetworkMBps=[math]::Round(($samples | Measure-Object -Property NetworkMBps -Average).Average, 2)
        Samples=$samples
    }
}

Export-ModuleMember -Function @(
    'New-MSPDashboard',
    'Get-MSPSLAMetrics',
    'Invoke-MSPCostOptimizer',
    'New-MSPComplianceReport',
    'Export-MSPReport',
    'Get-MSPTenantScorecard',
    'Get-MSPUtilizationTrend'
)
