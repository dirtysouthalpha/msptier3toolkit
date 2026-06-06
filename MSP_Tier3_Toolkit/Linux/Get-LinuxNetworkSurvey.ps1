<#
.SYNOPSIS Linux network survey -- interfaces, DNS, routing, connectivity tests.
.NOTES v22.0 -- Linux Support
#>
[CmdletBinding()] param()

$data = [PSCustomObject]@{ Timestamp=(Get-Date).ToString('o'); Interfaces=@(); DefaultGW=''; DNSServers=@(); ExternalIP=''; InternetReachable=$false; Checks=@(); Score=0; MaxScore=0; Summary='' }

if (-not $IsLinux) { $data.Summary='Linux required'; $data.MaxScore=20; return $data }

# Interfaces
$ips = ip -j addr 2>$null | ConvertFrom-Json
if ($ips) {
    foreach ($if in $ips) {
        if ($if.ifname -eq 'lo') { continue }
        $info = [PSCustomObject]@{ Name=$if.ifname; State=$if.operstate; MAC=$if.address; IPs=@() }
        foreach ($a in $if.addr_info) { if ($a.family -eq 'inet' -or $a.family -eq 'inet6') { $info.IPs += $a.local } }
        $data.Interfaces += $info
    }
}

# Gateway
$data.DefaultGW = (ip route show default 2>$null | Select-String 'via (\S+)' | ForEach-Object { $_.Matches.Groups[1].Value })
$data.DNSServers = @(grep 'nameserver' /etc/resolv.conf 2>$null | ForEach-Object { ($_ -split '\s+')[1] } | Where-Object { $_ })

# Connectivity
try { ping -c 1 -W 2 8.8.8.8 2>$null | Out-Null; $data.InternetReachable = ($LASTEXITCODE -eq 0) } catch { $data.InternetReachable = $false }
try { $data.ExternalIP = (curl -s ifconfig.me 2>$null).Trim() } catch {}

$data.Checks += [PSCustomObject]@{ Name='Interfaces Up'; Pass=($data.Interfaces.Count -gt 0); Detail="$($data.Interfaces.Count) active" }
$data.Checks += [PSCustomObject]@{ Name='Gateway Set'; Pass=($data.DefaultGW -ne ''); Detail=$data.DefaultGW }
$data.Checks += [PSCustomObject]@{ Name='Internet Reachable'; Pass=$data.InternetReachable; Detail=$(if($data.InternetReachable){'OK'}else{'FAIL'}) }

$data.MaxScore=$data.Checks.Count*20; $data.Score=($data.Checks|Where-Object{$_.Pass}).Count*20
$data.Summary="Linux Net: GW:$($data.DefaultGW) | DNS:$($data.DNSServers -join ',') | Net:$(if($data.InternetReachable){'OK'}else{'FAIL'})"
return $data
