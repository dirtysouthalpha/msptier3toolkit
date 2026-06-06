<#
.SYNOPSIS Linux docker/container health -- container states, images, volumes, and resource usage.
.NOTES v22.0 -- Linux Support
#>
[CmdletBinding()] param()

$data = [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o'); DockerInstalled=$false; RunningContainers=0; StoppedContainers=0; TotalImages=0; DanglingImages=0; Volumes=0; Networks=0; Checks=@(); Score=0; MaxScore=0; Summary='' }

$data.DockerInstalled = (Get-Command docker -ErrorAction SilentlyContinue) -ne $null
if (-not $data.DockerInstalled) { $data.Summary='Docker not installed'; $data.MaxScore=20; return $data }

$data.Checks += [PSCustomObject]@{ Name='Docker Installed'; Pass=$true; Detail=(docker --version 2>$null).Trim() }

# Containers
$data.RunningContainers = (docker ps -q 2>$null | Measure-Object).Count
$data.StoppedContainers = (docker ps -aq 2>$null | Measure-Object).Count - $data.RunningContainers
$data.Checks += [PSCustomObject]@{ Name='Containers Running'; Pass=($data.RunningContainers -gt 0 -or $data.StoppedContainers -eq 0); Detail="$($data.RunningContainers) running / $($data.StoppedContainers) stopped" }

# Images
$data.TotalImages = (docker images -q 2>$null | Measure-Object).Count
$data.DanglingImages = (docker images -f 'dangling=true' -q 2>$null | Measure-Object).Count
$data.Checks += [PSCustomObject]@{ Name='No Dangling Images'; Pass=($data.DanglingImages -lt 10); Detail="$($data.DanglingImages) dangling" }

# Volumes
$data.Volumes = (docker volume ls -q 2>$null | Measure-Object).Count

# Networks
$data.Networks = (docker network ls -q 2>$null | Measure-Object).Count

# Docker disk usage
try { $dockerDisk = docker system df 2>$null; if ($dockerDisk -match 'Total.*?(\d+\.?\d*)(GB|MB)') { $data.Checks += [PSCustomObject]@{ Name='Disk Usage'; Pass=$true; Detail=$Matches[0] } } } catch {}

$data.MaxScore=$data.Checks.Count*20; $data.Score=($data.Checks|Where-Object{$_.Pass}).Count*20
$data.Summary="Docker: $($data.RunningContainers) running | $($data.TotalImages) images | $($data.Volumes) volumes"
return $data
