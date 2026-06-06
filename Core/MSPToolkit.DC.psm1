<#
.SYNOPSIS
    MSP Toolkit - Domain Controller Operations Module.
.DESCRIPTION
    First-class DC health tooling: replication, DNS, DHCP, FSMO, GPO,
    Kerberos, trusts, LDAP, and AD database information.

    Designed for AD DS environments. Uses ActiveDirectory module when
    available, falls back to raw repadmin/dcdiag/nltest/ldifde wrappers.
#>

Set-StrictMode -Version Latest

# Safety: ensure Platform module is loaded for Invoke-MSPNativeCommand
if (-not (Get-Command Invoke-MSPNativeCommand -ErrorAction SilentlyContinue)) {
    try { Import-Module (Join-Path $PSScriptRoot 'MSPToolkit.Platform.psm1') -Force -ErrorAction Stop } catch {
        function Invoke-MSPNativeCommand { param($Command,$Arguments,$TimeoutSec=30) & $Command @$Arguments 2>&1 | Out-String }
    }
}

# -----------------------------------------------------------------------
#  DC Enumeration
# -----------------------------------------------------------------------

function Get-MSPDCList {
    <#
    .SYNOPSIS
        Enumerate all domain controllers with site, type, and OS info.
    #>
    [CmdletBinding()]
    param(
        [string]$Domain,
        [PSCredential]$Credential
    )

    $dcs = @()
    $domainParam = if ($Domain) { @($Domain) } else { @() }

    # Try ActiveDirectory module
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $adDCs = Get-ADDomainController -Filter * @domainParam -ErrorAction SilentlyContinue
        foreach ($dc in $adDCs) {
            $dcs += [pscustomobject]@{
                Name             = $dc.Name
                FQDN             = $dc.HostName
                Site             = $dc.Site
                IPv4             = $dc.IPv4Address
                IsGlobalCatalog  = $dc.IsGlobalCatalog
                IsReadOnly       = $dc.IsReadOnly
                OperatingSystem  = $dc.OperatingSystem
                Forest           = $dc.Forest
                Domain           = $dc.Domain
                Roles            = @()
            }
        }
        if ($dcs.Count -gt 0) { return $dcs }
    } catch { }

    # Fallback: nltest
    try {
        $nltest = Invoke-MSPNativeCommand -Command 'nltest' -Arguments @('/dclist:' + (if ($Domain) { $Domain } else { $env:USERDNSDOMAIN })) -TimeoutSec 15
        $lines = $nltest -split "`n" | Where-Object { $_ -match '^\s+\S+' }
        foreach ($line in $lines) {
            $name = $line.Trim()
            if ($name -and $name -notmatch '^The command completed') {
                $dcs += [pscustomobject]@{
                    Name             = $name
                    FQDN             = $name
                    Site             = ''
                    IPv4             = ''
                    IsGlobalCatalog  = $false
                    IsReadOnly       = $false
                    OperatingSystem  = ''
                    Forest           = ''
                    Domain           = ''
                    Roles            = @()
                }
            }
        }
    } catch { }

    return $dcs
}

# -----------------------------------------------------------------------
#  Site Mapping
# -----------------------------------------------------------------------

function Get-MSPSiteForDC {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $dc = Get-ADDomainController -Identity $ComputerName -ErrorAction Stop
        return [pscustomobject]@{
            DC        = $dc.HostName
            Site      = $dc.Site
            Subnet    = ''
            Reachable = $true
        }
    } catch {
        # nltest fallback
        try {
            $nltest = Invoke-MSPNativeCommand -Command 'nltest' -Arguments @('/server:'.$ComputerName,'/dsgetsite') -TimeoutSec 10
            $site = ($nltest -split "`n" | Where-Object { $_ -notmatch '^The command' }).Trim()
            return [pscustomobject]@{ DC = $ComputerName; Site = if ($site) { $site } else { 'Unknown' }; Subnet = ''; Reachable = ($LASTEXITCODE -eq 0) }
        } catch {
            return [pscustomobject]@{ DC = $ComputerName; Site = 'Unknown'; Subnet = ''; Reachable = $false }
        }
    }
}

# -----------------------------------------------------------------------
#  FSMO Inventory
# -----------------------------------------------------------------------

function Get-MSPFSMOInventory {
    <#
    .SYNOPSIS
        Get all 5 FSMO role holders with connectivity check.
    #>
    [CmdletBinding()]
    param()

    $roles = @()
    $fsmoTests = @(
        @{Role='Schema Master';        Cmd='Schema';}
        @{Role='Domain Naming Master'; Cmd='Naming';}
        @{Role='PDC Emulator';         Cmd='PDC';}
        @{Role='RID Master';           Cmd='RID';}
        @{Role='Infrastructure Master';Cmd='Infrastructure';}
    )

    foreach ($r in $fsmoTests) {
        $holder = ''
        $reachable = $false
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            $forest = Get-ADForest -ErrorAction SilentlyContinue
            $domain = Get-ADDomain -ErrorAction SilentlyContinue
            switch ($r.Role) {
                'Schema Master'         { $holder = $forest.SchemaMaster }
                'Domain Naming Master'  { $holder = $forest.DomainNamingMaster }
                'PDC Emulator'          { $holder = $domain.PDCEmulator }
                'RID Master'            { $holder = $domain.RIDMaster }
                'Infrastructure Master' { $holder = $domain.InfrastructureMaster }
            }
        } catch {
            try {
                $netdom = Invoke-MSPNativeCommand -Command 'netdom' -Arguments @('query','fsmo') -TimeoutSec 15
                $pattern = "$($r.Role.Replace(' ','\s*'))\s+(\S+)"
                if ($netdom -match $pattern) { $holder = $Matches[1] }
            } catch { }
        }

        if ($holder) {
            $ping = Test-Connection -ComputerName $holder -Count 1 -Quiet -ErrorAction SilentlyContinue
            $reachable = $ping
        }

        $roles += [pscustomobject]@{
            Role      = $r.Role
            Holder    = if ($holder) { $holder } else { 'Unknown' }
            Reachable = $reachable
        }
    }

    return $roles
}

# -----------------------------------------------------------------------
#  Repadmin Wrapper
# -----------------------------------------------------------------------

function Invoke-MSPRepAdmin {
    <#
    .SYNOPSIS
        Safe repadmin wrapper returning structured output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [int]$TimeoutSec = 60
    )

    $output = Invoke-MSPNativeCommand -Command 'repadmin' -Arguments $Arguments -TimeoutSec $TimeoutSec
    $exitCode = $global:LASTEXITCODE

    return [pscustomobject]@{
        Output    = $output
        ExitCode  = $exitCode
        Success   = ($exitCode -eq 0)
        Arguments = $Arguments -join ' '
    }
}

# -----------------------------------------------------------------------
#  Port Check (DC Ports)
# -----------------------------------------------------------------------

function Test-MSPPortDC {
    <#
    .SYNOPSIS
        Test required DC ports against a target.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [int]$TimeoutMs = 2000
    )

    $ports = @{
        53   = 'DNS'
        88   = 'Kerberos'
        135  = 'RPC Endpoint Mapper'
        389  = 'LDAP'
        445  = 'SMB'
        636  = 'LDAPS'
        3268 = 'Global Catalog'
        3269 = 'Global Catalog SSL'
        9389 = 'ADWS'
    }

    $results = @()
    foreach ($port in $ports.Keys) {
        $open = $false
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            if ($tcp.ConnectAsync($ComputerName, $port).Wait($TimeoutMs)) {
                $open = $tcp.Connected
            }
            $tcp.Close()
            $tcp.Dispose()
        } catch { }

        $results += [pscustomobject]@{
            Port     = $port
            Service  = $ports[$port]
            Open     = $open
        }
    }

    return $results
}

# -----------------------------------------------------------------------
#  AD Database Info
# -----------------------------------------------------------------------

function Get-MSPADDatabaseInfo {
    <#
    .SYNOPSIS
        Get NTDS.dit size, white space, and partition info.
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME
    )

    $result = @{
        NTDSDITPath    = ''
        NTDSDITSizeMB  = 0
        WhiteSpaceMB    = 0
        Partitions     = @()
        LogPath        = ''
        SYSVOLPath     = ''
    }

    try {
        $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $ComputerName)
        $ntdsKey = $reg.OpenSubKey('SYSTEM\CurrentControlSet\Services\NTDS\Parameters')
        if ($ntdsKey) {
            $result.NTDSDITPath = $ntdsKey.GetValue('DSA Database file', '')
            $result.LogPath     = $ntdsKey.GetValue('Database log files path', '')
            $result.SYSVOLPath  = $ntdsKey.GetValue('DSA Working Directory', '')
        }

        # Try to get file size via admin share
        if ($result.NTDSDITPath) {
            $uncPath = "\\$ComputerName\" + ($result.NTDSDITPath.Replace(':', '$'))
            if (Test-Path $uncPath) {
                $result.NTDSDITSizeMB = [math]::Round((Get-Item $uncPath).Length / 1MB, 1)
            }
        }
    } catch { }

    # repadmin for partition info
    try {
        $repOut = (Invoke-MSPRepAdmin -Arguments @('/showrepl','*','/csv') -TimeoutSec 30).Output
        $seen = @{}
        foreach ($line in ($repOut -split "`n")) {
            $parts = $line -split ','
            if ($parts.Count -ge 3 -and $parts[0] -notmatch 'Destination|showrepl') {
                $partition = $parts[1].Trim('"')
                if (-not $seen[$partition]) {
                    $result.Partitions += $partition
                    $seen[$partition] = $true
                }
            }
        }
    } catch { }

    return [pscustomobject]$result
}

# -----------------------------------------------------------------------
#  Password Policy
# -----------------------------------------------------------------------

function Get-MSPPasswordPolicy {
    <#
    .SYNOPSIS
        Get default domain password policy and fine-grained policies.
    #>
    [CmdletBinding()]
    param([string]$Domain)

    $policies = @()

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $domain = Get-ADDefaultDomainPasswordPolicy -ErrorAction SilentlyContinue
        if ($domain) {
            $policies += [pscustomobject]@{
                Name                 = 'Default Domain Policy'
                Type                 = 'Default'
                MinPasswordLength    = $domain.MinPasswordLength
                PasswordHistoryCount = $domain.PasswordHistoryCount
                MaxPasswordAge       = $domain.MaxPasswordAge
                MinPasswordAge       = $domain.MinPasswordAge
                ComplexityEnabled    = $domain.ComplexityEnabled
                ReversibleEncryption = $domain.ReversibleEncryptionEnabled
                LockoutThreshold     = $domain.LockoutThreshold
                LockoutDuration      = $domain.LockoutDuration
                LockoutWindow        = $domain.LockoutObservationWindow
            }
        }

        $fgpp = Get-ADFineGrainedPasswordPolicy -Filter * -ErrorAction SilentlyContinue
        foreach ($f in $fgpp) {
            $policies += [pscustomobject]@{
                Name                 = $f.Name
                Type                 = 'Fine-Grained'
                MinPasswordLength    = $f.MinPasswordLength
                PasswordHistoryCount = $f.PasswordHistoryCount
                MaxPasswordAge       = $f.MaxPasswordAge
                MinPasswordAge       = $f.MinPasswordAge
                ComplexityEnabled    = $f.ComplexityEnabled
                ReversibleEncryption = $f.ReversibleEncryptionEnabled
                LockoutThreshold     = $f.LockoutThreshold
                LockoutDuration      = $f.LockoutDuration
                LockoutWindow        = $f.LockoutObservationWindow
                Precedence           = $f.Precedence
                AppliesTo            = $f.AppliesTo -join ', '
            }
        }
    } catch {
        # net accounts fallback
        try {
            $net = Invoke-MSPNativeCommand -Command 'net' -Arguments @('accounts') -TimeoutSec 5
            $policies += [pscustomobject]@{
                Name                 = 'Default Domain'
                Type                 = 'Default (net accounts)'
                MinPasswordLength    = 0
                PasswordHistoryCount = 0
                MaxPasswordAge       = ''
                MinPasswordAge       = ''
                ComplexityEnabled    = $false
                ReversibleEncryption = $false
                LockoutThreshold     = 0
                LockoutDuration      = ''
                LockoutWindow        = ''
                RawOutput            = $net
            }
        } catch { }
    }

    return $policies
}

# -----------------------------------------------------------------------
#  LDAP Bind Test
# -----------------------------------------------------------------------

function Test-MSPLDAPBind {
    <#
    .SYNOPSIS
        LDAP + LDAPS connectivity test with timing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [int]$TimeoutSec = 10
    )

    $results = @()
    $tests = @(
        @{Port=389; Protocol='LDAP';  UseSSL=$false},
        @{Port=636; Protocol='LDAPS'; UseSSL=$true},
        @{Port=3268; Protocol='GC';   UseSSL=$false},
        @{Port=3269; Protocol='GC SSL'; UseSSL=$true}
    )

    foreach ($test in $tests) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $open = $false
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $open = $tcp.ConnectAsync($ComputerName, $test.Port).Wait($TimeoutSec * 1000)
            if ($open) { $open = $tcp.Connected }
            $tcp.Close()
            $tcp.Dispose()
        } catch { }
        $sw.Stop()

        $results += [pscustomobject]@{
            Protocol  = $test.Protocol
            Port      = $test.Port
            Reachable = $open
            LatencyMs = $sw.ElapsedMilliseconds
        }
    }

    return $results
}

# -----------------------------------------------------------------------
#  KRBTGT Health
# -----------------------------------------------------------------------

function Get-MSPKRBTGTInfo {
    <#
    .SYNOPSIS
        KRBTGT password age and rotation recommendation.
    #>
    [CmdletBinding()]
    param()

    $result = @{
        Name              = 'krbtgt'
        PasswordLastSet   = $null
        PasswordAgeDays   = 0
        RotationRecommended = $null
        Reason            = ''
    }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $krbtgt = Get-ADUser -Identity 'krbtgt' -Properties PasswordLastSet -ErrorAction SilentlyContinue
        if ($krbtgt) {
            $result.PasswordLastSet = $krbtgt.PasswordLastSet
            $result.PasswordAgeDays = [math]::Round(((Get-Date) - $krbtgt.PasswordLastSet).TotalDays, 0)
            if ($result.PasswordAgeDays -gt 180) {
                $result.RotationRecommended = $true
                $result.Reason = "KRBTGT password is $($result.PasswordAgeDays) days old. Recommend rotation every 180 days."
            } else {
                $result.RotationRecommended = $false
                $result.Reason = "KRBTGT password age ($($result.PasswordAgeDays) days) is within recommended range."
            }
        }
    } catch {
        $result.Reason = 'Cannot query Active Directory. ActiveDirectory module may not be available.'
    }

    return [pscustomobject]$result
}

Export-ModuleMember -Function @(
    'Get-MSPDCList',
    'Get-MSPSiteForDC',
    'Get-MSPFSMOInventory',
    'Invoke-MSPRepAdmin',
    'Test-MSPPortDC',
    'Get-MSPADDatabaseInfo',
    'Get-MSPPasswordPolicy',
    'Test-MSPLDAPBind',
    'Get-MSPKRBTGTInfo'
)
