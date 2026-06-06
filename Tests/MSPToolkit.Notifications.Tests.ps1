BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\Core\MSPToolkit.psd1'
    if (-not (Test-Path $modulePath)) { throw "Module manifest not found at $modulePath" }
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Send-MSPTeamsMessage' {
    It 'builds a MessageCard payload and POSTs it' {
        InModuleScope MSPToolkit.Notifications {
            Mock Invoke-RestMethod { return $true }
            { Send-MSPTeamsMessage -WebhookUrl 'https://example.invalid/teams' -Title 't' -Text 'b' -Theme good } | Should -Not -Throw
            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
                $Uri -eq 'https://example.invalid/teams' -and $Method -eq 'Post'
            }
        }
    }
}

Describe 'Send-MSPSlackMessage' {
    It 'POSTs an attachment payload' {
        InModuleScope MSPToolkit.Notifications {
            Mock Invoke-RestMethod { return $true }
            { Send-MSPSlackMessage -WebhookUrl 'https://example.invalid/slack' -Title 't' -Text 'b' } | Should -Not -Throw
            Should -Invoke Invoke-RestMethod -Times 1
        }
    }
}
