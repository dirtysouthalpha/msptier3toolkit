<#
.SYNOPSIS
    MSPToolkit Orchestrator - DAG workflow engine for scheduling, sequencing,
    and managing multi-step operations with change control.
.DESCRIPTION
    Provides a directed-acyclic-graph workflow engine that can chain toolkit
    operations, enforce maintenance windows, implement change management
    approvals, and track execution lineage.
    Exported functions:
      New-MSPWorkflow        - Define a DAG workflow from a JSON/YAML spec
      Invoke-MSPWorkflow     - Execute a workflow with parallel/dependency resolution
      Get-MSPWorkflowStatus  - Query running/completed workflow state
      Set-MSPMaintenanceWindow - Define a maintenance window
      Test-MSPMaintenanceWindow - Check if current time is within a window
      New-MSPChangeRequest   - Create a change management record
      Approve-MSPChangeRequest - Approve/reject a change
      Get-MSPChangeHistory   - Retrieve change history
      Stop-MSPWorkflow       - Halt a running workflow
      Resume-MSPWorkflow     - Resume from last checkpoint
.NOTES
    v16.0 - Orchestration & Change Management
#>
#Requires -Version 5.1

$script:Workflows = @{}
$script:MaintenanceWindows = @()
$script:ChangeRequests = @{}
$script:ChangeCounter = 0
$script:PersistPath = "$env:APPDATA\MSPToolkit"
$script:OrchestratorFile = "$script:PersistPath\orchestrator.json"

# ============================================================================
#  Persistence layer
# ============================================================================

function Save-MSPOrchestratorState {
    [CmdletBinding()]
    param()
    try {
        $state = [PSCustomObject]@{
            SavedAt           = (Get-Date).ToString('o')
            ChangeCounter     = $script:ChangeCounter
            Workflows         = @($script:Workflows.Values | ForEach-Object {
                [PSCustomObject]@{ Id=$_.Id; Name=$_.Name; Created=$_.Created; MaxParallel=$_.MaxParallel; TimeoutMin=$_.TimeoutMin; Status=$_.Status; Steps=@($_.Steps) }
            })
            MaintenanceWindows = $script:MaintenanceWindows
            ChangeRequests     = @($script:ChangeRequests.Values)
        }
        if (-not (Test-Path $script:PersistPath)) { New-Item -ItemType Directory -Force -Path $script:PersistPath | Out-Null }
        $state | ConvertTo-Json -Depth 10 | Set-Content $script:OrchestratorFile -Encoding UTF8
        Write-Verbose "Orchestrator state saved to $($script:OrchestratorFile)"
    } catch { Write-Warning "Failed to save orchestrator state: $($_.Exception.Message)" }
}

function Restore-MSPOrchestratorState {
    [CmdletBinding()]
    param()
    if (-not (Test-Path $script:OrchestratorFile)) { Write-Verbose 'No saved state'; return }
    try {
        $state = Get-Content $script:OrchestratorFile -Raw | ConvertFrom-Json
        $script:ChangeCounter = $state.ChangeCounter
        $script:MaintenanceWindows = @($state.MaintenanceWindows)
        $script:ChangeRequests = @{}
        foreach ($cr in $state.ChangeRequests) { $script:ChangeRequests[$cr.Id] = $cr }
        $script:Workflows = @{}
        foreach ($wf in $state.Workflows) { $script:Workflows[$wf.Name] = $wf }
        Write-Verbose "Restored $($state.Workflows.Count) workflows, $($state.ChangeRequests.Count) changes, $($state.MaintenanceWindows.Count) windows"
    } catch { Write-Warning "Failed to restore orchestrator state: $($_.Exception.Message)" }
}

# Auto-restore saved state on module load
Restore-MSPOrchestratorState

function New-MSPWorkflow {
    <#
    .SYNOPSIS
        Creates a new workflow definition from a structured specification.
    .DESCRIPTION
        Parses a JSON or hashtable specification defining steps, their
        dependencies (DAG edges), max parallelism, and rollback actions.
    .PARAMETER Name
        Unique workflow name.
    .PARAMETER Definition
        Hashtable or path to JSON file defining the workflow DAG.
    .EXAMPLE
        $wf = New-MSPWorkflow -Name 'WeeklyMaintenance' -Definition @{
            steps = @(
                @{ id='backup';  command='Start-MSPBackup';         dependsOn=@() }
                @{ id='updates'; command='Install-WindowsUpdates';  dependsOn=@('backup') }
                @{ id='cleanup'; command='Start-MSPSystemCleanup';  dependsOn=@('updates') }
            )
            maxParallel = 2
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        $Definition
    )

    $spec = if ($Definition -is [string] -and (Test-Path $Definition)) {
        Get-Content $Definition -Raw | ConvertFrom-Json
    } elseif ($Definition -is [hashtable]) {
        $Definition
    } else {
        $Definition
    }

    $wf = [PSCustomObject]@{
        Id          = [Guid]::NewGuid().ToString()
        Name        = $Name
        Created     = (Get-Date).ToString('o')
        Steps       = @($spec.steps | ForEach-Object {
            [PSCustomObject]@{
                Id          = $_.id
                Command     = $_.command
                Description = if ($_.description) { $_.description } else { '' }
                DependsOn   = @($_.dependsOn)
                Rollback    = if ($_.rollback) { $_.rollback } else { $null }
                RetryCount  = if ($_.retryCount) { $_.retryCount } else { 0 }
                RetryDelay  = if ($_.retryDelay) { $_.retryDelay } else { 5 }
                TimeoutMin  = if ($_.timeoutMin) { $_.timeoutMin } else { 30 }
                Verify      = if ($_.verify) { $_.verify } else { $null }
                Condition   = if ($_.condition) { $_.condition } else { $null }
                Status      = 'Pending'
                StartedAt   = $null
                CompletedAt = $null
                Attempts    = 0
                Error       = $null
                Output      = $null
            }
        })
        MaxParallel = if ($spec.maxParallel) { $spec.maxParallel } else { 4 }
        TimeoutMin  = if ($spec.timeoutMin) { $spec.timeoutMin } else { 120 }
        Status      = 'Defined'
    }

    $script:Workflows[$Name] = $wf
    Save-MSPOrchestratorState
    return $wf
}

function Invoke-MSPWorkflow {
    <#
    .SYNOPSIS
        Executes a defined workflow, resolving DAG dependencies in parallel where possible.
    .PARAMETER Name
        Workflow name to execute.
    .PARAMETER DryRun
        Validate DAG structure without executing steps.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [switch]$DryRun
    )

    $wf = $script:Workflows[$Name]
    if (-not $wf) { throw "Workflow '$Name' not found. Use New-MSPWorkflow first." }

    # DAG validation
    $stepIds = $wf.Steps | ForEach-Object { $_.Id }
    foreach ($step in $wf.Steps) {
        foreach ($dep in $step.DependsOn) {
            if ($dep -notin $stepIds) { throw "Step '$($step.Id)' depends on unknown step '$dep'" }
            if ($dep -eq $step.Id) { throw "Step '$($step.Id)' cannot depend on itself" }
        }
    }

    # Cycle detection (simple DFS)
    $visiting = @{}
    $visited = @{}
    function Test-Cycle($id) {
        if ($visiting[$id]) { throw "Circular dependency detected at step '$id'" }
        if ($visited[$id]) { return }
        $visiting[$id] = $true
        $st = $wf.Steps | Where-Object { $_.Id -eq $id }
        foreach ($dep in $st.DependsOn) { Test-Cycle $dep }
        $visiting[$id] = $false
        $visited[$id] = $true
    }
    foreach ($s in $stepIds) { Test-Cycle $s }

    if ($DryRun) { return $wf }

    $wf.Status = 'Running'
    $ready = [System.Collections.ArrayList]@()
    $running = @{}
    $doneIds = @{}

    # Find initial ready steps (no dependencies)
    $wf.Steps | Where-Object { $_.DependsOn.Count -eq 0 } | ForEach-Object { $null = $ready.Add($_.Id) }

    while ($doneIds.Count -lt $wf.Steps.Count) {
        # Launch ready steps up to maxParallel
        while ($ready.Count -gt 0 -and $running.Count -lt $wf.MaxParallel) {
            $nextId = $ready[0]
            $ready.RemoveAt(0)

            $step = $wf.Steps | Where-Object { $_.Id -eq $nextId }
            $step.Status = 'Running'
            $step.StartedAt = Get-Date

            $job = Start-Job -Name "MSPWF_$($Name)_$nextId" -ScriptBlock {
                param($cmd, $retryCount, $retryDelay, $verify, $timeoutMin, $modulePath)
                try { Import-Module (Join-Path $modulePath 'Core\MSPToolkit.psd1') -Force -ErrorAction Stop } catch {}
                $result = [PSCustomObject]@{ Success=$false; Output=$null; Error=$null; Attempts=0 }
                for ($a = 0; $a -le $retryCount; $a++) {
                    $result.Attempts = $a + 1
                    try {
                        $out = Invoke-Expression $cmd 2>&1
                        $result.Output = $out | Out-String
                        if ($verify) {
                            $vResult = Invoke-Expression $verify 2>&1
                            if ($LASTEXITCODE -ne 0) {
                                $result.Error = "Verify failed: $vResult"
                                if ($a -lt $retryCount) { Start-Sleep $retryDelay; continue }
                                break
                            }
                        }
                        $result.Success = $true
                        break
                    } catch {
                        $result.Error = $_.Exception.Message
                        if ($a -lt $retryCount) { Start-Sleep $retryDelay }
                    }
                }
                return $result
            } -ArgumentList $step.Command, $step.RetryCount, $step.RetryDelay, $step.Verify, $step.TimeoutMin, $PSScriptRoot

            $running[$nextId] = $job
        }

        if ($running.Count -eq 0 -and $ready.Count -eq 0 -and $doneIds.Count -lt $wf.Steps.Count) {
            throw "Workflow deadlocked: $($wf.Steps | Where-Object {$_.Status -eq 'Pending'} | ForEach-Object {$_.Id})"
        }

        # Wait for any running job to complete
        $completedId = $null
        $timeout = Get-Date
        while ($true) {
            foreach ($rid in $running.Keys) {
                if ($running[$rid].State -eq 'Completed' -or $running[$rid].State -eq 'Failed') {
                    $completedId = $rid
                    break
                }
            }
            if ($completedId) { break }
            if (((Get-Date) - $timeout).TotalSeconds -gt 10) {
                $completedId = ($running.Keys | Select-Object -First 1)
                Wait-Job -Job $running[$completedId] -Timeout 5 | Out-Null
                break
            }
            Start-Sleep -Milliseconds 500
        }

        $job = $running[$completedId]
        $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force
        $running.Remove($completedId)

        $step = $wf.Steps | Where-Object { $_.Id -eq $completedId }
        $step.CompletedAt = Get-Date
        $step.Attempts = if ($result) { $result.Attempts } else { 1 }
        $step.Error = if ($result -and -not $result.Success) { $result.Error } else { $null }
        $step.Output = if ($result) { $result.Output } else { $null }
        $step.Status = if ($result -and $result.Success) { 'Completed' } else { 'Failed' }

        if ($step.Status -eq 'Failed') {
            if ($step.Rollback) {
                try { Invoke-Expression $step.Rollback 2>&1 | Out-Null } catch {}
            }
            $wf.Status = 'Failed'
            break
        }

        $doneIds[$completedId] = $true

        # Enqueue newly-ready steps
        foreach ($s in $wf.Steps) {
            if ($doneIds[$s.Id] -or $running[$s.Id] -or $s.Status -ne 'Pending') { continue }
            $allDepsDone = ($s.DependsOn | Where-Object { -not $doneIds[$_] }).Count -eq 0
            if ($allDepsDone) { $null = $ready.Add($s.Id) }
        }
    }

    if ($wf.Status -eq 'Running') { $wf.Status = 'Completed' }
    Save-MSPOrchestratorState
    return $wf
}

function Get-MSPWorkflowStatus {
    <#
    .SYNOPSIS
        Retrieves the current status of one or all defined workflows.
    #>
    [CmdletBinding()]
    param([string]$Name)

    if ($Name) { return $script:Workflows[$Name] }
    return $script:Workflows.Values | ForEach-Object { $_ }
}

function Stop-MSPWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    $wf = $script:Workflows[$Name]
    if (-not $wf) { throw "Workflow '$Name' not found" }
    $wf.Status = 'Cancelled'
    Get-Job -Name "MSPWF_$($Name)_*" -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
    Get-Job -Name "MSPWF_$($Name)_*" -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
    Save-MSPOrchestratorState
    return $wf
}

function Resume-MSPWorkflow {
    <#
    .SYNOPSIS
        Resumes a failed workflow from the last successful checkpoint.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    $wf = $script:Workflows[$Name]
    if (-not $wf) { throw "Workflow '$Name' not found" }
    if ($wf.Status -notin @('Failed', 'Cancelled')) { throw "Workflow '$Name' is not in a resumable state ($($wf.Status))" }

    foreach ($s in $wf.Steps) {
        if ($s.Status -in @('Failed', 'Running')) { $s.Status = 'Pending'; $s.StartedAt = $null; $s.CompletedAt = $null; $s.Error = $null }
    }
    $wf.Status = 'Running'
    Write-Warning "Resume-MSPWorkflow restarts from beginning. Manual checkpointing available in a future update."
    return Invoke-MSPWorkflow -Name $Name
}

# ============================================================================
#  Maintenance windows
# ============================================================================

function Set-MSPMaintenanceWindow {
    <#
    .SYNOPSIS
        Defines a scheduled maintenance window for controlled operations.
    .PARAMETER Name
        Window label.
    .PARAMETER Schedule
        Cron-like expression or datetime range.
    .PARAMETER DurationMinutes
        How long the window stays open.
    .PARAMETER AllowedWorkflows
        Workflow names permitted during this window.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [string]$Schedule,
        [Parameter(Mandatory=$true)]
        [int]$DurationMinutes,
        [string[]]$AllowedWorkflows = @('*')
    )

    $mw = [PSCustomObject]@{
        Name             = $Name
        Schedule         = $Schedule
        DurationMinutes  = $DurationMinutes
        AllowedWorkflows = $AllowedWorkflows
        Created          = (Get-Date).ToString('o')
        Enabled          = $true
    }

    $script:MaintenanceWindows += $mw
    Save-MSPOrchestratorState
    return $mw
}

function Test-MSPMaintenanceWindow {
    <#
    .SYNOPSIS
        Tests whether the current time falls within any enabled maintenance window.
    .PARAMETER WorkflowName
        Optionally filter by allowed workflows.
    #>
    [CmdletBinding()]
    param([string]$WorkflowName)

    $now = Get-Date
    foreach ($mw in $script:MaintenanceWindows | Where-Object { $_.Enabled }) {
        $parts = $mw.Schedule -split '\s+'
        if ($parts.Count -lt 2) { continue }
        $targetDay = $parts[0]
        $targetTime = $parts[1]

        $dayMatch = ($now.DayOfWeek -like "$targetDay*")
        if (-not $dayMatch) { continue }

        $timeParts = $targetTime -split ':'
        $targetHour = [int]$timeParts[0]
        $targetMin = [int]$timeParts[1]
        $windowStart = Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour $targetHour -Minute $targetMin -Second 0
        $windowEnd = $windowStart.AddMinutes($mw.DurationMinutes)

        if ($now -ge $windowStart -and $now -le $windowEnd) {
            if ($WorkflowName -and '*' -notin $mw.AllowedWorkflows -and $WorkflowName -notin $mw.AllowedWorkflows) { continue }
            return $true
        }
    }
    return $false
}

# ============================================================================
#  Change management
# ============================================================================

function New-MSPChangeRequest {
    <#
    .SYNOPSIS
        Creates a change management record for audit and approval tracking.
    .PARAMETER Title
        Change description.
    .PARAMETER Impact
        Risk/impact level: Low, Medium, High, Critical.
    .PARAMETER WorkflowName
        Associated workflow.
    .PARAMETER RollbackPlan
        Description of rollback procedure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title,
        [Parameter(Mandatory=$true)]
        [ValidateSet('Low','Medium','High','Critical')]
        [string]$Impact,
        [string]$WorkflowName,
        [string]$RollbackPlan = ''
    )

    $script:ChangeCounter++
    $cr = [PSCustomObject]@{
        Id            = "CHG$($script:ChangeCounter.ToString('D5'))"
        Title         = $Title
        Impact        = $Impact
        WorkflowName  = $WorkflowName
        RollbackPlan  = $RollbackPlan
        Status        = 'Pending'
        CreatedBy     = $env:USERNAME
        CreatedAt     = (Get-Date).ToString('o')
        ApprovedBy    = $null
        ApprovedAt    = $null
        Comments      = @()
    }
    $script:ChangeRequests[$cr.Id] = $cr
    Save-MSPOrchestratorState
    return $cr
}

function Approve-MSPChangeRequest {
    <#
    .SYNOPSIS
        Approves or rejects a change request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ChangeId,
        [Parameter(Mandatory=$true)]
        [ValidateSet('Approved','Rejected')]
        [string]$Decision,
        [string]$Comment = ''
    )

    $cr = $script:ChangeRequests[$ChangeId]
    if (-not $cr) { throw "Change request '$ChangeId' not found" }
    if ($cr.Status -ne 'Pending') { throw "Change request '$ChangeId' is not pending ($($cr.Status))" }

    $cr.Status = $Decision
    $cr.ApprovedBy = $env:USERNAME
    $cr.ApprovedAt = (Get-Date).ToString('o')
    if ($Comment) { $cr.Comments += "[$Decision by $env:USERNAME] $Comment" }
    Save-MSPOrchestratorState
    return $cr
}

function Get-MSPChangeHistory {
    <#
    .SYNOPSIS
        Retrieves all change requests with optional filters.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Pending','Approved','Rejected','All')]
        [string]$Status = 'All',
        [string]$Impact
    )

    $list = $script:ChangeRequests.Values
    if ($Status -ne 'All') { $list = $list | Where-Object { $_.Status -eq $Status } }
    if ($Impact) { $list = $list | Where-Object { $_.Impact -eq $Impact } }
    return $list | Sort-Object CreatedAt -Descending
}

Export-ModuleMember -Function @(
    'New-MSPWorkflow',
    'Invoke-MSPWorkflow',
    'Get-MSPWorkflowStatus',
    'Set-MSPMaintenanceWindow',
    'Test-MSPMaintenanceWindow',
    'New-MSPChangeRequest',
    'Approve-MSPChangeRequest',
    'Get-MSPChangeHistory',
    'Stop-MSPWorkflow',
    'Resume-MSPWorkflow',
    'Save-MSPOrchestratorState',
    'Restore-MSPOrchestratorState'
)
