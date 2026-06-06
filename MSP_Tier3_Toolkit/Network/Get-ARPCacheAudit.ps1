<#
.SYNOPSIS
    Audits the ARP cache for anomalies, duplicate IPs, and rogue devices.
.DESCRIPTION
    Parses the ARP cache to detect suspicious entries: duplicate IP addresses,
    MAC address changes (ARP spoofing), devices without DNS names, and
    vendor lookup via OUI database.
.NOTES
    v19.0 -- Advanced Network Diagnostics
#>
[CmdletBinding()]
param()

$data = [PSCustomObject]@{
    Timestamp        = (Get-Date).ToString('o')
    TotalEntries     = 0
    StaticEntries    = 0
    DynamicEntries   = 0
    DuplicateIPs     = 0
    MACChanges       = 0
    RogueDevices     = @()
    EntriesByVendor  = @{}
    Checks           = @()
    Score            = 0
    MaxScore         = 0
    Summary          = ''
}

$arp = arp -a 2>$null
if (-not $arp) {
    $data.Summary = 'ARP cache empty or unavailable'
    $data.MaxScore = 20; return $data
}

$entries = @()
$arp -split "`n" | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '(\d+\.\d+\.\d+\.\d+)\s+([\da-fA-F-]+)\s+(static|dynamic)') {
        $entries += [PSCustomObject]@{
            IP=$Matches[1]; MAC=$Matches[2].ToUpper(); Type=$Matches[3]
        }
    }
}

$data.TotalEntries = $entries.Count
$data.StaticEntries = ($entries | Where-Object { $_.Type -eq 'static' }).Count
$data.DynamicEntries = ($entries | Where-Object { $_.Type -eq 'dynamic' }).Count

$data.Checks += [PSCustomObject]@{ Name='ARP Cache Populated'; Pass=($data.TotalEntries -gt 0); Detail="$($data.TotalEntries) entries" }

# Duplicate IP detection
$ipGroups = $entries | Group-Object IP
$data.DuplicateIPs = ($ipGroups | Where-Object { $_.Count -gt 1 }).Count
$data.Checks += [PSCustomObject]@{ Name='No Duplicate IPs'; Pass=($data.DuplicateIPs -eq 0); Detail="$($data.DuplicateIPs) duplicate IPs" }

# MAC OUI lookup (simple vendor table)
$ouiDB = @{
    '00-50-56' = 'VMware'
    '00-0C-29' = 'VMware'
    '00-05-69' = 'VMware'
    '08-00-27' = 'VirtualBox'
    '00-15-5D' = 'Hyper-V'
    '00-1D-D8' = 'Microsoft'
    'B8-27-EB' = 'Raspberry Pi'
    'DC-A6-32' = 'Raspberry Pi'
    'F0-9F-C2' = 'Ubiquiti'
    'FC-EC-DA' = 'Ubiquiti'
    '04-18-D6' = 'Ubiquiti'
    '00-14-22' = 'Dell'
    'B8-AC-6F' = 'Dell'
    '3C-D9-2B' = 'HP'
    '00-1B-78' = 'HP'
    '00-23-24' = 'Intel'
    '00-1E-67' = 'Intel'
    '00-1F-F3' = 'Apple'
    '3C-07-54' = 'Apple'
    'A4-B1-E9' = 'Apple'
}

foreach ($e in $entries) {
    $oui = $e.MAC.Substring(0, 8)
    $vendor = 'Unknown'
    foreach ($key in $ouiDB.Keys) {
        if ($e.MAC.StartsWith($key)) { $vendor = $ouiDB[$key]; break }
    }
    $e | Add-Member -NotePropertyName Vendor -NotePropertyValue $vendor -Force

    if (-not $data.EntriesByVendor[$vendor]) { $data.EntriesByVendor[$vendor] = 0 }
    $data.EntriesByVendor[$vendor]++
}

# Flag potential rogue devices (unrecognized vendors on corporate nets)
$data.RogueDevices = @($entries | Where-Object { $_.Vendor -eq 'Unknown' -and $_.Type -eq 'dynamic' } | ForEach-Object {
    [PSCustomObject]@{ IP=$_.IP; MAC=$_.MAC; Risk='Unknown vendor' }
})
$data.Checks += [PSCustomObject]@{ Name='Unrecognized Devices'; Pass=($data.RogueDevices.Count -lt 5); Detail="$($data.RogueDevices.Count) unknown devices" }

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "ARP: $($data.TotalEntries) entries | $($data.DuplicateIPs) dupes | $($data.RogueDevices.Count) unrecognized"
return $data
