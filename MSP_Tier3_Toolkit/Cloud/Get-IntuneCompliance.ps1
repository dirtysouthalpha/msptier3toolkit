<#
.SYNOPSIS
    Reports Intune device compliance and enrollment status.
.DESCRIPTION
    Uses Microsoft Graph API to query Intune managed devices, compliance state,
    non-compliant reasons, enrollment profiles, and configuration drift.
.NOTES
    v14.0 -- Cloud & Hybrid Operations
    Requires: MSPToolkit.Graph module loaded
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$DetailReport
)

$data = [PSCustomObject]@{
    Timestamp          = (Get-Date).ToString('o')
    TotalDevices       = 0
    CompliantDevices   = 0
    NonCompliant       = 0
    InGracePeriod      = 0
    NotEvaluated       = 0
    TopNonCompliance   = @()
    PlatformBreakdown  = @{}
    Checks             = @()
    Score              = 0
    MaxScore           = 0
    Summary            = ''
}

# Attempt via Graph
try {
    $devices = Invoke-MSPGraph -Resource 'deviceManagement/managedDevices' -ErrorAction Stop
    if ($devices.value) {
        $data.TotalDevices = $devices.value.Count
        
        foreach ($d in $devices.value) {
            switch ($d.complianceState) {
                'compliant' { $data.CompliantDevices++ }
                'noncompliant' { $data.NonCompliant++ }
                'configManager' { $data.NotEvaluated++ }
                'inGracePeriod' { $data.InGracePeriod++ }
                default { $data.NotEvaluated++ }
            }
            $os = $d.operatingSystem
            if (-not $data.PlatformBreakdown[$os]) { $data.PlatformBreakdown[$os] = 0 }
            $data.PlatformBreakdown[$os]++
        }

        $data.Checks += [PSCustomObject]@{ Name='Intune Connected'; Pass=$true; Detail="$($data.TotalDevices) devices found" }
        $data.Checks += [PSCustomObject]@{ Name='Compliance Rate'; Pass=($data.CompliantDevices/$data.TotalDevices -ge 0.80); Detail="$([math]::Round($data.CompliantDevices/$data.TotalDevices*100,1))% compliant" }

        # Top non-compliance reasons
        $nonComp = Invoke-MSPGraph -Resource 'deviceManagement/deviceCompliancePolicySettingStateSummaries' -ErrorAction SilentlyContinue
        if ($nonComp.value) {
            $data.TopNonCompliance = @($nonComp.value | Sort-Object { $_.nonCompliantDeviceCount } -Descending | Select-Object -First 5 | ForEach-Object {
                [PSCustomObject]@{ Setting=$_.settingName; Count=$_.nonCompliantDeviceCount }
            })
        }
    } else {
        $data.Checks += [PSCustomObject]@{ Name='Intune Connected'; Pass=$false; Detail='No devices returned' }
    }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Intune Connected'; Pass=$false; Detail="Graph error: $($_.Exception.Message)" }
}

# Local enrollment check
$enrollmentReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue
$mgmtReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device' -ErrorAction SilentlyContinue
$data.Checks += [PSCustomObject]@{ Name='This Device Enrolled'; Pass=($enrollmentReg -or $mgmtReg); Detail=$(if($enrollmentReg -or $mgmtReg){'MDM enrolled'}else{'Not enrolled'}) }

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Intune: $($data.Score)/$($data.MaxScore) -- $($data.TotalDevices) devices | $($data.CompliantDevices) compliant | $($data.NonCompliant) non-compliant"

return $data
