<#
.SYNOPSIS
    Checks on-premises Exchange Server health, queues, and DAG replication.
.DESCRIPTION
    Validates Exchange services, transport queue depth, DAG copy status,
    mailbox database mount state, and certificate expiry.
.NOTES
    v15.0 -- Application & Database Health
#>
[CmdletBinding()]
param()

$data = [PSCustomObject]@{
    Timestamp          = (Get-Date).ToString('o')
    ExchangeInstalled  = $false
    ExchangeVersion    = $null
    ServicesRunning    = 0
    ServicesTotal      = 0
    TransportQueues    = @()
    QueueTotalCount    = 0
    DAGConfigured      = $false
    DAGCopyHealthy     = $true
    DatabaseCount      = 0
    DatabasesMounted   = 0
    CertExpiringSoon   = 0
    Checks             = @()
    Score              = 0
    MaxScore           = 0
    Summary            = ''
}

# Check Exchange installed
$exReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup' -ErrorAction SilentlyContinue
if (-not $exReg) { $exReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ExchangeServer\v14\Setup' -ErrorAction SilentlyContinue }
$data.ExchangeInstalled = ($null -ne $exReg)

if ($data.ExchangeInstalled) {
    $data.ExchangeVersion = "$($exReg.MsiProductMajor).$($exReg.MsiProductMinor)"
}

$data.Checks += [PSCustomObject]@{ Name='Exchange Installed'; Pass=$data.ExchangeInstalled; Detail=$(if($data.ExchangeInstalled){"v$($data.ExchangeVersion)"}else{'Not installed'}) }

if (-not $data.ExchangeInstalled) {
    $data.Summary = 'Exchange Server not detected on this machine'
    $data.MaxScore = 20
    $data.Score = 0
    return $data
}

# Check Exchange services
$exSvcs = @(
    'MSExchangeTransport', 'MSExchangeIS', 'MSExchangeADTopology',
    'MSExchangeMailboxAssistants', 'MSExchangeFrontEndTransport',
    'MSExchangeDelivery', 'MSExchangeSubmission', 'MSExchangeServiceHost'
)
foreach ($sn in $exSvcs) {
    $svc = Get-Service -Name $sn -ErrorAction SilentlyContinue
    $data.ServicesTotal++
    if ($svc -and $svc.Status -eq 'Running') { $data.ServicesRunning++ }
}
$data.Checks += [PSCustomObject]@{ Name='Exchange Services'; Pass=($data.ServicesRunning -ge ($data.ServicesTotal - 2)); Detail="$($data.ServicesRunning)/$($data.ServicesTotal) running" }

# Exchange Management Shell checks -- try modern module first, then snapin
try {
    # Exchange 2016+ uses ExchangeManagement module
    $exMod = Get-Module -Name ExchangeManagement -ListAvailable -ErrorAction SilentlyContinue
    if ($exMod) {
        Import-Module ExchangeManagement -ErrorAction Stop
    } else {
        # Exchange 2010/2013 uses snapin
        Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction Stop
    }
    
    # Transport queues
    $queues = Get-Queue -ErrorAction SilentlyContinue
    if ($queues) {
        $data.QueueTotalCount = ($queues | Measure-Object -Property MessageCount -Sum).Sum
        $data.TransportQueues = @($queues | Select-Object Identity, Status, MessageCount, NextHopDomain | Sort-Object MessageCount -Descending)
        $data.Checks += [PSCustomObject]@{ Name='Queue Depth OK'; Pass=($data.QueueTotalCount -lt 1000); Detail="$($data.QueueTotalCount) total messages queued" }
    } else {
        $data.Checks += [PSCustomObject]@{ Name='Queue Depth OK'; Pass=$true; Detail='Queues empty' }
    }

    # DAG health
    try {
        $dag = Get-DatabaseAvailabilityGroup -ErrorAction SilentlyContinue
        if ($dag) {
            $data.DAGConfigured = $true
            $copies = Get-MailboxDatabaseCopyStatus -ErrorAction SilentlyContinue
            $failedCopies = ($copies | Where-Object { $_.Status -ne 'Mounted' -and $_.Status -ne 'Healthy' }).Count
            $data.DAGCopyHealthy = ($failedCopies -eq 0)
            $data.Checks += [PSCustomObject]@{ Name='DAG Copies Healthy'; Pass=$data.DAGCopyHealthy; Detail=$(if($data.DAGCopyHealthy){'All copies healthy'}else{"$failedCopies unhealthy copies"}) }
        } else {
            $data.Checks += [PSCustomObject]@{ Name='DAG Copies Healthy'; Pass=$true; Detail='No DAG configured' }
        }
    } catch { $data.Checks += [PSCustomObject]@{ Name='DAG Copies Healthy'; Pass=$false; Detail='Could not query' } }

    # Database mount state
    $dbs = Get-MailboxDatabase -Status -ErrorAction SilentlyContinue
    if ($dbs) {
        $data.DatabaseCount = $dbs.Count
        $data.DatabasesMounted = ($dbs | Where-Object { $_.Mounted }).Count
        $data.Checks += [PSCustomObject]@{ Name='Databases Mounted'; Pass=($data.DatabasesMounted -eq $data.DatabaseCount); Detail="$($data.DatabasesMounted)/$($data.DatabaseCount) mounted" }
    }

    # Certificate expiry
    $certs = Get-ExchangeCertificate -ErrorAction SilentlyContinue
    if ($certs) {
        $expiringCert = ($certs | Where-Object { $_.NotAfter -lt (Get-Date).AddDays(30) -and $_.Services -ne 'None' }).Count
        $data.CertExpiringSoon = $expiringCert
        $data.Checks += [PSCustomObject]@{ Name='No Expiring Certs'; Pass=($data.CertExpiringSoon -eq 0); Detail="$expiringCert cert(s) expiring within 30d" }
    }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='EMS Snapin'; Pass=$false; Detail="Error: $($_.Exception.Message)" }
}

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Exchange: $($data.Score)/$($data.MaxScore) -- v$($data.ExchangeVersion) | $($data.DatabasesMounted)/$($data.DatabaseCount) DBs | Queue: $($data.QueueTotalCount)"

return $data
