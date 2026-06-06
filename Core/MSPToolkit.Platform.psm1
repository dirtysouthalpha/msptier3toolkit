<#
.SYNOPSIS
    MSP Toolkit - Cross-Platform Abstraction Module.
.DESCRIPTION
    Provides OS detection, elevation checking, unified system facts gathering,
    and platform-appropriate command execution for Windows, macOS, and Linux.

    All functions return the same shapes regardless of OS so that every
    diagnostic, the REST API, and the fleet runner can consume them uniformly.

    Exported functions:
      Get-MSPPlatform           -- 'Windows' | 'macOS' | 'Linux' + version
      Test-MSPElevation         -- admin/root check per platform
      Get-MSPPlatformFacts      -- unified CPU/RAM/disk/network/security per OS
      Get-MSPDiskInfo           -- cross-platform disk info
      Get-MSPNetworkInfo        -- cross-platform network adapters, IPs, DNS
      Get-MSPSecurityStatus     -- AV/Firewall/Encryption per platform
      Test-MSPPendingReboot     -- multi-signal pending-reboot (Win + Mac + Linux)
      Invoke-MSPNativeCommand   -- safe platform-native command wrapper
      ConvertTo-MSPPlatformPath -- path normalization per platform
      Get-MSPPlatformUsers      -- local user enumeration per platform
#>

Set-StrictMode -Version Latest

# -----------------------------------------------------------------------
#  OS Detection
# -----------------------------------------------------------------------

function Get-MSPPlatform {
    <#
    .SYNOPSIS
        Returns the current platform identifier and version.
    .EXAMPLE
        Get-MSPPlatform
        # { Platform: 'Windows', Version: '10.0.22621', IsWindows: $true, IsMacOS: $false, IsLinux: $false }
    #>
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $isWin = $IsWindows; $isMac = $IsMacOS; $isLin = $IsLinux
    } else {
        $isWin = $true; $isMac = $false; $isLin = $false
    }

    $version = ''
    $name = ''
    if ($isWin) {
        $name = 'Windows'
        try { $version = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Version } catch { $version = [Environment]::OSVersion.Version.ToString() }
    } elseif ($isMac) {
        $name = 'macOS'
        try { $version = (sw_vers -productVersion 2>$null) } catch { $version = '' }
    } elseif ($isLin) {
        $name = 'Linux'
        try { $version = (lsb_release -ds 2>$null) -replace '"','' } catch { try { $version = (cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 -s | tr -d '"') } catch { $version = '' } }
    }

    [pscustomobject]@{
        Platform  = $name
        Version   = $version
        IsWindows = $isWin
        IsMacOS   = $isMac
        IsLinux   = $isLin
    }
}

# -----------------------------------------------------------------------
#  Elevation Detection (cross-platform)
# -----------------------------------------------------------------------

function Test-MSPElevation {
    <#
    .SYNOPSIS
        Returns $true when running as Administrator (Windows), root (macOS/Linux),
        or when running with elevated privileges.
    #>
    [CmdletBinding()]
    param()

    $plat = Get-MSPPlatform

    if ($plat.IsWindows) {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = [Security.Principal.WindowsPrincipal]::new($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    if ($plat.IsMacOS -or $plat.IsLinux) {
        try {
            $uid = (id -u 2>$null)
            return [int]$uid -eq 0
        } catch {
            # Fallback: try to write to a root-only path
            try {
                [System.IO.File]::WriteAllText('/tmp/.mspelevationtest', 'test')
                Remove-Item '/tmp/.mspelevationtest' -Force -ErrorAction SilentlyContinue
                return $false
            } catch {
                return $false
            }
        }
    }

    return $false
}

# -----------------------------------------------------------------------
#  Unified Platform Facts
# -----------------------------------------------------------------------

$Script:PlatformFactsCache = $null

function Get-MSPPlatformFacts {
    <#
    .SYNOPSIS
        Cached unified OS/hardware/network facts across all platforms.
    #>
    [CmdletBinding()]
    param([switch]$Refresh)

    if (-not $Refresh -and $Script:PlatformFactsCache) {
        return [pscustomobject]$Script:PlatformFactsCache
    }

    $plat = Get-MSPPlatform
    $facts = @{}

    # --- Common ---
    $facts.ComputerName = if ($plat.IsWindows) { $env:COMPUTERNAME } else { (hostname 2>$null).Trim() }
    $facts.UserName     = if ($plat.IsWindows) { $env:USERNAME } else { (whoami 2>$null).Trim() }
    $facts.Platform     = $plat.Platform
    $facts.PlatformVersion = $plat.Version
    $facts.IsElevated   = Test-MSPElevation

    # --- Windows ---
    if ($plat.IsWindows) {
        try {
            $os   = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
            $cs   = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
            $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
            $cpu  = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1

            $facts.OSName         = $os.Caption
            $facts.OSBuild        = $os.BuildNumber
            $facts.OSArchitecture = $os.OSArchitecture
            $facts.Manufacturer   = $cs.Manufacturer
            $facts.Model          = $cs.Model
            $facts.SerialNumber   = $bios.SerialNumber
            $facts.CPU            = $cpu.Name
            $facts.CPUCores       = $cpu.NumberOfCores
            $facts.CPULogical     = $cpu.NumberOfLogicalProcessors
            $facts.MemoryGB       = if ($cs.TotalPhysicalMemory) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { 0 }
            $facts.LastBoot       = $os.LastBootUpTime.ToString('o')
            $facts.Uptime         = ((Get-Date) - $os.LastBootUpTime).ToString()
            $facts.Domain         = $cs.Domain
        } catch { }
    }

    # --- macOS ---
    if ($plat.IsMacOS) {
        try {
            $facts.OSName         = 'macOS'
            $facts.OSBuild        = try { (sw_vers -buildVersion 2>$null).Trim() } catch { '' }
            $facts.OSArchitecture = (uname -m 2>$null).Trim()
            $facts.Manufacturer   = 'Apple'
            $facts.Model          = try { (sysctl -n hw.model 2>$null).Trim() } catch { '' }
            $facts.SerialNumber   = try { (ioreg -c IOPlatformExpertDevice -d 2 | grep IOPlatformSerialNumber | awk -F'"' '{print $4}') } catch { '' }
            $facts.CPU            = try { (sysctl -n machdep.cpu.brand_string 2>$null).Trim() } catch { '' }
            $facts.CPUCores       = try { [int](sysctl -n hw.physicalcpu 2>$null).Trim() } catch { 0 }
            $facts.CPULogical     = try { [int](sysctl -n hw.logicalcpu 2>$null).Trim() } catch { 0 }
            $memBytes             = try { [long](sysctl -n hw.memsize 2>$null).Trim() } catch { 0 }
            $facts.MemoryGB       = [math]::Round($memBytes / 1GB, 1)
            $facts.LastBoot       = try {
                $bootEpoch = [long](sysctl -n kern.boottime 2>$null | grep -oE 'sec = [0-9]+' | awk '{print $3}')
                ([DateTimeOffset]::FromUnixTimeSeconds($bootEpoch)).DateTime.ToString('o')
            } catch { '' }
            $facts.Uptime         = try { (uptime 2>$null | sed 's/.*up //' | sed 's/,.*//').Trim() } catch { '' }
            $facts.Domain         = try { (dsconfigad -show 2>$null | grep 'Active Directory Domain' | awk -F'= ' '{print $2}').Trim() } catch { '' }
        } catch { }
    }

    # --- Linux ---
    if ($plat.IsLinux) {
        try {
            $facts.OSName         = try { (lsb_release -ds 2>$null -replace '"','').Trim() } catch { try { (cat /etc/os-release 2>$null | grep '^PRETTY_NAME=' | cut -d= -f2- | tr -d '"').Trim() } catch { '' } }
            $facts.OSArchitecture = (uname -m 2>$null).Trim()
            $facts.Manufacturer   = try { (cat /sys/devices/virtual/dmi/id/sys_vendor 2>$null).Trim() } catch { '' }
            $facts.Model          = try { (cat /sys/devices/virtual/dmi/id/product_name 2>$null).Trim() } catch { '' }
            $facts.SerialNumber   = try { (cat /sys/devices/virtual/dmi/id/product_serial 2>$null).Trim() } catch { '' }
            $facts.CPU            = try { (cat /proc/cpuinfo 2>$null | grep 'model name' | head -1 | cut -d: -f2-).Trim() } catch { '' }
            $facts.CPUCores       = try { [int](nproc --all 2>$null) } catch { try { [int](cat /proc/cpuinfo 2>$null | grep -c processor) } catch { 0 } }
            $facts.CPULogical     = $facts.CPUCores
            $memKB                = try { [long](cat /proc/meminfo 2>$null | grep MemTotal | awk '{print $2}') } catch { 0 }
            $facts.MemoryGB       = [math]::Round($memKB / (1024*1024), 1)
            $facts.LastBoot       = try {
                $uptimeSec = [double](cat /proc/uptime 2>$null | awk '{print $1}')
                ([DateTime]::Now.AddSeconds(-$uptimeSec)).ToString('o')
            } catch { '' }
            $facts.Uptime         = try { (uptime -p 2>$null).Replace('up ','').Trim() } catch { '' }
            $facts.Domain         = try { (realm list 2>$null | head -1).Trim() } catch { '' }
        } catch { }
    }

    $Script:PlatformFactsCache = $facts
    return [pscustomobject]$facts
}

# -----------------------------------------------------------------------
#  Disk Info
# -----------------------------------------------------------------------

function Get-MSPDiskInfo {
    <#
    .SYNOPSIS
        Cross-platform disk/volume information.
    #>
    [CmdletBinding()]
    param()

    $plat = Get-MSPPlatform
    $disks = @()

    if ($plat.IsWindows) {
        Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | ForEach-Object {
            $disks += [pscustomobject]@{
                Drive      = $_.DeviceID
                SizeGB     = [math]::Round($_.Size / 1GB, 1)
                FreeGB     = [math]::Round($_.FreeSpace / 1GB, 1)
                UsedPct    = if ($_.Size -gt 0) { [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1) } else { 0 }
                FileSystem = $_.FileSystem
                VolumeName = $_.VolumeName
            }
        }
    } elseif ($plat.IsMacOS) {
        $output = Invoke-MSPNativeCommand -Command 'diskutil' -Arguments @('list') -TimeoutSec 10
        # Parse diskutil output for mounted volumes
        $info = Invoke-MSPNativeCommand -Command 'df' -Arguments @('-h','-l') -TimeoutSec 10
        $lines = $info -split "`n" | Select-Object -Skip 1
        foreach ($line in $lines) {
            if ($line -match '^/dev/') {
                $parts = $line -split '\s+'
                if ($parts.Count -ge 6) {
                    $sizeStr = $parts[1]
                    $usedStr = $parts[2]
                    $freeStr = $parts[3]
                    $mountPoint = $parts[5]
                    $disks += [pscustomobject]@{
                        Drive      = $mountPoint
                        SizeHuman  = $sizeStr
                        UsedHuman  = $usedStr
                        FreeHuman  = $freeStr
                        MountPoint = $mountPoint
                    }
                }
            }
        }
    } elseif ($plat.IsLinux) {
        $lines = (Invoke-MSPNativeCommand -Command 'df' -Arguments @('-h','-x','tmpfs','-x','devtmpfs','-x','squashfs') -TimeoutSec 10) -split "`n" | Select-Object -Skip 1
        foreach ($line in $lines) {
            if ($line -match '^/dev/') {
                $parts = $line -split '\s+'
                if ($parts.Count -ge 6) {
                    $disks += [pscustomobject]@{
                        Drive      = $parts[0]
                        SizeHuman  = $parts[1]
                        UsedHuman  = $parts[2]
                        FreeHuman  = $parts[3]
                        MountPoint = $parts[5]
                    }
                }
            }
        }
    }

    return $disks
}

# -----------------------------------------------------------------------
#  Network Info
# -----------------------------------------------------------------------

function Get-MSPNetworkInfo {
    <#
    .SYNOPSIS
        Cross-platform network adapter, IP, and DNS configuration.
    #>
    [CmdletBinding()]
    param()

    $plat = Get-MSPPlatform
    $adapters = @()

    if ($plat.IsWindows) {
        $nics = Get-NetIPConfiguration -Detailed -ErrorAction SilentlyContinue
        foreach ($nic in $nics) {
            if ($nic.IPv4Address -or $nic.IPv6Address) {
                $adapters += [pscustomobject]@{
                    Name         = $nic.InterfaceAlias
                    Description  = $nic.InterfaceDescription
                    Status       = $nic.NetAdapter.Status
                    IPv4         = @($nic.IPv4Address | ForEach-Object { $_.IPAddress })
                    IPv6         = @($nic.IPv6Address | ForEach-Object { $_.IPAddress })
                    Gateway      = if ($nic.IPv4DefaultGateway) { $nic.IPv4DefaultGateway.NextHop } else { '' }
                    DNSServers   = if ($nic.DNSServer) { @($nic.DNSServer.ServerAddresses) } else { @() }
                    MacAddress   = $nic.NetAdapter.LinkLayerAddress
                    LinkSpeed    = $nic.NetAdapter.LinkSpeed
                }
            }
        }
    } elseif ($plat.IsMacOS) {
        $ifaces = Invoke-MSPNativeCommand -Command 'ifconfig' -Arguments @('-l') -TimeoutSec 5
        $ifaceList = $ifaces -split '\s+'
        foreach ($iface in $ifaceList) {
            if ($iface -and $iface -ne 'lo0') {
                $cfg = Invoke-MSPNativeCommand -Command 'ifconfig' -Arguments @($iface) -TimeoutSec 5
                $ipv4 = ''
                $ipv6 = ''
                $mac = ''
                if ($cfg -match 'inet (\d+\.\d+\.\d+\.\d+)') { $ipv4 = $Matches[1] }
                if ($cfg -match 'inet6 ([a-f0-9:]+)') { $ipv6 = $Matches[1] }
                if ($cfg -match 'ether ([a-f0-9:]+)') { $mac = $Matches[1] }
                if ($ipv4 -or $mac) {
                    $adapters += [pscustomobject]@{
                        Name        = $iface
                        Description = ''
                        Status      = if ($cfg -match 'status: (active|inactive)') { $Matches[1] } else { 'unknown' }
                        IPv4        = @(if ($ipv4) { $ipv4 } else { @() })
                        IPv6        = @(if ($ipv6) { $ipv6 } else { @() })
                        Gateway     = ''
                        DNSServers  = @()
                        MacAddress  = $mac
                        LinkSpeed   = ''
                    }
                }
            }
        }
    } elseif ($plat.IsLinux) {
        $ipLines = Invoke-MSPNativeCommand -Command 'ip' -Arguments @('addr','show') -TimeoutSec 5
        $currentName = ''
        $currentMac = ''
        $currentIPs = @()
        foreach ($line in ($ipLines -split "`n")) {
            if ($line -match '^\d+:\s+(\S+):') {
                if ($currentName) {
                    $adapters += [pscustomobject]@{
                        Name        = $currentName
                        IPv4        = @($currentIPs | Where-Object { $_ -match '^\d+\.' })
                        IPv6        = @($currentIPs | Where-Object { $_ -match ':' })
                        MacAddress  = $currentMac
                        Status      = if ($line -match 'UP') { 'Up' } else { 'Down' }
                    }
                }
                $currentName = $Matches[1]
                $currentMac = ''
                $currentIPs = @()
            }
            if ($line -match 'link/ether ([a-f0-9:]+)') { $currentMac = $Matches[1] }
            if ($line -match 'inet6?\s+([a-f0-9\.:]+)') { $currentIPs += $Matches[1] }
        }
        # Last one
        if ($currentName) {
            $adapters += [pscustomobject]@{
                Name        = $currentName
                IPv4        = @($currentIPs | Where-Object { $_ -match '^\d+\.' })
                IPv6        = @($currentIPs | Where-Object { $_ -match ':' })
                MacAddress  = $currentMac
                Status      = 'unknown'
            }
        }
    }

    return $adapters
}

# -----------------------------------------------------------------------
#  Security Status
# -----------------------------------------------------------------------

function Get-MSPSecurityStatus {
    <#
    .SYNOPSIS
        Cross-platform security posture: AV, firewall, encryption.
    #>
    [CmdletBinding()]
    param()

    $plat = Get-MSPPlatform
    $result = @{
        FirewallEnabled   = $false
        EncryptionEnabled = $false
        AVStatus          = 'Unknown'
        AVProduct         = ''
        AVUpdated          = $false
    }

    if ($plat.IsWindows) {
        # Firewall
        try {
            $fw = Get-NetFirewallProfile -Profile Domain,Public,Private -ErrorAction SilentlyContinue
            $result.FirewallEnabled = ($fw | Where-Object Enabled -eq $true).Count -gt 0
        } catch { }

        # Encryption (BitLocker)
        try {
            $blv = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
            $result.EncryptionEnabled = ($blv.ProtectionStatus -eq 'On')
        } catch { }

        # AV
        try {
            $av = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntivirusProduct -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($av) {
                $result.AVProduct = $av.displayName
                $result.AVStatus = 'Enabled'
            }
        } catch { }
        # Defender fallback
        if (-not $result.AVProduct) {
            try {
                $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
                if ($mp) {
                    $result.AVProduct = 'Microsoft Defender'
                    $result.AVStatus = if ($mp.AntivirusEnabled) { 'Enabled' } else { 'Disabled' }
                    $result.AVUpdated = $mp.AntivirusSignatureAge -lt 7
                }
            } catch { }
        }
    }

    if ($plat.IsMacOS) {
        # Firewall (pfctl / application firewall)
        try {
            $fwState = Invoke-MSPNativeCommand -Command 'defaults' -Arguments @('read','/Library/Preferences/com.apple.alf','globalstate') -TimeoutSec 5
            $result.FirewallEnabled = ([int]($fwState.Trim()) -ge 1)
        } catch { }

        # FileVault
        try {
            $fv = Invoke-MSPNativeCommand -Command 'fdesetup' -Arguments @('status') -TimeoutSec 10 2>&1
            $result.EncryptionEnabled = $fv -match 'FileVault is On'
        } catch { }

        # XProtect / Gatekeeper
        try {
            $gk = Invoke-MSPNativeCommand -Command 'spctl' -Arguments @('--status') -TimeoutSec 5 2>&1
            if ($gk -match 'assessments enabled') {
                $result.AVProduct = 'Gatekeeper + XProtect'
                $result.AVStatus = 'Enabled'
            }
        } catch { }
    }

    if ($plat.IsLinux) {
        # Firewall (iptables/ufw)
        try {
            $ufw = Invoke-MSPNativeCommand -Command 'ufw' -Arguments @('status') -TimeoutSec 5 2>&1
            $result.FirewallEnabled = $ufw -match 'Status: active'
        } catch {
            try {
                $ipt = Invoke-MSPNativeCommand -Command 'iptables' -Arguments @('-L','-n') -TimeoutSec 5 2>&1
                $result.FirewallEnabled = ($ipt -match 'DROP|REJECT')
            } catch { }
        }

        # Encryption (LUKS)
        try {
            $luks = Invoke-MSPNativeCommand -Command 'dmsetup' -Arguments @('ls','--target','crypt') -TimeoutSec 5
            $result.EncryptionEnabled = -not [string]::IsNullOrWhiteSpace($luks)
        } catch { }

        # SELinux / AppArmor
        try {
            $selinux = Invoke-MSPNativeCommand -Command 'getenforce' -Arguments @() -TimeoutSec 5 2>&1
            if ($selinux -match 'Enforcing') {
                $result.AVProduct = 'SELinux'
                $result.AVStatus = 'Enabled'
            }
        } catch {
            try {
                $aa = Invoke-MSPNativeCommand -Command 'aa-status' -Arguments @() -TimeoutSec 5 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $result.AVProduct = 'AppArmor'
                    $result.AVStatus = 'Enabled'
                }
            } catch { }
        }
    }

    return [pscustomobject]$result
}

# -----------------------------------------------------------------------
#  Pending Reboot (cross-platform)
# -----------------------------------------------------------------------

function Test-MSPPendingReboot {
    <#
    .SYNOPSIS
        Multi-signal pending-reboot detection for Windows, macOS, and Linux.
    #>
    [CmdletBinding()]
    param()

    $plat = Get-MSPPlatform
    $reasons = New-Object System.Collections.Generic.List[string]

    if ($plat.IsWindows) {
        # CBS
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
            $reasons.Add('CBS:RebootPending')
        }
        # Windows Update
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
            $reasons.Add('WindowsUpdate:RebootRequired')
        }
        # PendingFileRenameOperations
        try {
            $sm = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
            if ($sm -and $sm.PendingFileRenameOperations) {
                $reasons.Add('PendingFileRenameOperations')
            }
        } catch { }
        # SCCM
        try {
            $ccm = [wmiclass]'\\.\root\ccm\ClientSDK:CCM_ClientUtilities'
            $r = $ccm.DetermineIfRebootPending()
            if ($r.ReturnValue -eq 0 -and $r.RebootPending) {
                $reasons.Add('SCCM:RebootPending')
            }
        } catch { }
    }

    if ($plat.IsMacOS) {
        # Check for softwareupdate restart needed
        try {
            $su = Invoke-MSPNativeCommand -Command 'softwareupdate' -Arguments @('--list') -TimeoutSec 15 2>&1
            if ($su -match 'restart') {
                $reasons.Add('macOS:SoftwareUpdateRestartRequired')
            }
        } catch { }
        # Check for kernel extension cache rebuild needed
        try {
            $kext = Invoke-MSPNativeCommand -Command 'kextstat' -Arguments @() -TimeoutSec 5 2>$null
            if ($LASTEXITCODE -ne 0) {
                $reasons.Add('macOS:KextStagingNeedsReboot')
            }
        } catch { }
    }

    if ($plat.IsLinux) {
        # Check for /var/run/reboot-required (Debian/Ubuntu)
        if (Test-Path '/var/run/reboot-required') {
            $reasons.Add('Linux:RebootRequired')
            try {
                $pkgs = Get-Content '/var/run/reboot-required.pkgs' -ErrorAction SilentlyContinue
                if ($pkgs) { $reasons.Add("Linux:Packages=$($pkgs -join ',')") }
            } catch { }
        }
        # Check for kernel version mismatch
        try {
            $runningKernel = Invoke-MSPNativeCommand -Command 'uname' -Arguments @('-r') -TimeoutSec 5
            $runningKernel = $runningKernel.Trim()
            $installedKernels = Invoke-MSPNativeCommand -Command 'ls' -Arguments @('/boot/vmlinuz-*') -TimeoutSec 5
            if ($installedKernels -and $installedKernels -notmatch [regex]::Escape($runningKernel)) {
                $reasons.Add('Linux:KernelUpdatePending')
            }
        } catch { }
    }

    [pscustomobject]@{
        PendingReboot = $reasons.Count -gt 0
        Reasons       = $reasons.ToArray()
    }
}

# -----------------------------------------------------------------------
#  Native Command Wrapper
# -----------------------------------------------------------------------

function Invoke-MSPNativeCommand {
    <#
    .SYNOPSIS
        Safe wrapper for platform-native commands with timeout and error handling.
    .EXAMPLE
        Invoke-MSPNativeCommand -Command 'diskutil' -Arguments @('list') -TimeoutSec 10
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [string[]]$Arguments = @(),

        [int]$TimeoutSec = 30
    )

    $stdout = New-Object System.Text.StringBuilder
    $stderr = New-Object System.Text.StringBuilder

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Command
        $psi.Arguments = $Arguments -join ' '
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()

        $proc.WaitForExit($TimeoutSec * 1000) | Out-Null
        if (-not $proc.HasExited) {
            $proc.Kill()
            throw "Command '$Command' timed out after ${TimeoutSec}s"
        }

        $stdout.Append($proc.StandardOutput.ReadToEnd()) | Out-Null
        $stderr.Append($proc.StandardError.ReadToEnd()) | Out-Null
    } catch {
        throw "Failed to run '$Command': $($_.Exception.Message)"
    }

    $LASTEXITCODE = $proc.ExitCode
    return $stdout.ToString()
}

# -----------------------------------------------------------------------
#  Platform Path Normalization
# -----------------------------------------------------------------------

function ConvertTo-MSPPlatformPath {
    <#
    .SYNOPSIS
        Normalizes a path for the current platform, converting slashes
        and expanding environment variables.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path
    )
    $plat = Get-MSPPlatform
    if ($plat.IsWindows) {
        return $Path.Replace('/', '\')
    } else {
        return $Path.Replace('\', '/')
    }
}

# -----------------------------------------------------------------------
#  Local Users
# -----------------------------------------------------------------------

function Get-MSPPlatformUsers {
    <#
    .SYNOPSIS
        Cross-platform local user enumeration.
    #>
    [CmdletBinding()]
    param()

    $plat = Get-MSPPlatform
    $users = @()

    if ($plat.IsWindows) {
        try {
            Get-LocalUser -ErrorAction Stop | ForEach-Object {
                $users += [pscustomobject]@{
                    Name        = $_.Name
                    FullName    = $_.FullName
                    Enabled     = $_.Enabled
                    LastLogon   = if ($_.LastLogon) { $_.LastLogon.ToString('o') } else { $null }
                    Description = $_.Description
                    SID         = if ($_.SID) { $_.SID.Value } else { '' }
                }
            }
        } catch { }
    } elseif ($plat.IsMacOS) {
        $output = Invoke-MSPNativeCommand -Command 'dscl' -Arguments @('.','-list','/Users') -TimeoutSec 10
        $allUsers = ($output -split '\s+') | Where-Object { $_ -and $_ -notmatch '^_' }
        foreach ($u in $allUsers) {
            $uid = try { (Invoke-MSPNativeCommand -Command 'dscl' -Arguments @('.','-read',"/Users/$u",'UniqueID') -TimeoutSec 5).Split(':')[1].Trim() } catch { '' }
            $users += [pscustomobject]@{ Name = $u; FullName = ''; Enabled = ($uid -and [int]$uid -ge 500); UID = $uid }
        }
    } elseif ($plat.IsLinux) {
        $passwd = Invoke-MSPNativeCommand -Command 'cat' -Arguments @('/etc/passwd') -TimeoutSec 5
        foreach ($line in ($passwd -split "`n")) {
            $parts = $line -split ':'
            if ($parts.Count -ge 7) {
                $uid = [int]$parts[2]
                $hasShell = $parts[6] -notmatch '/(false|nologin)$'
                if ($uid -ge 1000 -and $hasShell) {
                    $users += [pscustomobject]@{
                        Name     = $parts[0]
                        FullName = $parts[4] -replace ',.*',''
                        Enabled  = $hasShell
                        UID      = $uid
                        HomeDir  = $parts[5]
                        Shell    = $parts[6]
                    }
                }
            }
        }
    }

    return $users
}

# -----------------------------------------------------------------------
#  Export
# -----------------------------------------------------------------------

Export-ModuleMember -Function @(
    'Get-MSPPlatform',
    'Test-MSPElevation',
    'Get-MSPPlatformFacts',
    'Get-MSPDiskInfo',
    'Get-MSPNetworkInfo',
    'Get-MSPSecurityStatus',
    'Test-MSPPendingReboot',
    'Invoke-MSPNativeCommand',
    'ConvertTo-MSPPlatformPath',
    'Get-MSPPlatformUsers'
)
