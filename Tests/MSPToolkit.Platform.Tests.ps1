# MSPToolkit.Platform.Tests.ps1
# Pester 5 tests for the cross-platform module

Describe 'MSPToolkit.Platform' {

    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..\Core\MSPToolkit.Platform.psm1'
        if (Test-Path $modulePath) {
            Import-Module $modulePath -Force
        }
    }

    Context 'Get-MSPPlatform' {
        It 'Returns a platform object with expected properties' {
            $plat = Get-MSPPlatform
            $plat | Should -Not -BeNullOrEmpty
            $plat.PSObject.Properties.Name -contains 'Platform' | Should -Be $true
            $plat.PSObject.Properties.Name -contains 'Version' | Should -Be $true
            $plat.PSObject.Properties.Name -contains 'IsWindows' | Should -Be $true
            $plat.PSObject.Properties.Name -contains 'IsMacOS' | Should -Be $true
            $plat.PSObject.Properties.Name -contains 'IsLinux' | Should -Be $true
        }

        It 'Reports exactly one platform as true' {
            $plat = Get-MSPPlatform
            $trueCount = @($plat.IsWindows, $plat.IsMacOS, $plat.IsLinux | Where-Object { $_ }).Count
            $trueCount | Should -BeExactly 1
        }

        It 'Platform string is one of the known values' {
            $plat = Get-MSPPlatform
            $plat.Platform | Should -BeIn @('Windows','macOS','Linux')
        }
    }

    Context 'Test-MSPElevation' {
        It 'Returns a boolean' {
            $result = Test-MSPElevation
            $result -is [bool] | Should -Be $true
        }

        It 'Does not throw' {
            { Test-MSPElevation } | Should -Not -Throw
        }
    }

    Context 'Test-MSPPendingReboot' {
        It 'Returns object with PendingReboot boolean' {
            $reboot = Test-MSPPendingReboot
            $reboot.PendingReboot -is [bool] | Should -Be $true
        }

        It 'Returns object with Reasons array' {
            $reboot = Test-MSPPendingReboot
            $reboot.Reasons -is [Array] | Should -Be $true
        }

        It 'Does not throw on any platform' {
            { Test-MSPPendingReboot } | Should -Not -Throw
        }
    }

    Context 'Get-MSPPlatformFacts' {
        It 'Returns facts with expected properties' {
            $facts = Get-MSPPlatformFacts
            $facts | Should -Not -BeNullOrEmpty
            $facts.PSObject.Properties.Name -contains 'Platform' | Should -Be $true
            $facts.PSObject.Properties.Name -contains 'ComputerName' | Should -Be $true
            $facts.PSObject.Properties.Name -contains 'IsElevated' | Should -Be $true
        }

        It 'ComputerName is not empty' {
            $facts = Get-MSPPlatformFacts
            [string]::IsNullOrWhiteSpace($facts.ComputerName) | Should -Be $false
        }

        It 'Caches results unless -Refresh is used' {
            $a = Get-MSPPlatformFacts
            $b = Get-MSPPlatformFacts
            $a.ToString() | Should -BeExactly $b.ToString()
            $c = Get-MSPPlatformFacts -Refresh
            $c | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-MSPDiskInfo' {
        It 'Returns array of disk objects' {
            $disks = Get-MSPDiskInfo
            $disks -is [Array] | Should -Be $true
        }

        It 'Does not throw' {
            { Get-MSPDiskInfo } | Should -Not -Throw
        }
    }

    Context 'ConvertTo-MSPPlatformPath' {
        It 'Normalizes path slashes' {
            $path = ConvertTo-MSPPlatformPath -Path 'foo/bar\baz.txt'
            $path | Should -Not -BeNullOrEmpty
            # Should not contain mixed slashes
            $hasMixed = ($path -match '/' -and $path -match '\\')
            $hasMixed | Should -Be $false
        }
    }

    Context 'Invoke-MSPNativeCommand' {
        It 'Can run a simple command' {
            if (Get-MSPPlatform | Where-Object IsWindows) {
                $result = Invoke-MSPNativeCommand -Command 'cmd.exe' -Arguments @('/c','echo','hello') -TimeoutSec 5
                $result | Should -Match 'hello'
            } else {
                $result = Invoke-MSPNativeCommand -Command 'echo' -Arguments @('hello') -TimeoutSec 5
                $result | Should -Match 'hello'
            }
        }

        It 'Throws on missing command' {
            { Invoke-MSPNativeCommand -Command 'nonexistent_command_xyz_12345' -Arguments @() -TimeoutSec 2 } | Should -Throw
        }
    }

    Context 'Get-MSPNetworkInfo' {
        It 'Returns array' {
            $net = Get-MSPNetworkInfo
            $net -is [Array] | Should -Be $true
        }

        It 'Does not throw' {
            { Get-MSPNetworkInfo } | Should -Not -Throw
        }
    }

    Context 'Get-MSPSecurityStatus' {
        It 'Returns security status object' {
            $sec = Get-MSPSecurityStatus
            $sec.PSObject.Properties.Name -contains 'FirewallEnabled' | Should -Be $true
            $sec.PSObject.Properties.Name -contains 'EncryptionEnabled' | Should -Be $true
            $sec.PSObject.Properties.Name -contains 'AVStatus' | Should -Be $true
        }
    }

    Context 'Get-MSPPlatformUsers' {
        It 'Returns users array' {
            $users = Get-MSPPlatformUsers
            $users -is [Array] | Should -Be $true
        }

        It 'Does not throw' {
            { Get-MSPPlatformUsers } | Should -Not -Throw
        }
    }
}
