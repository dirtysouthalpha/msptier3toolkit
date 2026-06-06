BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\Core\MSPToolkit.psd1'
    if (-not (Test-Path $modulePath)) { throw "Module manifest not found at $modulePath" }
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Invoke-MSPPlaybook' {
    It 'short-circuits when overall verify already passes' {
        $pb = [pscustomobject]@{
            name = 'Already-Healthy'
            verify = [pscustomobject]@{ script = '$true' }
            steps = @()
        }
        $r = Invoke-MSPPlaybook -Playbook $pb
        $r.status | Should -Be 'Success'
        $r.data.Skipped | Should -BeTrue
    }

    It 'runs steps until verify passes, then stops' {
        $pb = [pscustomobject]@{
            name = 'Recovers'
            stopOnSuccess = $true
            verify = [pscustomobject]@{ script = "Test-Path '$env:TEMP\msp-pb-marker'" }
            steps = @(
                [pscustomobject]@{ name='step1'; script='throw "fail"'; retry=1 },
                [pscustomobject]@{ name='step2'; script="New-Item -Path '$env:TEMP\msp-pb-marker' -Force | Out-Null" }
            )
        }
        Remove-Item "$env:TEMP\msp-pb-marker" -Force -ErrorAction SilentlyContinue
        $r = Invoke-MSPPlaybook -Playbook $pb
        $r.status | Should -Be 'Success'
        $r.metrics.StepsRun | Should -Be 2
        Remove-Item "$env:TEMP\msp-pb-marker" -Force -ErrorAction SilentlyContinue
    }

    It 'reports failure when no step recovers' {
        $pb = [pscustomobject]@{
            name = 'AllFail'
            stopOnSuccess = $true
            verify = [pscustomobject]@{ script = '$false' }
            steps = @(
                [pscustomobject]@{ name='step1'; script='1' }
            )
        }
        $r = Invoke-MSPPlaybook -Playbook $pb
        $r.status | Should -BeIn 'Failure','Warning'
        $r.data.OverallHealthy | Should -BeFalse
    }
}
