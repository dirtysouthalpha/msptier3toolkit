<#
.SYNOPSIS Linux service audit -- systemd unit states, failed services, masked units, and resource hogs.
.NOTES v22.0 -- Linux Support
#>
[CmdletBinding()] param()

$data = [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o'); TotalUnits=0; FailedUnits=0; MaskedUnits=0; DisabledUnits=0; TopResources=@(); Checks=@(); Score=0; MaxScore=0; Summary='' }

if (-not $IsLinux) { $data.Summary='Linux required'; $data.MaxScore=20; return $data }

# Failed services
$failed = systemctl list-units --type=service --state=failed --no-legend 2>$null
$data.FailedUnits = ($failed | Where-Object { $_ -match '\.service' } | Measure-Object).Count
$data.Checks += [PSCustomObject]@{ Name='No Failed Services'; Pass=($data.FailedUnits -eq 0); Detail="$($data.FailedUnits) failed" }

# Masked
$masked = systemctl list-unit-files --state=masked --no-legend 2>$null
$data.MaskedUnits = ($masked | Measure-Object).Count

# Top resource consumers
$topProcs = ps aux --sort=-%mem 2>$null | Select-Object -First 8 | ForEach-Object {
    $parts = $_ -split '\s+'
    [PSCustomObject]@{ User=$parts[0]; PID=$parts[1]; CPU=$parts[2]; MEM=$parts[3]; Command=($parts[10..99] -join ' ').Substring(0,[Math]::Min(40,($parts[10..99] -join ' ').Length)) }
}
$data.TopResources = @($topProcs | Select-Object -Skip 1)

# Disabled but installed
$data.DisabledUnits = (systemctl list-unit-files --state=disabled --type=service --no-legend 2>$null | Measure-Object).Count
$data.Checks += [PSCustomObject]@{ Name='Service Health'; Pass=($data.FailedUnits -eq 0); Detail="Failed:$($data.FailedUnits) Disabled:$($data.DisabledUnits)" }

$data.MaxScore=$data.Checks.Count*20; $data.Score=($data.Checks|Where-Object{$_.Pass}).Count*20
$data.Summary="Linux Services: $($data.FailedUnits) failed | $($data.DisabledUnits) disabled"
return $data
