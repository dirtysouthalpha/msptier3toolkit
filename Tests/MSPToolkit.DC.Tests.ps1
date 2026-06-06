# MSPToolkit.DC.Tests.ps1
# Pester 5 tests for the Domain Controller operations module

Describe 'MSPToolkit.DC' {

    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..\Core\MSPToolkit.DC.psm1'
        if (Test-Path $modulePath) {
            Import-Module $modulePath -Force
        }
    }

    Context 'Module Loading' {
        It 'Exports expected functions' {
            $cmds = Get-Command -Module MSPToolkit.DC -ErrorAction SilentlyContinue
            $cmds | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-MSPDCList' {
        It 'Returns DC list as array' {
            $dcs = Get-MSPDCList -ErrorAction SilentlyContinue
            if ($dcs) {
                $dcs -is [Array] | Should -Be $true
            }
            # May be empty on non-DC -- that's OK
        }

        It 'Does not throw' {
            { Get-MSPDCList -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'Get-MSPFSMOInventory' {
        It 'Returns array of role objects' {
            $roles = Get-MSPFSMOInventory
            $roles -is [Array] | Should -Be $true
        }

        It 'Each role has expected properties' {
            $roles = Get-MSPFSMOInventory
            if ($roles.Count -gt 0) {
                $roles[0].PSObject.Properties.Name -contains 'Role' | Should -Be $true
                $roles[0].PSObject.Properties.Name -contains 'Holder' | Should -Be $true
                $roles[0].PSObject.Properties.Name -contains 'Reachable' | Should -Be $true
            }
        }

        It 'Does not throw' {
            { Get-MSPFSMOInventory } | Should -Not -Throw
        }
    }

    Context 'Test-MSPPortDC' {
        It 'Returns port status array' {
            $ports = Test-MSPPortDC -ComputerName 'localhost' -TimeoutMs 1000
            $ports -is [Array] | Should -Be $true
        }

        It 'Each port entry has expected properties' {
            $ports = Test-MSPPortDC -ComputerName 'localhost' -TimeoutMs 1000
            if ($ports.Count -gt 0) {
                $ports[0].PSObject.Properties.Name -contains 'Port' | Should -Be $true
                $ports[0].PSObject.Properties.Name -contains 'Service' | Should -Be $true
                $ports[0].PSObject.Properties.Name -contains 'Open' | Should -Be $true
            }
        }
    }

    Context 'Test-MSPLDAPBind' {
        It 'Returns LDAP bind test results' {
            $results = Test-MSPLDAPBind -ComputerName 'localhost' -TimeoutSec 3
            $results -is [Array] | Should -Be $true
        }

        It 'Does not throw' {
            { Test-MSPLDAPBind -ComputerName 'localhost' -TimeoutSec 2 } | Should -Not -Throw
        }
    }

    Context 'Get-MSPPasswordPolicy' {
        It 'Does not throw' {
            { Get-MSPPasswordPolicy } | Should -Not -Throw
        }
    }

    Context 'Get-MSPKRBTGTInfo' {
        It 'Returns KRBTGT info object' {
            $info = Get-MSPKRBTGTInfo
            $info.PSObject.Properties.Name -contains 'Name' | Should -Be $true
            $info.PSObject.Properties.Name -contains 'RotationRecommended' | Should -Be $true
        }

        It 'Does not throw' {
            { Get-MSPKRBTGTInfo } | Should -Not -Throw
        }
    }

    Context 'Get-MSPSiteForDC' {
        It 'Returns site object' {
            $site = Get-MSPSiteForDC -ComputerName $env:COMPUTERNAME
            $site.PSObject.Properties.Name -contains 'Site' | Should -Be $true
            $site.PSObject.Properties.Name -contains 'Reachable' | Should -Be $true
        }

        It 'Does not throw' {
            { Get-MSPSiteForDC -ComputerName $env:COMPUTERNAME } | Should -Not -Throw
        }
    }

    Context 'Invoke-MSPRepAdmin' -Skip:(!(Get-Command repadmin -ErrorAction SilentlyContinue)) {
        It 'Accepts arguments and returns result' {
            # /showrepl is safe, read-only
            $result = Invoke-MSPRepAdmin -Arguments @('/showrepl') -TimeoutSec 15
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name -contains 'Success' | Should -Be $true
            $result.PSObject.Properties.Name -contains 'ExitCode' | Should -Be $true
        }
    }

    Context 'Get-MSPADDatabaseInfo' {
        It 'Does not throw' {
            { Get-MSPADDatabaseInfo -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }
}
