<#
.SYNOPSIS Linux user audit -- local users, sudo access, SSH keys, and last logins.
.NOTES v22.0 -- Linux Support
#>
[CmdletBinding()] param()

$data = [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o'); TotalUsers=0; UsersWithShell=0; SudoUsers=@(); SSHKeys=@(); RecentLogins=@(); Checks=@(); Score=0; MaxScore=0; Summary='' }

if (-not $IsLinux) { $data.Summary='Linux required'; $data.MaxScore=20; return $data }

# Local users
$passwd = Get-Content /etc/passwd
$data.TotalUsers = ($passwd | Measure-Object).Count
$data.UsersWithShell = ($passwd | Where-Object { $_ -match '(/bin/bash|/bin/sh|/bin/zsh)$' }).Count
$data.Checks += [PSCustomObject]@{ Name='User Count Normal'; Pass=($data.UsersWithShell -lt 50); Detail="$($data.UsersWithShell) shell users" }

# Sudo users
$sudoers = grep -v '^#' /etc/sudoers 2>$null; $sudoers += (grep -rh '' /etc/sudoers.d/ 2>$null)
$data.SudoUsers = @($sudoers | Select-String '\w+\s+ALL=' | ForEach-Object { ($_.Line -split '\s+')[0] } | Sort-Object -Unique)
$data.Checks += [PSCustomObject]@{ Name='Sudo Users'; Pass=($data.SudoUsers.Count -le 10); Detail="$($data.SudoUsers.Count) sudoers" }

# SSH authorized keys
$data.SSHKeys = @()
Get-ChildItem /home -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $akf = Join-Path $_.FullName '.ssh/authorized_keys'
    if (Test-Path $akf) {
        $keys = (Get-Content $akf | Where-Object { $_ -notmatch '^#' }).Count
        if ($keys -gt 0) { $data.SSHKeys += [PSCustomObject]@{ User=$_.Name; Keys=$keys } }
    }
}
$data.Checks += [PSCustomObject]@{ Name='SSH Key Access'; Pass=($data.SSHKeys.Count -lt 20); Detail="$($data.SSHKeys.Count) users with keys" }

# Recent logins
$data.RecentLogins = @((last -10 2>$null) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\s+' -and $_ -notmatch 'wtmp|reboot' })

$data.MaxScore=$data.Checks.Count*20; $data.Score=($data.Checks|Where-Object{$_.Pass}).Count*20
$data.Summary="Linux Users: $($data.UsersWithShell) shell users | $($data.SudoUsers.Count) sudo | $($data.SSHKeys.Count) SSH keys"
return $data
