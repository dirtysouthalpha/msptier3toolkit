<#
.SYNOPSIS
    Run the full Pester suite. Installs Pester 5 if missing.
.EXAMPLE
    .\Invoke-Tests.ps1
#>
[CmdletBinding()]
param([switch]$CI)

if (-not (Get-Module -ListAvailable -Name Pester | Where-Object Version -ge '5.0.0')) {
    Install-Module Pester -MinimumVersion 5.5.0 -Force -SkipPublisherCheck -Scope CurrentUser
}
Import-Module Pester -MinimumVersion 5.5.0

$cfg = New-PesterConfiguration
$cfg.Run.Path = $PSScriptRoot
$cfg.Output.Verbosity = if ($CI) { 'Detailed' } else { 'Normal' }
$cfg.Run.Exit = $CI.IsPresent
$cfg.TestResult.Enabled = $CI.IsPresent
$cfg.TestResult.OutputPath = Join-Path $PSScriptRoot 'TestResults.xml'
$cfg.TestResult.OutputFormat = 'NUnitXml'

Invoke-Pester -Configuration $cfg
