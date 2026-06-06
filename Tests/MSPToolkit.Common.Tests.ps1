<#
.SYNOPSIS
    Pester 5 tests for the Common module.
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\Core\MSPToolkit.psd1'
    if (-not (Test-Path $modulePath)) { throw "Module manifest not found at $modulePath" }
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Get-MSPPaths' {
    It 'returns an object with every required directory present' {
        $paths = Get-MSPPaths
        foreach ($name in 'Root','Logs','Reports','Cache','Templates','KnowledgeBase','Backups','Jobs','Inventory') {
            $paths.PSObject.Properties.Name | Should -Contain $name
            Test-Path $paths.$name | Should -BeTrue
        }
    }
}

Describe 'Test-MSPElevation' {
    It 'returns a bool' {
        Test-MSPElevation | Should -BeOfType [bool]
    }
}

Describe 'Invoke-MSPWithRetry' {
    It 'returns the scriptblock value on first success' {
        Invoke-MSPWithRetry -ScriptBlock { 42 } | Should -Be 42
    }
    It 'retries up to MaxAttempts then throws' {
        $script:attempts = 0
        { Invoke-MSPWithRetry -MaxAttempts 3 -InitialDelayMs 1 -ScriptBlock {
            $script:attempts++; throw 'nope'
        } } | Should -Throw
        $script:attempts | Should -Be 3
    }
    It 'recovers if a later attempt succeeds' {
        $script:n = 0
        $r = Invoke-MSPWithRetry -MaxAttempts 5 -InitialDelayMs 1 -ScriptBlock {
            $script:n++; if ($script:n -lt 3) { throw 'wait' } else { 'ok' }
        }
        $r | Should -Be 'ok'
        $script:n | Should -Be 3
    }
}

Describe 'New-MSPResult' {
    It 'fills required fields and stamps timestamp' {
        $r = New-MSPResult -Tool 'Test' -Status 'Success' -Summary 'hello'
        $r.tool | Should -Be 'Test'
        $r.status | Should -Be 'Success'
        $r.summary | Should -Be 'hello'
        $r.schema | Should -Be 'msp-result/v1'
        $r.timestamp | Should -Not -BeNullOrEmpty
        $r.computerName | Should -Be $env:COMPUTERNAME
    }
    It 'rejects invalid status' {
        { New-MSPResult -Tool 'Test' -Status 'Bogus' } | Should -Throw
    }
}

Describe 'Save-MSPResult' {
    It 'writes JSON to disk and returns the path' {
        $r = New-MSPResult -Tool 'PesterTest' -Status 'Success' -Summary 'unit-test'
        $f = Save-MSPResult -Result $r -Subfolder 'PesterTests'
        $f | Should -Not -BeNullOrEmpty
        Test-Path $f | Should -BeTrue
        $loaded = Get-Content $f -Raw | ConvertFrom-Json
        $loaded.tool | Should -Be 'PesterTest'
        Remove-Item $f -Force
    }
}

Describe 'Test-MSPPendingReboot' {
    It 'returns an object with PendingReboot and Reasons' {
        $r = Test-MSPPendingReboot
        $r.PSObject.Properties.Name | Should -Contain 'PendingReboot'
        $r.PSObject.Properties.Name | Should -Contain 'Reasons'
        $r.PendingReboot | Should -BeOfType [bool]
    }
}

Describe 'ConvertTo-MSPSize' {
    It 'formats KB' { ConvertTo-MSPSize 2048      | Should -Be '2.00 KB' }
    It 'formats MB' { ConvertTo-MSPSize 5242880   | Should -Be '5.00 MB' }
    It 'formats GB' { ConvertTo-MSPSize 3221225472 | Should -Be '3.00 GB' }
    It 'leaves small numbers as bytes' { ConvertTo-MSPSize 500 | Should -Be '500 B' }
}
