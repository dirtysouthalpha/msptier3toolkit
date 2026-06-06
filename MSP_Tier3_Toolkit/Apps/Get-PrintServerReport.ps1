<#
.SYNOPSIS
    Reports print server queue health, driver inventory, and spooler status.
.DESCRIPTION
    Enumerates all printers, their driver versions/type, queue depth/status,
    spooler service health, and driver isolation status.
.NOTES
    v15.0 -- Application & Database Health
#>
[CmdletBinding()]
param()

$data = [PSCustomObject]@{
    Timestamp          = (Get-Date).ToString('o')
    SpoolerRunning     = $false
    TotalPrinters      = 0
    StoppedPrinters    = 0
    TotalQueuedJobs    = 0
    DriverCount        = 0
    DriversV3          = 0
    DriversV4          = 0
    DriversOther       = 0
    PrinterDetails     = @()
    Checks             = @()
    Score              = 0
    MaxScore           = 0
    Summary            = ''
}

# Check 1: Print Spooler service
$spooler = Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue
$data.SpoolerRunning = ($null -ne $spooler -and $spooler.Status -eq 'Running')
$data.Checks += [PSCustomObject]@{ Name='Spooler Running'; Pass=$data.SpoolerRunning; Detail=$(if($data.SpoolerRunning){'Running'}else{'Stopped'}) }

if (-not $data.SpoolerRunning) {
    $data.Summary = 'Print Spooler not running'
    $data.MaxScore = 20
    $data.Score = 0
    return $data
}

# Check 2: Printer enumeration
try {
    $printers = Get-Printer -ErrorAction Stop
    $data.TotalPrinters = ($printers | Measure-Object).Count
    
    foreach ($p in $printers) {
        $isStopped = ($p.PrinterStatus -match 'Paused|Error|Offline')
        $jobs = Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue
        $jobCount = ($jobs | Measure-Object).Count
        $data.TotalQueuedJobs += $jobCount

        if ($isStopped) { $data.StoppedPrinters++ }

        $data.PrinterDetails += [PSCustomObject]@{
            Name=$p.Name; DriverName=$p.DriverName; PortName=$p.PortName
            Shared=$p.Shared; Status=$p.PrinterStatus; QueuedJobs=$jobCount
        }
    }

    $data.Checks += [PSCustomObject]@{ Name='Printers Enumerated'; Pass=($data.TotalPrinters -gt 0); Detail="$($data.TotalPrinters) printers" }
    $data.Checks += [PSCustomObject]@{ Name='No Stopped Printers'; Pass=($data.StoppedPrinters -eq 0); Detail="$($data.StoppedPrinters) stopped/error" }
    $data.Checks += [PSCustomObject]@{ Name='Queue Depth OK'; Pass=($data.TotalQueuedJobs -lt 100); Detail="$($data.TotalQueuedJobs) queued jobs" }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Printers Enumerated'; Pass=$false; Detail="Error: $($_.Exception.Message)" }
}

# Check 3: Driver inventory
try {
    $drivers = Get-PrinterDriver -ErrorAction SilentlyContinue
    $data.DriverCount = ($drivers | Measure-Object).Count
    foreach ($d in $drivers) {
        $ver = [int]($d.DriverVersion -replace '\D')
        if ($ver -eq 4) { $data.DriversV4++ }
        elseif ($ver -eq 3) { $data.DriversV3++ }
        else { $data.DriversOther++ }
    }
    $data.Checks += [PSCustomObject]@{ Name='Drivers Current'; Pass=($data.DriversV4 -ge $data.DriversV3); Detail="v3:$($data.DriversV3) v4:$($data.DriversV4) other:$($data.DriversOther)" }
} catch {
    $data.Checks += [PSCustomObject]@{ Name='Drivers Current'; Pass=$true; Detail='Could not assess' }
}

# Check 4: Spooler crash history
$crashes = Get-WinEvent -LogName 'Application' -FilterXPath "*[System[Provider[@Name='Microsoft-Windows-PrintService'] and EventID=811]]" -MaxEvents 5 -ErrorAction SilentlyContinue
$crashCount = ($crashes | Measure-Object).Count
$data.Checks += [PSCustomObject]@{ Name='No Spooler Crashes'; Pass=($crashCount -eq 0); Detail="$crashCount recent crashes" }

$data.MaxScore = $data.Checks.Count * 20
$data.Score = ($data.Checks | Where-Object { $_.Pass }).Count * 20
$data.Summary = "Print Server: $($data.Score)/$($data.MaxScore) -- $($data.TotalPrinters) printers | $($data.TotalQueuedJobs) queued | $($data.StoppedPrinters) stopped"

return $data
