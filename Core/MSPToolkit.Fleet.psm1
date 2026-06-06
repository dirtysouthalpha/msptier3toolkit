<#
.SYNOPSIS
    MSP Toolkit - Parallel fleet executor over WinRM.
.DESCRIPTION
    Invoke-MSPFleet runs a script or scriptblock against many hosts in
    parallel using a runspace pool. Output is normalised:

        ComputerName  Status  DurationMs  Result  Error

    Each row's `Result` is the deserialized PSObject the remote script
    returned (almost always a New-MSPResult). The fleet runner itself
    knows nothing about MSP results -- it just ferries objects.

    Why runspaces and not Start-Job? Start-Job spawns a separate powershell.exe
    per host (~200 MB each). 100 hosts = 20 GB and 30 seconds of warm-up.
    A runspace pool is in-process and ~5 ms to spin up -- you can fan out
    to 1000 hosts on a workstation.
#>

Set-StrictMode -Version Latest

function Invoke-MSPFleet {
    <#
    .SYNOPSIS
        Run a scriptblock or script file against many computers in parallel.

    .PARAMETER ComputerName
        Hostnames / IPs. Reads from pipeline.
    .PARAMETER ScriptBlock
        Inline scriptblock to run remotely.
    .PARAMETER ScriptPath
        Path to a .ps1 file to ship and run remotely.
    .PARAMETER ArgumentList
        Arguments forwarded to ScriptBlock or ScriptPath.
    .PARAMETER Credential
        Optional PSCredential.
    .PARAMETER Throttle
        Max concurrent hosts. Default from config.fleet.maxConcurrent or 16.
    .PARAMETER TimeoutSec
        Per-host hard timeout. Default 300.

    .EXAMPLE
        # Roll out a Defender signature update across a CSV of hosts
        Import-Csv .\hosts.csv | Invoke-MSPFleet -ScriptBlock { Update-MpSignature }

    .EXAMPLE
        # Run a packaged toolkit script on every host
        Invoke-MSPFleet -ComputerName (Get-Content hosts.txt) `
                       -ScriptPath '.\MSP_Tier3_Toolkit\Security\BitLockerStatusCheck.ps1'
    #>
    [CmdletBinding(DefaultParameterSetName='Block')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName='Block', Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter(ParameterSetName='File', Mandatory)]
        [string]$ScriptPath,

        [object[]]$ArgumentList,

        [pscredential]$Credential,

        [ValidateRange(1, 256)]
        [int]$Throttle,

        [ValidateRange(5, 3600)]
        [int]$TimeoutSec = 300,

        [switch]$PassThru
    )

    begin {
        $allHosts = New-Object System.Collections.Generic.List[string]
        if (-not $Throttle) {
            try {
                $cfg = Get-MSPConfig
                $Throttle = if ($cfg.fleet.maxConcurrent) { [int]$cfg.fleet.maxConcurrent } else { 16 }
            } catch { $Throttle = 16 }
        }
    }
    process { foreach ($c in $ComputerName) { $allHosts.Add($c) } }
    end {
        if ($PSCmdlet.ParameterSetName -eq 'File') {
            if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "Script not found: $ScriptPath" }
            $ScriptBlock = [scriptblock]::Create((Get-Content -Raw -LiteralPath $ScriptPath))
        }

        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $pool = [runspacefactory]::CreateRunspacePool(1, $Throttle, $iss, $Host)
        $pool.Open()

        $jobs = New-Object System.Collections.Generic.List[object]
        foreach ($c in $allHosts) {
            $worker = [powershell]::Create()
            $worker.RunspacePool = $pool

            [void]$worker.AddScript({
                param($ComputerName, $InnerSB, $Args, $Cred, $TimeoutSec)
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $sessionParams = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
                    if ($Cred) { $sessionParams.Credential = $Cred }

                    $invokeParams = @{
                        ScriptBlock = $InnerSB
                        ErrorAction = 'Stop'
                    }
                    if ($Args) { $invokeParams.ArgumentList = $Args }

                    $result = $null
                    $job = Start-Job -ScriptBlock {
                        param($sp, $ip)
                        Invoke-Command @sp @ip
                    } -ArgumentList $sessionParams, $invokeParams

                    if (Wait-Job $job -Timeout $TimeoutSec) {
                        $result = Receive-Job $job -ErrorAction Stop
                        $status = 'Success'
                        $err = $null
                    } else {
                        Stop-Job $job
                        $result = $null
                        $status = 'Timeout'
                        $err = "Timed out after ${TimeoutSec}s"
                    }
                    Remove-Job $job -Force

                    [pscustomobject]@{
                        ComputerName = $ComputerName
                        Status       = $status
                        DurationMs   = $sw.ElapsedMilliseconds
                        Result       = $result
                        Error        = $err
                    }
                } catch {
                    [pscustomobject]@{
                        ComputerName = $ComputerName
                        Status       = 'Failed'
                        DurationMs   = $sw.ElapsedMilliseconds
                        Result       = $null
                        Error        = $_.Exception.Message
                    }
                }
            })
            [void]$worker.AddArgument($c)
            [void]$worker.AddArgument($ScriptBlock)
            [void]$worker.AddArgument($ArgumentList)
            [void]$worker.AddArgument($Credential)
            [void]$worker.AddArgument($TimeoutSec)

            $jobs.Add([pscustomobject]@{
                Pipe   = $worker
                Handle = $worker.BeginInvoke()
                Host   = $c
            })
        }

        $results = New-Object System.Collections.Generic.List[object]
        $done = 0
        while ($jobs.Where({ -not $_.Handle.IsCompleted }).Count -gt 0) {
            Start-Sleep -Milliseconds 250
            $newDone = $jobs.Where({ $_.Handle.IsCompleted }).Count
            if ($newDone -ne $done) {
                $done = $newDone
                Write-Progress -Activity "Invoke-MSPFleet" `
                               -Status "$done / $($jobs.Count) hosts complete" `
                               -PercentComplete ([int](($done/$jobs.Count)*100))
            }
        }
        Write-Progress -Activity "Invoke-MSPFleet" -Completed

        foreach ($j in $jobs) {
            try {
                $r = $j.Pipe.EndInvoke($j.Handle)
                foreach ($x in $r) { $results.Add($x) }
            } catch {
                $results.Add([pscustomobject]@{
                    ComputerName = $j.Host
                    Status       = 'Failed'
                    DurationMs   = 0
                    Result       = $null
                    Error        = $_.Exception.Message
                })
            }
            $j.Pipe.Dispose()
        }
        $pool.Close(); $pool.Dispose()

        if ($PassThru) { return $results }

        # Default: return summary + results so the user gets both
        [pscustomobject]@{
            TotalHosts = $results.Count
            Succeeded  = ($results | Where-Object Status -eq 'Success').Count
            Failed     = ($results | Where-Object Status -in 'Failed','Timeout').Count
            Results    = $results.ToArray()
        }
    }
}

Export-ModuleMember -Function 'Invoke-MSPFleet'
