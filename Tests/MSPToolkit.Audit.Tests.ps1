BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\Core\MSPToolkit.psd1'
    if (-not (Test-Path $modulePath)) { throw "Module manifest not found at $modulePath" }
    Import-Module $modulePath -Force -ErrorAction Stop
    $paths = Get-MSPPaths
    $script:auditPath = Join-Path $paths.Logs 'audit.jsonl'
    if (Test-Path $script:auditPath) { Remove-Item $script:auditPath -Force }
}

Describe 'Write-MSPAudit + Test-MSPAuditChain' {
    It 'writes entries and the chain verifies clean' {
        Write-MSPAudit -Action 'TestAction1' -Subject 'subject-a' -Detail @{ a = 1 }
        Write-MSPAudit -Action 'TestAction2' -Subject 'subject-b' -Detail @{ a = 2 }
        Write-MSPAudit -Action 'TestAction3' -Subject 'subject-c' -Detail @{ a = 3 }

        $v = Test-MSPAuditChain
        $v.Ok | Should -BeTrue
        $v.Entries | Should -BeGreaterOrEqual 3
    }

    It 'detects tampering in the middle of the chain' {
        # Tamper: rewrite the second line's subject
        $lines = Get-Content $script:auditPath
        $obj = $lines[1] | ConvertFrom-Json
        $obj.subject = 'TAMPERED'
        $lines[1] = ($obj | ConvertTo-Json -Compress)
        Set-Content -LiteralPath $script:auditPath -Value $lines -Encoding UTF8

        $v = Test-MSPAuditChain
        $v.Ok | Should -BeFalse
        $v.FirstBadIndex | Should -Be 2
    }
}

AfterAll {
    if ($script:auditPath -and (Test-Path $script:auditPath)) { Remove-Item $script:auditPath -Force }
}
