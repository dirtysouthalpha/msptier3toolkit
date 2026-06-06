<#
.SYNOPSIS
    Pester 5 tests for the new Emergency/Security tools.
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\Core\MSPToolkit.psd1'
    if (-not (Test-Path $modulePath)) { throw "Module manifest not found at $modulePath" }
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Reset-LocalAdminPassword' {
    It 'script file exists and is reachable' {
        $scriptPath = Join-Path $PSScriptRoot '..\MSP_Tier3_Toolkit\Security\Reset-LocalAdminPassword.ps1'
        Test-Path $scriptPath | Should -BeTrue
    }
}

Describe 'Get-LAPSPassword' {
    It 'script file exists and is reachable' {
        $scriptPath = Join-Path $PSScriptRoot '..\MSP_Tier3_Toolkit\Security\Get-LAPSPassword.ps1'
        Test-Path $scriptPath | Should -BeTrue
    }
}

Describe 'Unlock-ADAccountAdvanced' {
    It 'script file exists and is reachable' {
        $scriptPath = Join-Path $PSScriptRoot '..\MSP_Tier3_Toolkit\Security\Unlock-ADAccountAdvanced.ps1'
        Test-Path $scriptPath | Should -BeTrue
    }
}

Describe 'Test-BitLockerRecovery' {
    It 'script file exists and is reachable' {
        $scriptPath = Join-Path $PSScriptRoot '..\MSP_Tier3_Toolkit\Security\Test-BitLockerRecovery.ps1'
        Test-Path $scriptPath | Should -BeTrue
    }
}
