<#
.SYNOPSIS Linux disk health -- SMART, filesystem usage, inode utilization, and I/O stats.
.NOTES v22.0 -- Linux Support
#>
[CmdletBinding()] param()

$data = [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o'); Disks=@(); Partitions=@(); IOWait=0; Checks=@(); Score=0; MaxScore=0; Summary='' }

if (-not $IsLinux) { $data.Summary='Linux required'; $data.MaxScore=20; return $data }

# Disk devices
$diskDevs = lsblk -d -o NAME,SIZE,ROTA,TYPE -J 2>$null | ConvertFrom-Json
if ($diskDevs.blockdevices) {
    foreach ($d in $diskDevs.blockdevices | Where-Object { $_.type -eq 'disk' }) {
        $smartOk = $false
        try { $smartctl = smartctl -H /dev/$($d.name) 2>$null; $smartOk = ($LASTEXITCODE -eq 0 -and $smartctl -match 'PASSED|OK') } catch {}
        $data.Disks += [PSCustomObject]@{ Name=$d.name; Size=$d.size; Rotational=$d.rota; SMART=$smartOk }
    }
}

# Partition usage
$df = df -h --output=source,size,used,avail,pcent,target 2>$null
if ($df) {
    $lines = $df -split "`n" | Select-Object -Skip 1
    foreach ($line in $lines) {
        if ($line -match '(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)') {
            $data.Partitions += [PSCustomObject]@{ Source=$Matches[1]; Size=$Matches[2]; Used=$Matches[3]; Avail=$Matches[4]; UsePct=$Matches[5]; Target=$Matches[6] }
        }
    }
}

# Inode usage
$inodeIssues = (df -i 2>$null | Where-Object { $_ -match '(\d+)%' -and [int]$Matches[1] -gt 90 }).Count

# I/O wait
try {
    $ioLine = (iostat -c 1 2 2>$null | Select-String '%iowait' -Context 1)
    if ($ioLine) { $data.IOWait = [math]::Round([double]($ioLine.Context.PostContext[0] -replace '\s+','' -split '\s+' | Select-Object -Last 1)) }
} catch {}

$data.Checks += [PSCustomObject]@{ Name='Disks Detected'; Pass=($data.Disks.Count -gt 0); Detail="$($data.Disks.Count) disks" }
$data.Checks += [PSCustomObject]@{ Name='SMART Healthy'; Pass=(($data.Disks | Where-Object { $_.SMART }).Count -eq $data.Disks.Count); Detail="All SMART OK" }
$data.Checks += [PSCustomObject]@{ Name='No Critical Inodes'; Pass=($inodeIssues -eq 0); Detail="$inodeIssues volumes >90%" }

$data.MaxScore=$data.Checks.Count*20; $data.Score=($data.Checks|Where-Object{$_.Pass}).Count*20
$data.Summary="Linux Disks: $($data.Disks.Count) devices | I/O wait: $($data.IOWait)%"
return $data
