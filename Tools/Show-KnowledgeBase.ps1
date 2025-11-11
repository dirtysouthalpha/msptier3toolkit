<#
.SYNOPSIS
    MSP Toolkit - Team Knowledge Base
.DESCRIPTION
    View and contribute to team knowledge base for toolkit scripts
#>

[CmdletBinding()]
param(
    [int]$ScriptID,
    [switch]$AddNote,
    [switch]$ViewAll
)

# Import modules
$CorePath = "$PSScriptRoot\..\Core"
Import-Module "$CorePath\MSPToolkit.Config.psm1" -Force
Import-Module "$CorePath\MSPToolkit.Logging.psm1" -Force

Initialize-MSPLogging -ScriptName "KnowledgeBase"
$config = Get-MSPConfig

$kbPath = $config.paths.knowledgeBase
if (-not (Test-Path $kbPath)) {
    New-Item -ItemType Directory -Path $kbPath -Force | Out-Null
}

# Script catalog (matching launcher)
$Script:ToolCatalog = @(
    @{ ID = 1; Name = "System Health Report"; Icon = "📊" },
    @{ ID = 2; Name = "Boot Time Analyzer"; Icon = "⏱️" },
    @{ ID = 3; Name = "Client System Summary"; Icon = "📄" },
    @{ ID = 4; Name = "Check AD User Status"; Icon = "👤" },
    @{ ID = 5; Name = "M365 User Provisioning"; Icon = "☁️" },
    @{ ID = 6; Name = "Cleanup Old Profiles"; Icon = "🧹" },
    @{ ID = 7; Name = "Comprehensive Cleanup"; Icon = "🗑️" },
    @{ ID = 8; Name = "Printer Spooler Fix"; Icon = "🖨️" },
    @{ ID = 9; Name = "Spooler Monitor Setup"; Icon = "👁️" },
    @{ ID = 10; Name = "Fix Mapped Drives"; Icon = "🔌" },
    @{ ID = 11; Name = "Remote Software Uninstall"; Icon = "📦" },
    @{ ID = 12; Name = "Windows Update Fix"; Icon = "🔄" }
)

function Get-KnowledgeBaseEntries {
    param([int]$ToolID)

    $kbFile = Join-Path $kbPath "Script_$ToolID.json"

    if (Test-Path $kbFile) {
        return Get-Content $kbFile | ConvertFrom-Json
    } else {
        return @{
            ScriptID = $ToolID
            ScriptName = ($Script:ToolCatalog | Where-Object { $_.ID -eq $ToolID }).Name
            Notes = @()
            Tips = @()
            CommonIssues = @()
            BestPractices = @()
        }
    }
}

function Save-KnowledgeBaseEntries {
    param(
        [int]$ToolID,
        [object]$Data
    )

    $kbFile = Join-Path $kbPath "Script_$ToolID.json"
    $Data | ConvertTo-Json -Depth 5 | Set-Content $kbFile
    Write-MSPLog "Knowledge base updated for script ID $ToolID" -Level SUCCESS
}

function Show-KnowledgeBaseForScript {
    param([int]$ToolID)

    $tool = $Script:ToolCatalog | Where-Object { $_.ID -eq $ToolID }
    if (-not $tool) {
        Show-MSPError -Message "Invalid script ID: $ToolID"
        return
    }

    $kb = Get-KnowledgeBaseEntries -ToolID $ToolID

    Clear-Host
    Write-MSPLog "═══ Knowledge Base: $($tool.Name) $($tool.Icon) ═══" -Level HEADER

    Write-Host ""

    # Tips
    if ($kb.Tips.Count -gt 0) {
        Write-Host "  💡 TIPS & TRICKS" -ForegroundColor Yellow
        Write-Host "  ───────────────" -ForegroundColor DarkGray
        Write-Host ""
        foreach ($tip in $kb.Tips) {
            Write-Host "    • " -NoNewline -ForegroundColor Yellow
            Write-Host $tip.Text -ForegroundColor White
            Write-Host "      " -NoNewline
            Write-Host "- $($tip.Author) " -NoNewline -ForegroundColor DarkGray
            Write-Host "($($tip.Date))" -ForegroundColor DarkGray
            Write-Host ""
        }
    }

    # Common Issues
    if ($kb.CommonIssues.Count -gt 0) {
        Write-Host "  ⚠️  COMMON ISSUES & SOLUTIONS" -ForegroundColor Red
        Write-Host "  ────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        foreach ($issue in $kb.CommonIssues) {
            Write-Host "    Problem: " -NoNewline -ForegroundColor Red
            Write-Host $issue.Problem -ForegroundColor White
            Write-Host "    Solution: " -NoNewline -ForegroundColor Green
            Write-Host $issue.Solution -ForegroundColor White
            Write-Host "    " -NoNewline
            Write-Host "- $($issue.Author) " -NoNewline -ForegroundColor DarkGray
            Write-Host "($($issue.Date))" -ForegroundColor DarkGray
            Write-Host ""
        }
    }

    # Best Practices
    if ($kb.BestPractices.Count -gt 0) {
        Write-Host "  ✅ BEST PRACTICES" -ForegroundColor Green
        Write-Host "  ────────────────" -ForegroundColor DarkGray
        Write-Host ""
        foreach ($practice in $kb.BestPractices) {
            Write-Host "    • " -NoNewline -ForegroundColor Green
            Write-Host $practice.Text -ForegroundColor White
            Write-Host "      " -NoNewline
            Write-Host "- $($practice.Author) " -NoNewline -ForegroundColor DarkGray
            Write-Host "($($practice.Date))" -ForegroundColor DarkGray
            Write-Host ""
        }
    }

    # General Notes
    if ($kb.Notes.Count -gt 0) {
        Write-Host "  📝 NOTES" -ForegroundColor Cyan
        Write-Host "  ───────" -ForegroundColor DarkGray
        Write-Host ""
        foreach ($note in $kb.Notes) {
            Write-Host "    $($note.Text)" -ForegroundColor Gray
            Write-Host "    " -NoNewline
            Write-Host "- $($note.Author) " -NoNewline -ForegroundColor DarkGray
            Write-Host "($($note.Date))" -ForegroundColor DarkGray
            Write-Host ""
        }
    }

    if ($kb.Tips.Count -eq 0 -and $kb.CommonIssues.Count -eq 0 -and $kb.BestPractices.Count -eq 0 -and $kb.Notes.Count -eq 0) {
        Write-Host "  No knowledge base entries yet for this script." -ForegroundColor Gray
        Write-Host "  Be the first to contribute!" -ForegroundColor Yellow
    }

    Write-Host ""
}

function Add-KnowledgeBaseEntry {
    param([int]$ToolID)

    $tool = $Script:ToolCatalog | Where-Object { $_.ID -eq $ToolID }
    if (-not $tool) {
        Show-MSPError -Message "Invalid script ID: $ToolID"
        return
    }

    Write-MSPLog "═══ Add Knowledge Base Entry: $($tool.Name) ═══" -Level HEADER
    Write-Host ""

    Write-Host "  Select entry type:" -ForegroundColor Cyan
    Write-Host "  [1] Tip/Trick" -ForegroundColor White
    Write-Host "  [2] Common Issue & Solution" -ForegroundColor White
    Write-Host "  [3] Best Practice" -ForegroundColor White
    Write-Host "  [4] General Note" -ForegroundColor White
    Write-Host ""
    Write-Host "  Choice (1-4): " -NoNewline -ForegroundColor Yellow
    $type = Read-Host

    Write-Host ""
    Write-Host "  Your name: " -NoNewline -ForegroundColor Yellow
    $author = Read-Host

    if ([string]::IsNullOrWhiteSpace($author)) {
        $author = $env:USERNAME
    }

    $kb = Get-KnowledgeBaseEntries -ToolID $ToolID

    switch ($type) {
        '1' {
            Write-Host "  Enter your tip: " -NoNewline -ForegroundColor Yellow
            $text = Read-Host

            $kb.Tips += @{
                Text = $text
                Author = $author
                Date = Get-Date -Format "yyyy-MM-dd"
            }

            Write-MSPLog "Tip added successfully!" -Level SUCCESS
        }
        '2' {
            Write-Host "  Describe the problem: " -NoNewline -ForegroundColor Yellow
            $problem = Read-Host

            Write-Host "  Describe the solution: " -NoNewline -ForegroundColor Yellow
            $solution = Read-Host

            $kb.CommonIssues += @{
                Problem = $problem
                Solution = $solution
                Author = $author
                Date = Get-Date -Format "yyyy-MM-dd"
            }

            Write-MSPLog "Issue/Solution added successfully!" -Level SUCCESS
        }
        '3' {
            Write-Host "  Enter the best practice: " -NoNewline -ForegroundColor Yellow
            $text = Read-Host

            $kb.BestPractices += @{
                Text = $text
                Author = $author
                Date = Get-Date -Format "yyyy-MM-dd"
            }

            Write-MSPLog "Best practice added successfully!" -Level SUCCESS
        }
        '4' {
            Write-Host "  Enter your note: " -NoNewline -ForegroundColor Yellow
            $text = Read-Host

            $kb.Notes += @{
                Text = $text
                Author = $author
                Date = Get-Date -Format "yyyy-MM-dd"
            }

            Write-MSPLog "Note added successfully!" -Level SUCCESS
        }
        default {
            Show-MSPError -Message "Invalid selection"
            return
        }
    }

    Save-KnowledgeBaseEntries -ToolID $ToolID -Data $kb
}

# Main logic
if ($ViewAll) {
    Write-MSPLog "═══ Team Knowledge Base ═══" -Level HEADER
    Write-Host ""

    foreach ($tool in $Script:ToolCatalog | Sort-Object ID) {
        $kb = Get-KnowledgeBaseEntries -ToolID $tool.ID
        $totalEntries = $kb.Tips.Count + $kb.CommonIssues.Count + $kb.BestPractices.Count + $kb.Notes.Count

        Write-Host "  [$($tool.ID.ToString().PadLeft(2))] " -NoNewline -ForegroundColor White
        Write-Host "$($tool.Icon)  " -NoNewline
        Write-Host $tool.Name -NoNewline -ForegroundColor Cyan
        if ($totalEntries -gt 0) {
            Write-Host " ($totalEntries entries)" -ForegroundColor Green
        } else {
            Write-Host " (no entries)" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "  Enter script ID to view, or 'Q' to quit: " -NoNewline -ForegroundColor Yellow
    $choice = Read-Host

    if ($choice -ne 'Q' -and $choice -ne 'q') {
        [int]$id = 0
        if ([int]::TryParse($choice, [ref]$id)) {
            Show-KnowledgeBaseForScript -ToolID $id
            Write-Host ""
            Read-Host "Press Enter to continue"
        }
    }
}
elseif ($AddNote) {
    if (-not $ScriptID) {
        Write-Host "  Enter script ID to add note for: " -NoNewline -ForegroundColor Yellow
        $ScriptID = Read-Host
    }

    [int]$id = 0
    if ([int]::TryParse($ScriptID, [ref]$id)) {
        Add-KnowledgeBaseEntry -ToolID $id
    } else {
        Show-MSPError -Message "Invalid script ID"
    }
}
elseif ($ScriptID) {
    Show-KnowledgeBaseForScript -ToolID $ScriptID
    Write-Host ""
    Read-Host "Press Enter to continue"
}
else {
    # Interactive mode
    Write-MSPLog "═══ Team Knowledge Base ═══" -Level HEADER
    Write-Host ""
    Write-Host "  [V] View all entries" -ForegroundColor Cyan
    Write-Host "  [A] Add new entry" -ForegroundColor Cyan
    Write-Host "  [S] Search by script ID" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Choice: " -NoNewline -ForegroundColor Yellow
    $choice = Read-Host

    switch -Regex ($choice) {
        '^[Vv]$' {
            & $PSCommandPath -ViewAll
        }
        '^[Aa]$' {
            & $PSCommandPath -AddNote
        }
        '^[Ss]$' {
            Write-Host "  Script ID: " -NoNewline -ForegroundColor Yellow
            $id = Read-Host
            & $PSCommandPath -ScriptID $id
        }
    }
}
