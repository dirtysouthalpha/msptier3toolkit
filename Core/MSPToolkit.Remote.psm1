<#
.SYNOPSIS
    MSP Toolkit - Remote Execution Module
.DESCRIPTION
    Enables remote execution of toolkit scripts across multiple computers
#>

Import-Module "$PSScriptRoot\MSPToolkit.Logging.psm1" -Force
Import-Module "$PSScriptRoot\MSPToolkit.Config.psm1" -Force

function Invoke-MSPRemoteScript {
    <#
    .SYNOPSIS
        Execute a script block on remote computer(s)
    .PARAMETER ComputerName
        Target computer name(s)
    .PARAMETER ScriptBlock
        Script block to execute
    .PARAMETER Credential
        PSCredential object for authentication
    .PARAMETER ArgumentList
        Arguments to pass to the script block
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$ComputerName,

        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,

        [PSCredential]$Credential,

        [object[]]$ArgumentList,

        [switch]$AsJob
    )

    $config = Get-MSPConfig
    $results = @()

    foreach ($computer in $ComputerName) {
        Write-MSPLog "Executing script on $computer..." -Level INFO

        try {
            $sessionParams = @{
                ComputerName = $computer
                ErrorAction = 'Stop'
            }

            if ($Credential) {
                $sessionParams.Credential = $Credential
            }

            $invokeParams = @{
                ScriptBlock = $ScriptBlock
                ErrorAction = 'Stop'
            }

            if ($ArgumentList) {
                $invokeParams.ArgumentList = $ArgumentList
            }

            if ($AsJob) {
                $job = Invoke-Command @sessionParams @invokeParams -AsJob
                $results += [PSCustomObject]@{
                    ComputerName = $computer
                    Status = 'Running'
                    Job = $job
                    StartTime = Get-Date
                }
                Write-MSPLog "Started background job for $computer (ID: $($job.Id))" -Level SUCCESS
            } else {
                $result = Invoke-Command @sessionParams @invokeParams
                $results += [PSCustomObject]@{
                    ComputerName = $computer
                    Status = 'Success'
                    Result = $result
                    CompletedTime = Get-Date
                }
                Write-MSPLog "Successfully executed on $computer" -Level SUCCESS
            }
        }
        catch {
            Write-MSPLog "Failed to execute on $computer : $_" -Level ERROR
            $results += [PSCustomObject]@{
                ComputerName = $computer
                Status = 'Failed'
                Error = $_.Exception.Message
                FailedTime = Get-Date
            }
        }
    }

    return $results
}

function Invoke-MSPRemoteScriptFile {
    <#
    .SYNOPSIS
        Execute a script file on remote computer(s)
    .PARAMETER ComputerName
        Target computer name(s)
    .PARAMETER ScriptPath
        Path to the script file
    .PARAMETER Credential
        PSCredential object for authentication
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$ComputerName,

        [Parameter(Mandatory=$true)]
        [string]$ScriptPath,

        [PSCredential]$Credential,

        [hashtable]$Parameters
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-MSPLog "Script file not found: $ScriptPath" -Level ERROR
        return
    }

    $scriptContent = Get-Content $ScriptPath -Raw
    $scriptBlock = [scriptblock]::Create($scriptContent)

    $argumentList = @()
    if ($Parameters) {
        foreach ($key in $Parameters.Keys) {
            $argumentList += "-$key"
            $argumentList += $Parameters[$key]
        }
    }

    return Invoke-MSPRemoteScript -ComputerName $ComputerName -ScriptBlock $scriptBlock -Credential $Credential -ArgumentList $argumentList
}

function Get-MSPRemoteComputerStatus {
    <#
    .SYNOPSIS
        Test connectivity to remote computer(s)
    .PARAMETER ComputerName
        Target computer name(s)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$ComputerName
    )

    $results = @()

    foreach ($computer in $ComputerName) {
        Write-MSPProgress -Activity "Testing Connectivity" -Status "Checking $computer" -PercentComplete (($results.Count / $ComputerName.Count) * 100)

        $status = [PSCustomObject]@{
            ComputerName = $computer
            Online = $false
            WSManAvailable = $false
            ResponseTime = $null
        }

        # Test ping
        $ping = Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue
        $status.Online = $ping

        if ($ping) {
            $pingResult = Test-Connection -ComputerName $computer -Count 1 -ErrorAction SilentlyContinue
            $status.ResponseTime = $pingResult.ResponseTime

            # Test WSMan
            $wsmanTest = Test-WSMan -ComputerName $computer -ErrorAction SilentlyContinue
            $status.WSManAvailable = $null -ne $wsmanTest
        }

        $results += $status
    }

    Write-Progress -Activity "Testing Connectivity" -Completed

    return $results
}

function Import-MSPComputerList {
    <#
    .SYNOPSIS
        Import computer names from CSV file
    .PARAMETER Path
        Path to CSV file (must have ComputerName column)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    try {
        if (-not (Test-Path $Path)) {
            Write-MSPLog "File not found: $Path" -Level ERROR
            return @()
        }

        $csv = Import-Csv -Path $Path
        $computers = $csv.ComputerName

        Write-MSPLog "Imported $($computers.Count) computers from $Path" -Level SUCCESS
        return $computers
    }
    catch {
        Write-MSPLog "Failed to import computer list: $_" -Level ERROR
        return @()
    }
}

function New-MSPCredential {
    <#
    .SYNOPSIS
        Create and optionally save a credential
    .PARAMETER Name
        Name to identify this credential
    .PARAMETER Save
        Save credential securely to disk
    #>
    [CmdletBinding()]
    param(
        [string]$Name = "Default",
        [switch]$Save
    )

    $credential = Get-Credential -Message "Enter credentials for $Name"

    if ($Save -and $credential) {
        $config = Get-MSPConfig
        $credPath = Join-Path $config.paths.cache "Credentials"

        if (-not (Test-Path $credPath)) {
            New-Item -ItemType Directory -Path $credPath -Force | Out-Null
        }

        $credFile = Join-Path $credPath "$Name.xml"
        $credential | Export-Clixml -Path $credFile

        Write-MSPLog "Credential saved: $credFile" -Level SUCCESS
    }

    return $credential
}

function Get-MSPCredential {
    <#
    .SYNOPSIS
        Retrieve a saved credential
    .PARAMETER Name
        Name of the credential to retrieve
    #>
    [CmdletBinding()]
    param(
        [string]$Name = "Default"
    )

    $config = Get-MSPConfig
    $credFile = Join-Path $config.paths.cache "Credentials\$Name.xml"

    if (Test-Path $credFile) {
        return Import-Clixml -Path $credFile
    } else {
        Write-MSPLog "Credential not found: $Name" -Level WARNING
        return $null
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Invoke-MSPRemoteScript',
    'Invoke-MSPRemoteScriptFile',
    'Get-MSPRemoteComputerStatus',
    'Import-MSPComputerList',
    'New-MSPCredential',
    'Get-MSPCredential'
)
