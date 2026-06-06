<#
.SYNOPSIS Linux package audit -- installed packages, updates pending, held packages, and security patches.
.NOTES v22.0 -- Linux Support
#>
[CmdletBinding()] param()

$data = [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o'); TotalPackages=0; UpdatesPending=0; SecurityUpdates=0; HeldPackages=0; LastUpdate=''; Checks=@(); Score=0; MaxScore=0; Summary='' }

if (-not $IsLinux) { $data.Summary='Linux required'; $data.MaxScore=20; return $data }

# Check package manager
$pm = $null
if (Get-Command dpkg -ErrorAction SilentlyContinue) {
    $pm = 'apt'
    $data.TotalPackages = (dpkg -l 2>$null | Where-Object { $_ -match '^ii' }).Count
    $data.UpdatesPending = (apt list --upgradable 2>$null | Where-Object { $_ -match '/' }).Count
    $data.HeldPackages = (apt-mark showhold 2>$null | Measure-Object).Count
    $data.SecurityUpdates = (apt list --upgradable 2>$null | Select-String 'security' | Measure-Object).Count
} elseif (Get-Command rpm -ErrorAction SilentlyContinue) {
    $pm = 'rpm'
    $data.TotalPackages = (rpm -qa 2>$null | Measure-Object).Count
    $data.UpdatesPending = (yum check-update 2>$null | Where-Object { $_ -match '\.' }).Count
}
# Last update
$data.LastUpdate = (stat -c %y /var/lib/apt/periodic/update-success-stamp 2>$null).Substring(0,19)  -replace 'T', ' '
if (-not $data.LastUpdate) { $data.LastUpdate = (stat -c %y /var/cache/yum 2>$null).Substring(0,19) }

$data.Checks += [PSCustomObject]@{ Name='Packages Current'; Pass=($data.UpdatesPending -lt 20); Detail="$($data.UpdatesPending) pending ($pm)" }
$data.Checks += [PSCustomObject]@{ Name='No Held Packages'; Pass=($data.HeldPackages -lt 5); Detail="$($data.HeldPackages) held" }
$data.Checks += [PSCustomObject]@{ Name='Security Patches'; Pass=($data.SecurityUpdates -lt 10); Detail="$($data.SecurityUpdates) security updates" }

$data.MaxScore=$data.Checks.Count*20; $data.Score=($data.Checks|Where-Object{$_.Pass}).Count*20
$data.Summary="Linux Pkgs: $($data.TotalPackages) installed | $($data.UpdatesPending) pending ($pm)"
return $data
