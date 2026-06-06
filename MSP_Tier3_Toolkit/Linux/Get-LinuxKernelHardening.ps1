<#
.SYNOPSIS Linux kernel hardening audit -- kernel parameters, modules, ASLR, and sysctl checks.
.NOTES v22.0 -- Linux Support
#>
[CmdletBinding()] param()

$data = [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o'); ASLREnabled=$false; ExecShield=$false; IPv6Enabled=$false; CoreDumps=$false; SysRQ=$false; BootParams=@(); Checks=@(); Score=0; MaxScore=0; Summary='' }

if (-not $IsLinux) { $data.Summary='Linux required'; $data.MaxScore=20; return $data }

# ASLR
$data.ASLREnabled = ((Get-Content /proc/sys/kernel/randomize_va_space 2>$null).Trim() -eq '2')
$data.Checks += [PSCustomObject]@{ Name='ASLR Enabled'; Pass=$data.ASLREnabled; Detail=$(if($data.ASLREnabled){'Full (2)'}else{'Disabled/Partial'}) }

# Exec shield / NX
$data.ExecShield = (grep ' nx ' /proc/cpuinfo 2>$null).Count -gt 0
$data.Checks += [PSCustomObject]@{ Name='NX/XD Bit'; Pass=$data.ExecShield; Detail=$(if($data.ExecShield){'Present'}else{'Missing'}) }

# Core dumps
$data.CoreDumps = ((ulimit -c 2>$null) -ne '0')
$data.Checks += [PSCustomObject]@{ Name='Core Dumps Disabled'; Pass=(-not $data.CoreDumps); Detail=$(if($data.CoreDumps){'Enabled'}else{'Disabled'}) }

# Magic SysRQ
$data.SysRQ = ((Get-Content /proc/sys/kernel/sysrq 2>$null).Trim() -ne '0')
$data.Checks += [PSCustomObject]@{ Name='SysRQ Restricted'; Pass=(-not $data.SysRQ -or (Get-Content /proc/sys/kernel/sysrq).Trim() -lt 16); Detail="Value: $((Get-Content /proc/sys/kernel/sysrq).Trim())" }

# IPv6
$data.IPv6Enabled = ((Get-Content /proc/net/if_inet6 2>$null) -ne '' -and (Get-Content /proc/net/if_inet6 2>$null).Count -gt 0)
$data.Checks += [PSCustomObject]@{ Name='IPv6 Status'; Pass=$true; Detail=$(if($data.IPv6Enabled){'Enabled'}else{'Disabled'}) }

# Kernel boot parameters
$data.BootParams = @((Get-Content /proc/cmdline) -split '\s+' | ForEach-Object { 
    if ($_ -match '(quiet|splash|audit=|selinux=|apparmor=|mitigations=)') { $_ }
} | Where-Object { $_ })

# Kernel modules
$loadedMods = (lsmod 2>$null | Measure-Object).Count
$data.Checks += [PSCustomObject]@{ Name='Kernel Modules'; Pass=$true; Detail="$loadedMods loaded" }

$data.MaxScore=$data.Checks.Count*20; $data.Score=($data.Checks|Where-Object{$_.Pass}).Count*20
$data.Summary="Linux Kernel: ASLR:$(if($data.ASLREnabled){'OK'}else{'WARN'}) | NX:$(if($data.ExecShield){'OK'}else{'WARN'})"
return $data
