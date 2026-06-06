<#
.SYNOPSIS
    MSP Toolkit - Certificate Inventory & Expiry Monitor.
.DESCRIPTION
    Enumerates all certificates in LocalMachine and CurrentUser stores,
    reports expiry timeline, weak algorithm detection (SHA-1, MD5),
    and flags certificates expiring within warning/critical thresholds.
#>
#Requires -Version 5.1
[CmdletBinding()]
param([int]$WarningDays = 30, [int]$CriticalDays = 7)

$ErrorActionPreference = 'Continue'
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
try { Import-Module (Join-Path $toolkitRoot 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch { }
$errors = [System.Collections.Generic.List[string]]::new()
$data = @{ Certs=@(); Expiring=@(); Expired=@(); WeakAlgorithms=@(); Summary=@{} }

try {
    $stores = @('Root','CA','My','TrustedPublisher','TrustedDevices','AuthRoot','Remote Desktop','TrustedPeople','SmartCardRoot')
    $locations = @('LocalMachine','CurrentUser')

    foreach ($loc in $locations) {
        foreach ($storeName in $stores) {
            try {
                $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName, $loc)
                $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
                
                foreach ($cert in $store.Certificates) {
                    $daysLeft = [math]::Round(($cert.NotAfter - (Get-Date)).TotalDays, 0)
                    $algo = $cert.SignatureAlgorithm.FriendlyName
                    $weakAlgo = ($algo -match 'sha1|md5' -or $cert.PublicKey.Key.KeySize -lt 2048)
                    
                    $certObj = [pscustomobject]@{
                        Subject      = $cert.Subject
                        Issuer       = $cert.Issuer
                        Thumbprint   = $cert.Thumbprint
                        NotBefore    = $cert.NotBefore.ToString('yyyy-MM-dd')
                        NotAfter     = $cert.NotAfter.ToString('yyyy-MM-dd')
                        DaysLeft     = $daysLeft
                        Algorithm    = $algo
                        KeySize      = $cert.PublicKey.Key.KeySize
                        HasPrivateKey= $cert.HasPrivateKey
                        Store        = "$loc\\$storeName"
                        IsExpired    = ($daysLeft -le 0)
                        IsExpiring   = ($daysLeft -le $WarningDays -and $daysLeft -gt 0)
                        IsWeakAlgo   = $weakAlgo
                    }
                    
                    $data.Certs += $certObj
                    if ($certObj.IsExpiring) { $data.Expiring += $certObj }
                    if ($certObj.IsExpired) { $data.Expired += $certObj }
                    if ($weakAlgo) { $data.WeakAlgorithms += $certObj }
                }
                $store.Close()
            } catch { }
        }
    }

    $data.Summary = @{
        Total       = $data.Certs.Count
        Expiring    = $data.Expiring.Count
        Expired     = $data.Expired.Count
        WeakAlgo    = $data.WeakAlgorithms.Count
        UniqueSubjects = ($data.Certs | Select-Object -ExpandProperty Subject -Unique).Count
    }
} catch { $errors.Add("Certificate enumeration: $($_.Exception.Message)") }

$summary = "Certs: $($data.Summary.Total) total | Expiring: $($data.Summary.Expiring) | Expired: $($data.Summary.Expired) | Weak algo: $($data.Summary.WeakAlgo)"

if (Get-Command New-MSPResult -ErrorAction SilentlyContinue) {
    New-MSPResult -Tool 'Get-CertificateInventory' -Status $(if ($data.Summary.Expired -gt 0) {'Warning'} elseif ($data.Summary.Expiring -gt 0) {'Warning'} else {'Success'}) `
        -Summary $summary -Data $data -Errors $errors.ToArray() `
        -Metrics @{ Total=$data.Summary.Total; Expiring=$data.Summary.Expiring; Expired=$data.Summary.Expired; WeakAlgo=$data.Summary.WeakAlgo }
} else {
    [pscustomobject]@{ Tool='Get-CertificateInventory'; Status=$(if ($data.Summary.Expired -gt 0) {'Warning'} elseif ($data.Summary.Expiring -gt 0) {'Warning'} else {'Success'}); Summary=$summary; Data=$data; Errors=$errors.ToArray() }
}
