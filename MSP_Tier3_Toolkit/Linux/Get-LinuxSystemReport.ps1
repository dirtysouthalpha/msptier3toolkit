<#
.SYNOPSIS
    Full Linux system report -- hardware, OS, kernel, and resource overview.
.DESCRIPTION
    Gathers comprehensive system information from /proc, /sys, dmidecode,
    lsb_release, and systemd for a complete Linux health snapshot.
    Produces the standard MSP result envelope with scored checks.
.NOTES
    v22.0 -- Linux Support
    Requires: PowerShell 7+ on Linux, or PowerShell 5.1 with SSH remoting
#>
[CmdletBinding()]
param()

$data = [PSCustomObject]@{
    Timestamp      = (Get-Date).ToString('o')
    Hostname       = hostname 2>$null
    Distro         = ''
    KernelVersion  = ''
    Uptime         = ''
    CPUModel       = ''
    CPUCores       = 0
    TotalMemoryGB  = 0
    FreeMemoryGB   = 0
    LoadAverage    = ''
    DiskLayout     = @()
    RunningServices = 0
    FailedServices  = 0
    Checks         = @()
    Score          = 0
    MaxScore       = 0
    Summary        = ''
}

# OS detection
if ($IsLinux) {
    $data.Distro = (Get-Content /etc/os-release -ErrorAction SilentlyContinue | Select-String 'PRETTY_NAME' | ForEach-Object { $_ -replace 'PRETTY_NAME=','' -replace '"','' })
    $data.KernelVersion = uname -r 2>$null
    $data.Uptime = uptime -p 2>$null
    
    # CPU
    $cpuInfo = Get-Content /proc/cpuinfo -ErrorAction SilentlyContinue
    $data.CPUModel = ($cpuInfo | Select-String 'model name' | Select-Object -First 1) -replace '.*:\s+',''
    $data.CPUCores = ($cpuInfo | Select-String 'processor' | Measure-Object).Count
    
    # Memory
    $memInfo = Get-Content /proc/meminfo -ErrorAction SilentlyContinue
    $totalMem = [int64]($memInfo | Select-String 'MemTotal' | ForEach-Object { ($_ -replace '\D','') })
    $freeMem = [int64]($memInfo | Select-String 'MemAvailable' | ForEach-Object { ($_ -replace '\D','') })
    $data.TotalMemoryGB = [math]::Round($totalMem / 1024 / 1024, 1)
    $data.FreeMemoryGB = [math]::Round($freeMem / 1024 / 1024, 1)
    
    # Load
    $data.LoadAverage = (Get-Content /proc/loadavg) -replace '\s+',' '
    
    # Disks
    $disks = lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE -J 2>$null | ConvertFrom-Json
    if ($disks.blockdevices) {
        foreach ($d in $disks.blockdevices) {
            $data.DiskLayout += [PSCustomObject]@{ Name=$d.name; Size=$d.size; Type=$d.type; MountPoint=$d.mountpoint; FSType=$d.fstype }
        }
    }
    
    # Services
    $data.RunningServices = (systemctl list-units --type=service --state=running 2>$null | Measure-Object).Count
    $data.FailedServices = (systemctl list-units --type=service --state=failed 2>$null | Measure-Object).Count

    $data.Checks += [PSCustomObject]@{ Name='OS Detected'; Pass=$true; Detail=$data.Distro }
    $data.Checks += [PSCustomObject]@{ Name='Memory Available'; Pass=($data.FreeMemoryGB -gt 0.5); Detail="$($data.FreeMemoryGB) GB free" }
    $data.Checks += [PSCustomObject]@{ Name='No Failed Services'; Pass=($data.FailedServices -eq 0); Detail="$($data.FailedServices) failed" }
} else {
    $data.Checks += [PSCustomObject]@{ Name='OS Detected'; Pass=$false; Detail='Not running on Linux' }
    $data.Summary = 'This script requires Linux (PowerShell 7+)'
}

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Linux: $($data.Distro) | Kernel: $($data.KernelVersion) | Load: $($data.LoadAverage)"
return $data
