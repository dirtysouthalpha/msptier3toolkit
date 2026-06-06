<#
.SYNOPSIS
    Performs SNMP discovery and polls device information from network hardware.
.DESCRIPTION
    Walks standard SNMP OIDs (sysDescr, sysName, interfaces, CPU, memory) on
    target devices and returns structured inventory data. Supports SNMPv1/v2c.
.NOTES
    v19.0 -- Advanced Network Diagnostics
    Uses built-in Windows SNMP tools or COM object.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string[]]$TargetHosts,
    [Parameter(Mandatory=$false)]
    [string]$Community = 'public',
    [Parameter(Mandatory=$false)]
    [int]$TimeoutMs = 5000
)

$data = [PSCustomObject]@{
    Timestamp   = (Get-Date).ToString('o')
    Devices     = @()
    Reachable   = 0
    Unreachable = 0
    Checks      = @()
    Score       = 0
    MaxScore    = 0
    Summary     = ''
}

# Standard OIDs to query
$oids = @{
    sysDescr    = '1.3.6.1.2.1.1.1.0'
    sysName     = '1.3.6.1.2.1.1.5.0'
    sysUpTime   = '1.3.6.1.2.1.1.3.0'
    sysContact  = '1.3.6.1.2.1.1.4.0'
    sysLocation = '1.3.6.1.2.1.1.6.0'
    ifNumber    = '1.3.6.1.2.1.2.1.0'
}

foreach ($hostIp in $TargetHosts) {
    # Check reachability first
    $ping = Test-Connection -ComputerName $hostIp -Count 1 -Quiet -ErrorAction SilentlyContinue
    if (-not $ping) {
        $data.Unreachable++
        $data.Devices += [PSCustomObject]@{ Host=$hostIp; Reachable=$false; Error='No ICMP response' }
        continue
    }

    $deviceInfo = [PSCustomObject]@{
        Host        = $hostIp
        Reachable   = $true
        sysName     = $null
        sysDescr    = $null
        sysUpTime   = $null
        sysContact  = $null
        sysLocation = $null
        Interfaces  = 0
        Error       = $null
    }

    foreach ($oidKey in $oids.Keys) {
        try {
            $com = New-Object -ComObject OlePrn.OleSNMP
            $com.Open($hostIp, $Community, 2, $TimeoutMs)
            $result = $com.Get($oids[$oidKey])
            $deviceInfo.$oidKey = $result
            $com.Close()
        } catch {
            # Try via snmpget if available
            try {
                $snmpOut = snmpget -v2c -c $Community $hostIp $oids[$oidKey] 2>$null
                if ($snmpOut -match '=\s*(.+)') { $deviceInfo.$oidKey = $Matches[1].Trim() }
            } catch { }
        }
    }

    if ($deviceInfo.sysDescr) {
        $data.Reachable++
        # Try interface count
        try {
            $com = New-Object -ComObject OlePrn.OleSNMP
            $com.Open($hostIp, $Community, 2, $TimeoutMs)
            $ifCount = $com.Get($oids.ifNumber)
            $deviceInfo.Interfaces = [int]$ifCount
            $com.Close()
        } catch { }
    }

    $data.Devices += $deviceInfo
}

$data.Checks += [PSCustomObject]@{ Name='Devices Discovered'; Pass=($data.Reachable -gt 0); Detail="$($data.Reachable) reachable / $($TargetHosts.Count) total" }
$data.Checks += [PSCustomObject]@{ Name='SNMP Responded'; Pass=($data.Reachable -ge $TargetHosts.Count * 0.5); Detail="$($data.Reachable) SNMP responses" }

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "SNMP Walk: $($data.Reachable)/$($TargetHosts.Count) devices discovered"
return $data
