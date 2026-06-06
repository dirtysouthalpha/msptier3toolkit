<#
.SYNOPSIS Linux security posture -- firewall, SELinux/AppArmor, SSH, kernel hardening, and package audit.
.NOTES v22.0 -- Linux Support
#>
[CmdletBinding()] param()

$data = [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o'); FirewallActive=$false; SELinux=$null; AppArmor=$null; SSHRootLogin=$false; PasswordAuth=$false; UpdatesPending=0; OpenPorts=@(); Checks=@(); Score=0; MaxScore=0; Summary='' }

if (-not $IsLinux) { $data.Summary='Linux required'; $data.MaxScore=20; return $data }

# Firewall
$ufw = ufw status 2>$null; $data.FirewallActive = ($ufw -match 'active' -or (firewall-cmd --state 2>$null) -match 'running')
$data.Checks += [PSCustomObject]@{ Name='Firewall Active'; Pass=$data.FirewallActive; Detail=$(if($data.FirewallActive){'Active'}else{'Inactive'}) }

# SELinux
$se = getenforce 2>$null; $data.SELinux = if($se){$se.Trim()}else{'Not installed'}
$data.Checks += [PSCustomObject]@{ Name='SELinux/AppArmor'; Pass=($data.SELinux -in @('Enforcing','enforcing') -or (aa-status 2>$null) -match 'apparmor'); Detail=$data.SELinux }

# SSH hardening
$data.SSHRootLogin = (grep '^PermitRootLogin\s+yes' /etc/ssh/sshd_config 2>$null).Count -gt 0
$data.PasswordAuth = (grep '^PasswordAuthentication\s+yes' /etc/ssh/sshd_config 2>$null).Count -gt 0
$data.Checks += [PSCustomObject]@{ Name='SSH Root Disabled'; Pass=(-not $data.SSHRootLogin); Detail=$(if($data.SSHRootLogin){'ROOT ENABLED'}else{'Disabled'}) }
$data.Checks += [PSCustomObject]@{ Name='SSH Key-Only'; Pass=(-not $data.PasswordAuth); Detail=$(if($data.PasswordAuth){'Password enabled'}else{'Key-only'}) }

# Updates pending
if (Get-Command apt-get -ErrorAction SilentlyContinue) { $data.UpdatesPending = (apt list --upgradable 2>$null | Where-Object { $_ -match '/' }).Count }
elseif (Get-Command yum -ErrorAction SilentlyContinue) { $data.UpdatesPending = (yum check-update 2>$null | Where-Object { $_ -match '\.' }).Count }
$data.Checks += [PSCustomObject]@{ Name='System Current'; Pass=($data.UpdatesPending -lt 20); Detail="$($data.UpdatesPending) pending" }

# Open ports
$data.OpenPorts = @(ss -tlnp 2>$null | Select-String 'LISTEN' | ForEach-Object { ($_ -split '\s+')[3] } | Where-Object { $_ })

$data.MaxScore=$data.Checks.Count*20; $data.Score=($data.Checks|Where-Object{$_.Pass}).Count*20
$data.Summary="Linux Security: $($data.Score)/$($data.MaxScore) | FW: $(if($data.FirewallActive){'ON'}else{'OFF'}) | SELinux: $($data.SELinux)"
return $data
