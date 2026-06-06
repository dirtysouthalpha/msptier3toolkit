<#
.SYNOPSIS
    MSP Toolkit - Common helpers shared across every script.
.DESCRIPTION
    Single source of truth for things that used to be copy-pasted into
    every script: admin checks, paths, retries, structured-result objects,
    safe JSON writers, and OS-fact gatherers.

    Loaded by MSPToolkit.psd1; you should never need to Import-Module this
    directly from a script -- `Import-Module MSPToolkit` pulls it in.
#>

Set-StrictMode -Version Latest

# Session id assigned once per module load -- used by New-MSPResult so every
# emitted record carries the same correlation id for the session.
$Script:MSPSessionId = ([guid]::NewGuid().ToString('N').Substring(0,12))

# -------------------------------------------------------------------------
#  Privilege / context
# -------------------------------------------------------------------------

function Test-MSPElevation {
    <#
    .SYNOPSIS
        Returns $true when running as Administrator. Mirrors
        Test-MSPAdminRights in the Config module so any module can ask.
    #>
    [CmdletBinding()]
    param()
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-MSPElevation {
    <#
    .SYNOPSIS
        Throws a friendly terminating error if not elevated.
    #>
    [CmdletBinding()]
    param([string]$Operation = 'this operation')

    if (-not (Test-MSPElevation)) {
        throw "Administrator privileges are required for $Operation. Re-launch PowerShell as Administrator."
    }
}

# -------------------------------------------------------------------------
#  Paths
# -------------------------------------------------------------------------

function Get-MSPPaths {
    <#
    .SYNOPSIS
        Resolve the toolkit's working directories, falling back to sane
        defaults under %ProgramData% so non-admins can still write logs.
    #>
    [CmdletBinding()]
    param()

    $cfg = $null
    try { $cfg = Get-MSPConfig } catch { }

    $root = if ($cfg -and $cfg.paths -and $cfg.paths.logs) {
        Split-Path -Parent $cfg.paths.logs
    } else {
        Join-Path $env:ProgramData 'MSPToolkit'
    }

    $paths = [pscustomobject]@{
        Root          = $root
        Logs          = Join-Path $root 'Logs'
        Reports       = Join-Path $root 'Reports'
        Cache         = Join-Path $root 'Cache'
        Templates     = Join-Path $root 'Templates'
        KnowledgeBase = Join-Path $root 'KnowledgeBase'
        Backups       = Join-Path $root 'Backups'
        Jobs          = Join-Path $root 'Jobs'
        Inventory     = Join-Path $root 'Inventory'
    }

    foreach ($p in $paths.PSObject.Properties.Value) {
        if (-not (Test-Path -LiteralPath $p)) {
            New-Item -ItemType Directory -Path $p -Force | Out-Null
        }
    }

    return $paths
}

# -------------------------------------------------------------------------
#  Retries
# -------------------------------------------------------------------------

function Invoke-MSPWithRetry {
    <#
    .SYNOPSIS
        Run a scriptblock with exponential backoff. Use for anything that
        touches the network, AD, Graph, or services that may take a beat
        to settle (Spooler, WinRM, BITS...).
    .EXAMPLE
        Invoke-MSPWithRetry -MaxAttempts 5 -ScriptBlock { Get-Service Spooler }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [scriptblock]$ScriptBlock,
        [int]$MaxAttempts = 3,
        [int]$InitialDelayMs = 500,
        [double]$BackoffFactor = 2.0,
        [type[]]$RetryOn = @()
    )

    $attempt = 0
    $delay = $InitialDelayMs
    while ($true) {
        $attempt++
        try {
            return & $ScriptBlock
        }
        catch {
            $shouldRetry = $attempt -lt $MaxAttempts
            if ($RetryOn.Count -gt 0) {
                $shouldRetry = $shouldRetry -and ($RetryOn | Where-Object { $_.IsInstanceOfType($_.Exception) })
            }
            if (-not $shouldRetry) { throw }
            Start-Sleep -Milliseconds $delay
            $delay = [int]($delay * $BackoffFactor)
        }
    }
}

# -------------------------------------------------------------------------
#  Standard result envelope
# -------------------------------------------------------------------------

function New-MSPResult {
    <#
    .SYNOPSIS
        Build the standard result object every script should emit so
        the REST API, fleet runner, and dashboard can render results
        consistently.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Tool,
        [ValidateSet('Success','Warning','Failure','Skipped')]
        [string]$Status = 'Success',
        [string]$Summary,
        [object]$Data,
        [string[]]$Errors = @(),
        [hashtable]$Metrics = @{}
    )

    [pscustomobject]@{
        schema       = 'msp-result/v1'
        tool         = $Tool
        computerName = $env:COMPUTERNAME
        userName     = $env:USERNAME
        status       = $Status
        summary      = $Summary
        data         = $Data
        errors       = $Errors
        metrics      = $Metrics
        timestamp    = (Get-Date).ToString('o')
        sessionId    = $Script:MSPSessionId
    }
}

function Save-MSPResult {
    <#
    .SYNOPSIS
        Persist a result object as JSON under the Reports directory and
        return the file path. Used by every diagnostic script that wants
        to leave a structured artifact behind.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [object]$Result,
        [string]$Subfolder
    )
    process {
        $paths = Get-MSPPaths
        $dest  = if ($Subfolder) { Join-Path $paths.Reports $Subfolder } else { $paths.Reports }
        if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }

        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $name  = ('{0}_{1}.json' -f $Result.tool, $stamp) -replace '[^\w\.-]','_'
        $file  = Join-Path $dest $name
        $Result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $file -Encoding UTF8
        return $file
    }
}

# -------------------------------------------------------------------------
#  OS fact gatherers (cached per-session so repeat calls are free)
# -------------------------------------------------------------------------

$Script:MSPOSCache = @{}

function Get-MSPOSFacts {
    <#
    .SYNOPSIS
        Cached OS / hardware / network facts. Mirrors the spirit of
        Get-MSPSystemInfo but returns deeper data and caches it.
    #>
    [CmdletBinding()]
    param([switch]$Refresh)

    if (-not $Refresh -and $Script:MSPOSCache.Count -gt 0) {
        return [pscustomobject]$Script:MSPOSCache
    }

    $os   = Get-CimInstance Win32_OperatingSystem  -ErrorAction SilentlyContinue
    $cs   = Get-CimInstance Win32_ComputerSystem   -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS             -ErrorAction SilentlyContinue
    $cpu  = Get-CimInstance Win32_Processor        -ErrorAction SilentlyContinue | Select-Object -First 1
    $disk = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue
    $net  = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up' }

    $Script:MSPOSCache = @{
        ComputerName   = $env:COMPUTERNAME
        Domain         = $cs.Domain
        OSName         = $os.Caption
        OSVersion      = $os.Version
        OSBuild        = $os.BuildNumber
        OSArchitecture = $os.OSArchitecture
        Manufacturer   = $cs.Manufacturer
        Model          = $cs.Model
        Serial         = $bios.SerialNumber
        BIOSVersion    = $bios.SMBIOSBIOSVersion
        CPU            = $cpu.Name
        CPUCores       = $cpu.NumberOfCores
        CPULogical     = $cpu.NumberOfLogicalProcessors
        MemoryGB       = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 2) } else { 0 }
        LastBoot       = $os.LastBootUpTime
        Uptime         = if ($os) { (Get-Date) - $os.LastBootUpTime } else { $null }
        Disks          = @($disk | ForEach-Object {
            [pscustomobject]@{
                Drive    = $_.DeviceID
                SizeGB   = [math]::Round($_.Size / 1GB, 1)
                FreeGB   = [math]::Round($_.FreeSpace / 1GB, 1)
                PctFree  = if ($_.Size) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
            }
        })
        IPAddresses    = @($net | ForEach-Object { $_.IPv4Address.IPAddress })
        DNSServers     = @($net | ForEach-Object { $_.DNSServer.ServerAddresses } | Sort-Object -Unique)
    }

    return [pscustomobject]$Script:MSPOSCache
}

# -------------------------------------------------------------------------
#  Pending-reboot detection (used by many scripts, factored once here)
# -------------------------------------------------------------------------

function Test-MSPPendingReboot {
    <#
    .SYNOPSIS
        Multi-signal pending-reboot check: CBS, WindowsUpdate, PendingFileRename,
        SCCM client. Returns a structured object, not just a bool.
    #>
    [CmdletBinding()]
    param()

    $reasons = New-Object System.Collections.Generic.List[string]

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $reasons.Add('CBS:RebootPending')
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $reasons.Add('WindowsUpdate:RebootRequired')
    }
    $sm = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
    if ($sm -and $sm.PSObject.Properties.Name -contains 'PendingFileRenameOperations' -and $sm.PendingFileRenameOperations) {
        $reasons.Add('PendingFileRenameOperations')
    }
    try {
        $ccm = [wmiclass]'\\.\root\ccm\ClientSDK:CCM_ClientUtilities'
        $r = $ccm.DetermineIfRebootPending()
        if ($r.ReturnValue -eq 0 -and $r.RebootPending) { $reasons.Add('SCCM:RebootPending') }
    } catch { }

    [pscustomobject]@{
        PendingReboot = $reasons.Count -gt 0
        Reasons       = $reasons.ToArray()
    }
}

# -------------------------------------------------------------------------
#  Misc helpers
# -------------------------------------------------------------------------

function ConvertTo-MSPSize {
    <#
    .SYNOPSIS
        Human-friendly byte formatting: 1234567 -> "1.2 MB".
    #>
    param([Parameter(Mandatory)] [long]$Bytes)
    if ($Bytes -ge 1TB) { return '{0:N2} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-MSPSessionId {
    if (-not $Script:MSPSessionId) {
        $Script:MSPSessionId = ([guid]::NewGuid().ToString('N').Substring(0,12))
    }
    return $Script:MSPSessionId
}

Export-ModuleMember -Function @(
    'Test-MSPElevation',
    'Assert-MSPElevation',
    'Get-MSPPaths',
    'Invoke-MSPWithRetry',
    'New-MSPResult',
    'Save-MSPResult',
    'Get-MSPOSFacts',
    'Test-MSPPendingReboot',
    'ConvertTo-MSPSize',
    'Get-MSPSessionId'
)
