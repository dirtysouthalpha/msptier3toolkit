<#
.SYNOPSIS
    MSP Toolkit - Auto-Update System
.DESCRIPTION
    Checks for and applies updates from Git repository with automatic backup
#>

[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Force,
    [switch]$NoBackup
)

# Import modules
$CorePath = "$PSScriptRoot\..\Core"
Import-Module "$CorePath\MSPToolkit.Config.psm1" -Force
Import-Module "$CorePath\MSPToolkit.Logging.psm1" -Force

Initialize-MSPLogging -ScriptName "Update"
$config = Get-MSPConfig

Write-MSPLog "═══ MSP Toolkit Update System ═══" -Level HEADER

# Check if Git is available
try {
    $gitVersion = git --version 2>&1
    Write-MSPLog "Git detected: $gitVersion" -Level SUCCESS
}
catch {
    Show-MSPError -Message "Git is not installed or not in PATH" -Details "Please install Git from https://git-scm.com/"
    return
}

$repoPath = $PSScriptRoot | Split-Path
$repoUrl = $config.updates.gitRepoUrl
$branch = $config.updates.updateBranch

Write-MSPLog "Repository: $repoUrl" -Level INFO
Write-MSPLog "Branch: $branch" -Level INFO
Write-MSPLog "Local path: $repoPath" -Level INFO

# Check if we're in a Git repo
Push-Location $repoPath
try {
    $isGitRepo = Test-Path ".git"

    if (-not $isGitRepo) {
        Write-MSPLog "Not a Git repository. Attempting to initialize..." -Level WARNING

        if ($Force) {
            git init
            git remote add origin $repoUrl
            git fetch origin
            git checkout -b $branch origin/$branch
            Write-MSPLog "Repository initialized" -Level SUCCESS
        } else {
            Show-MSPError -Message "Not a Git repository" -Details "Use -Force to initialize"
            return
        }
    }

    # Fetch latest changes
    Write-MSPLog "Fetching latest changes..." -Level INFO
    Write-MSPProgress -Activity "Updating MSP Toolkit" -Status "Fetching from remote..." -PercentComplete 20

    git fetch origin 2>&1 | Out-Null

    # Get current and remote commit
    $currentCommit = git rev-parse HEAD
    $remoteCommit = git rev-parse "origin/$branch"

    Write-MSPLog "Current commit: $($currentCommit.Substring(0,8))" -Level INFO
    Write-MSPLog "Remote commit:  $($remoteCommit.Substring(0,8))" -Level INFO

    if ($currentCommit -eq $remoteCommit) {
        Write-MSPProgress -Activity "Updating MSP Toolkit" -Status "Already up to date" -PercentComplete 100
        Show-MSPSuccess -Message "You are running the latest version!"
        Write-Host ""
        Write-Host "  Current Version: " -NoNewline -ForegroundColor Gray
        Write-Host $config.version -ForegroundColor Green
        Write-Host "  Commit: " -NoNewline -ForegroundColor Gray
        Write-Host $currentCommit.Substring(0,8) -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # Show what will be updated
    Write-MSPLog "Updates available!" -Level SUCCESS
    Write-Host ""
    Write-Host "  Changes:" -ForegroundColor Cyan
    Write-Host "  ────────" -ForegroundColor DarkGray

    $changes = git log --oneline "$currentCommit..$remoteCommit" --no-merges
    $changes | ForEach-Object {
        Write-Host "    • $_" -ForegroundColor Yellow
    }

    Write-Host ""

    if ($CheckOnly) {
        Write-MSPLog "Check-only mode. Use without -CheckOnly to apply updates." -Level INFO
        return
    }

    # Confirm update
    if (-not $Force) {
        Write-Host "  Apply these updates? (Y/N): " -NoNewline -ForegroundColor Yellow
        $confirm = Read-Host

        if ($confirm -ne 'Y' -and $confirm -ne 'y') {
            Write-MSPLog "Update cancelled by user" -Level WARNING
            return
        }
    }

    # Create backup
    if (-not $NoBackup -and $config.updates.backupBeforeUpdate) {
        Write-MSPProgress -Activity "Updating MSP Toolkit" -Status "Creating backup..." -PercentComplete 40

        $backupPath = Join-Path $config.paths.backups "MSPToolkit_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

        if (-not (Test-Path $config.paths.backups)) {
            New-Item -ItemType Directory -Path $config.paths.backups -Force | Out-Null
        }

        Write-MSPLog "Creating backup at: $backupPath" -Level INFO

        # Copy current version
        Copy-Item -Path $repoPath -Destination $backupPath -Recurse -Force -Exclude ".git"

        Write-MSPLog "Backup created successfully" -Level SUCCESS

        # Clean old backups (keep last 5)
        $oldBackups = Get-ChildItem -Path $config.paths.backups -Directory |
            Sort-Object CreationTime -Descending |
            Select-Object -Skip 5

        if ($oldBackups) {
            Write-MSPLog "Cleaning $($oldBackups.Count) old backup(s)..." -Level INFO
            $oldBackups | Remove-Item -Recurse -Force
        }
    }

    # Apply update
    Write-MSPProgress -Activity "Updating MSP Toolkit" -Status "Applying updates..." -PercentComplete 60

    try {
        # Stash any local changes
        $stashResult = git stash 2>&1

        # Pull changes
        git pull origin $branch --no-edit 2>&1 | Out-Null

        Write-MSPProgress -Activity "Updating MSP Toolkit" -Status "Update complete!" -PercentComplete 100

        # Get new version
        $newConfig = Get-MSPConfig -Reload
        $newCommit = git rev-parse HEAD

        Show-MSPSuccess -Message "Update completed successfully!"

        Write-Host ""
        Write-Host "  ╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "  ║              UPDATE SUMMARY                            ║" -ForegroundColor Green
        Write-Host "  ╠════════════════════════════════════════════════════════╣" -ForegroundColor Green
        Write-Host "  ║                                                        ║" -ForegroundColor Green
        Write-Host "  ║  Old Version: " -NoNewline -ForegroundColor Green
        Write-Host "$($config.version.PadRight(35))     ║" -ForegroundColor White
        Write-Host "  ║  New Version: " -NoNewline -ForegroundColor Green
        Write-Host "$($newConfig.version.PadRight(35))     ║" -ForegroundColor Yellow
        Write-Host "  ║                                                        ║" -ForegroundColor Green
        Write-Host "  ║  Old Commit:  " -NoNewline -ForegroundColor Green
        Write-Host "$($currentCommit.Substring(0,8).PadRight(35))     ║" -ForegroundColor White
        Write-Host "  ║  New Commit:  " -NoNewline -ForegroundColor Green
        Write-Host "$($newCommit.Substring(0,8).PadRight(35))     ║" -ForegroundColor Yellow
        Write-Host "  ║                                                        ║" -ForegroundColor Green
        if (-not $NoBackup -and $config.updates.backupBeforeUpdate) {
            Write-Host "  ║  Backup:      " -NoNewline -ForegroundColor Green
            Write-Host "Created                                 ║" -ForegroundColor Green
        }
        Write-Host "  ║                                                        ║" -ForegroundColor Green
        Write-Host "  ╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""

        Write-MSPLog "Restart the toolkit to use the new version" -Level INFO
    }
    catch {
        Write-MSPLog "Update failed: $_" -Level ERROR
        Show-MSPError -Message "Update failed!" -Details $_.Exception.Message

        # Restore from backup if available
        if (-not $NoBackup -and $config.updates.backupBeforeUpdate -and $backupPath) {
            Write-MSPLog "Attempting to restore from backup..." -Level WARNING
            Copy-Item -Path "$backupPath\*" -Destination $repoPath -Recurse -Force
            Write-MSPLog "Restored from backup" -Level SUCCESS
        }
    }
}
finally {
    Pop-Location
    Write-Progress -Activity "Updating MSP Toolkit" -Completed
}
