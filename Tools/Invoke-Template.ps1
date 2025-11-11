<#
.SYNOPSIS
    MSP Toolkit - Template Runner
.DESCRIPTION
    Execute predefined script templates with saved parameters
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$TemplateName,

    [string[]]$ComputerName,

    [switch]$ListTemplates
)

# Import modules
$CorePath = "$PSScriptRoot\..\Core"
Import-Module "$CorePath\MSPToolkit.Config.psm1" -Force
Import-Module "$CorePath\MSPToolkit.Logging.psm1" -Force
Import-Module "$CorePath\MSPToolkit.Remote.psm1" -Force

Initialize-MSPLogging -ScriptName "TemplateRunner"
$config = Get-MSPConfig

$templatePath = Join-Path $PSScriptRoot "..\Templates"

# List available templates
if ($ListTemplates) {
    Write-MSPLog "═══ Available Templates ═══" -Level HEADER

    $templates = Get-ChildItem -Path $templatePath -Filter "*.json"

    if ($templates.Count -eq 0) {
        Write-MSPLog "No templates found in $templatePath" -Level WARNING
        return
    }

    foreach ($template in $templates) {
        $templateData = Get-Content $template.FullName | ConvertFrom-Json

        Write-Host ""
        Write-Host "  📋 " -NoNewline -ForegroundColor Cyan
        Write-Host $templateData.templateName -ForegroundColor Yellow
        Write-Host "     Category: " -NoNewline -ForegroundColor Gray
        Write-Host $templateData.category -ForegroundColor White
        Write-Host "     Description: " -NoNewline -ForegroundColor Gray
        Write-Host $templateData.description -ForegroundColor White
        Write-Host "     Scripts: " -NoNewline -ForegroundColor Gray
        Write-Host "$($templateData.scripts.Count) scripts" -ForegroundColor White
        Write-Host "     File: " -NoNewline -ForegroundColor Gray
        Write-Host $template.Name -ForegroundColor DarkGray
    }

    Write-Host ""
    return
}

# Interactive template selection
if (-not $TemplateName) {
    $templates = Get-ChildItem -Path $templatePath -Filter "*.json"

    if ($templates.Count -eq 0) {
        Show-MSPError -Message "No templates found!" -Details "Create templates in $templatePath"
        return
    }

    Write-MSPLog "═══ Select a Template ═══" -Level HEADER
    Write-Host ""

    for ($i = 0; $i -lt $templates.Count; $i++) {
        $templateData = Get-Content $templates[$i].FullName | ConvertFrom-Json

        Write-Host "  [$($i + 1)] " -NoNewline -ForegroundColor White
        Write-Host $templateData.templateName -NoNewline -ForegroundColor Cyan
        Write-Host " - $($templateData.description)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "  Select template (1-$($templates.Count)): " -NoNewline -ForegroundColor Yellow
    $selection = Read-Host

    [int]$index = 0
    if ([int]::TryParse($selection, [ref]$index) -and $index -ge 1 -and $index -le $templates.Count) {
        $TemplateName = $templates[$index - 1].BaseName
    } else {
        Show-MSPError -Message "Invalid selection"
        return
    }
}

# Load template
$templateFile = Join-Path $templatePath "$TemplateName.json"

if (-not (Test-Path $templateFile)) {
    Show-MSPError -Message "Template not found: $TemplateName" -Details $templateFile
    return
}

$template = Get-Content $templateFile | ConvertFrom-Json

Write-MSPLog "═══ Executing Template: $($template.templateName) ═══" -Level HEADER
Write-Host ""
Write-Host "  Description: " -NoNewline -ForegroundColor Gray
Write-Host $template.description -ForegroundColor White
Write-Host "  Scripts to run: " -NoNewline -ForegroundColor Gray
Write-Host $template.scripts.Count -ForegroundColor Yellow
Write-Host ""

if ($template.notes) {
    Write-Host "  📝 Notes: " -NoNewline -ForegroundColor Cyan
    Write-Host $template.notes -ForegroundColor Gray
    Write-Host ""
}

# Confirm execution
Write-Host "  Execute this template? (Y/N): " -NoNewline -ForegroundColor Yellow
$confirm = Read-Host

if ($confirm -ne 'Y' -and $confirm -ne 'y') {
    Write-MSPLog "Template execution cancelled" -Level WARNING
    return
}

# Execute scripts
$results = @()
$scriptNum = 0

foreach ($script in $template.scripts) {
    $scriptNum++
    $percentComplete = [int](($scriptNum / $template.scripts.Count) * 100)

    Write-MSPProgress -Activity "Executing Template" -Status "Running $($script.name) ($scriptNum of $($template.scripts.Count))" -PercentComplete $percentComplete

    Write-MSPLog "Running: $($script.name)" -Level INFO

    $result = [PSCustomObject]@{
        ScriptName = $script.name
        Status = 'Unknown'
        StartTime = Get-Date
        EndTime = $null
        Error = $null
    }

    try {
        # Build script path from ID
        $toolCatalog = @(
            @{ ID = 1; Path = "MSP_Tier3_Toolkit\SystemHealthReport.ps1" },
            @{ ID = 5; Path = "MSP_Tier3_Toolkit\M365UserProvisioning.ps1" },
            @{ ID = 6; Path = "MSP_Tier3_Toolkit\CleanupOldProfiles.ps1" },
            @{ ID = 7; Path = "Cleanup Script\Cleanup-Auto.ps1" },
            @{ ID = 12; Path = "MSP_Tier3_Toolkit\WindowsUpdateFix.ps1" }
        )

        $tool = $toolCatalog | Where-Object { $_.ID -eq $script.id }
        if (-not $tool) {
            throw "Script ID $($script.id) not found in catalog"
        }

        $scriptPath = Join-Path (Split-Path $PSScriptRoot) $tool.Path

        if (-not (Test-Path $scriptPath)) {
            throw "Script not found: $scriptPath"
        }

        # Execute script
        if ($ComputerName) {
            Invoke-MSPRemoteScriptFile -ComputerName $ComputerName -ScriptPath $scriptPath -Parameters $script.parameters
        } else {
            & $scriptPath @($script.parameters)
        }

        $result.Status = 'Success'
        Write-MSPLog "✓ Completed: $($script.name)" -Level SUCCESS
    }
    catch {
        $result.Status = 'Failed'
        $result.Error = $_.Exception.Message
        Write-MSPLog "✗ Failed: $($script.name) - $_" -Level ERROR

        if (-not $template.settings.continueOnError) {
            Write-MSPLog "Template execution stopped (continueOnError = false)" -Level WARNING
            break
        }
    }
    finally {
        $result.EndTime = Get-Date
        $results += $result
    }

    Write-Host ""
}

Write-Progress -Activity "Executing Template" -Completed

# Summary
Write-Host ""
Write-MSPLog "═══ Execution Summary ═══" -Level HEADER
Write-Host ""

$successCount = ($results | Where-Object { $_.Status -eq 'Success' }).Count
$failedCount = ($results | Where-Object { $_.Status -eq 'Failed' }).Count

Write-Host "  Total Scripts:    " -NoNewline -ForegroundColor Gray
Write-Host $results.Count -ForegroundColor White
Write-Host "  Successful:       " -NoNewline -ForegroundColor Gray
Write-Host $successCount -ForegroundColor Green
Write-Host "  Failed:           " -NoNewline -ForegroundColor Gray
Write-Host $failedCount -ForegroundColor $(if ($failedCount -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

# Detailed results
Write-MSPTable -Data $results -Properties @('ScriptName', 'Status', 'StartTime', 'Error') -Title "Detailed Results"

# Generate report if requested
if ($template.settings.generateReport) {
    $reportPath = Join-Path $config.paths.reports "TemplateExecution_$($template.templateName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $reportHtml = @"
<!DOCTYPE html>
<html>
<head>
    <title>Template Execution Report</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1000px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        .summary { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin: 20px 0; }
        .stat-box { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .stat-box h3 { margin: 0; font-size: 36px; }
        .stat-box p { margin: 10px 0 0 0; opacity: 0.9; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #34495e; color: white; }
        tr:hover { background: #f5f5f5; }
        .success { color: #27ae60; font-weight: bold; }
        .failed { color: #e74c3c; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>📋 Template Execution Report</h1>
        <p><strong>Template:</strong> $($template.templateName)</p>
        <p><strong>Description:</strong> $($template.description)</p>
        <p><strong>Executed:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>

        <div class="summary">
            <div class="stat-box">
                <h3>$($results.Count)</h3>
                <p>Total Scripts</p>
            </div>
            <div class="stat-box" style="background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);">
                <h3>$successCount</h3>
                <p>Successful</p>
            </div>
            <div class="stat-box" style="background: linear-gradient(135deg, #eb3349 0%, #f45c43 100%);">
                <h3>$failedCount</h3>
                <p>Failed</p>
            </div>
        </div>

        <h2>Execution Details</h2>
        <table>
            <tr>
                <th>Script Name</th>
                <th>Status</th>
                <th>Start Time</th>
                <th>End Time</th>
                <th>Error</th>
            </tr>
"@

    foreach ($result in $results) {
        $statusClass = if ($result.Status -eq 'Success') { 'success' } else { 'failed' }
        $reportHtml += @"
            <tr>
                <td>$($result.ScriptName)</td>
                <td class="$statusClass">$($result.Status)</td>
                <td>$($result.StartTime.ToString('HH:mm:ss'))</td>
                <td>$($result.EndTime.ToString('HH:mm:ss'))</td>
                <td>$($result.Error)</td>
            </tr>
"@
    }

    $reportHtml += @"
        </table>
    </div>
</body>
</html>
"@

    $reportHtml | Out-File -FilePath $reportPath -Encoding UTF8
    Write-MSPLog "Report saved: $reportPath" -Level SUCCESS
}

if ($successCount -eq $results.Count) {
    Show-MSPSuccess -Message "Template executed successfully!"
} else {
    Show-MSPError -Message "Template execution completed with errors" -Details "$failedCount of $($results.Count) scripts failed"
}
