BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\Core\MSPToolkit.psd1'
    if (-not (Test-Path $modulePath)) { throw "Module manifest not found at $modulePath" }
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Get-MSPConfig' {
    It 'loads config.json and exposes the expected top-level keys' {
        $c = Get-MSPConfig
        $c | Should -Not -BeNullOrEmpty
        foreach ($k in 'version','paths','logging','notifications','rmmIntegration','webInterface','fleet') {
            $c.PSObject.Properties.Name | Should -Contain $k
        }
    }
}

Describe 'Get-MSPSystemInfo' {
    It 'returns the local computer identity' {
        $i = Get-MSPSystemInfo
        $i.ComputerName | Should -Be $env:COMPUTERNAME
    }
}
