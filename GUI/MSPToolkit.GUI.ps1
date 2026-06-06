<#
.SYNOPSIS
    MSP Toolkit - WPF Desktop GUI (single file).
.DESCRIPTION
    Native-looking Windows desktop app driven by XAML, embedded inline.
    No external dependencies beyond what ships with .NET Framework 4.5+
    (i.e. every Windows since 8.1 -- and downloadable on Win7 SP1).

    Self-aware: if launched on a server without a display, falls back to
    the console catalog automatically. If launched alongside the bundled
    portable file, reads modules from the bundle's extract directory.

.PARAMETER NoSplash
    Skip the splash screen.
.PARAMETER ToolkitRoot
    Override the toolkit root path (used by the portable bundler).

.EXAMPLE
    .\MSPToolkit.GUI.ps1
.EXAMPLE
    .\MSPToolkit.GUI.ps1 -NoSplash
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$NoSplash,
    [string]$ToolkitRoot
)

# -----------------------------------------------------------------------
#  Bootstrap
# -----------------------------------------------------------------------

if (-not $ToolkitRoot) { $ToolkitRoot = Split-Path -Parent $PSScriptRoot }
$modulePath = Join-Path $ToolkitRoot 'Core\MSPToolkit.psd1'
if (-not (Test-Path $modulePath)) {
    [System.Windows.Forms.MessageBox]::Show("Cannot find MSPToolkit module at $modulePath",'MSP Toolkit',0,16) | Out-Null
    return
}

# Headless fallback -- if STA is unavailable or no display, drop to console
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName PresentationCore -ErrorAction Stop
    Add-Type -AssemblyName WindowsBase -ErrorAction Stop
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
}
catch {
    Write-Host "WPF unavailable - falling back to console mode." -ForegroundColor Yellow
    & (Join-Path $ToolkitRoot 'Tools\Start-MSPApi.ps1')
    return
}

Import-Module $modulePath -Force -ErrorAction Stop
Initialize-MSPLogging -ScriptName 'GUI' | Out-Null

# -----------------------------------------------------------------------
#  Tool catalog
# -----------------------------------------------------------------------
$Script:Catalog = @(
    @{ id='triage';     name='Quick Triage Report';    cat='Workstation'; admin=$false; path='MSP_Tier3_Toolkit\Workstation\Get-QuickTriageReport.ps1';      desc='1-page HTML report you can hand to the user.' }
    @{ id='outlook';    name='Reset Outlook Cache';    cat='Workstation'; admin=$false; path='MSP_Tier3_Toolkit\Workstation\Reset-OutlookCache.ps1';         desc='Nuke OST, AutoComplete and cached credentials.' }
    @{ id='search';     name='Repair Windows Search';  cat='Workstation'; admin=$true;  path='MSP_Tier3_Toolkit\Workstation\Repair-WindowsSearch.ps1';       desc='Rebuild the Windows Search index from scratch.' }
    @{ id='netreset';   name='Reset Network Stack';    cat='Network';     admin=$true;  path='MSP_Tier3_Toolkit\Network\Reset-NetworkStack.ps1';             desc='winsock + ip + DNS + ARP + nbtstat full reset.' }
    @{ id='netpath';    name='Test Network Path';      cat='Network';     admin=$false; path='MSP_Tier3_Toolkit\Network\Test-NetworkPath.ps1';               desc='Ping/TCP/DNS/HTTP probe to common targets.' }
    @{ id='mapped';     name='Fix Mapped Drives';      cat='Network';     admin=$false; path='MSP_Tier3_Toolkit\FixMappedDrives.ps1';                       desc='Test + repair mapped drives.' }
    @{ id='reboot';     name='Reboot Pending Check';   cat='Diagnostics'; admin=$false; path='MSP_Tier3_Toolkit\Diagnostics\RebootPendingCheck.ps1';         desc='Multi-signal pending-reboot detection.' }
    @{ id='events';     name='Event Log Alert Summary';cat='Diagnostics'; admin=$false; path='MSP_Tier3_Toolkit\Diagnostics\EventLogAlertSummary.ps1';      desc='Last 24h Errors/Warnings grouped by source.' }
    @{ id='services';   name='Service Audit';          cat='Diagnostics'; admin=$true;  path='MSP_Tier3_Toolkit\Diagnostics\WindowsServiceAudit.ps1';       desc='Auto services that are stopped (+ repair).' }
    @{ id='perf';       name='Performance Baseline';   cat='Diagnostics'; admin=$false; path='MSP_Tier3_Toolkit\Diagnostics\Get-PerformanceBaseline.ps1';   desc='30-second CPU/mem/disk/network sample.' }
    @{ id='logons';     name='Logon Report';           cat='Diagnostics'; admin=$true;  path='MSP_Tier3_Toolkit\Diagnostics\Get-UserLogonReport.ps1';       desc='Recent logons/failures/lockouts.' }
    @{ id='bitlocker';  name='BitLocker Status';       cat='Security';    admin=$false; path='MSP_Tier3_Toolkit\Security\BitLockerStatusCheck.ps1';         desc='Per-volume protection state.' }
    @{ id='av';         name='AV Status';              cat='Security';    admin=$false; path='MSP_Tier3_Toolkit\Security\AVStatusCheck.ps1';                desc='SecurityCenter + Defender state.' }
    @{ id='admins';     name='Local Admin Audit';      cat='Security';    admin=$false; path='MSP_Tier3_Toolkit\Security\LocalAdminAudit.ps1';              desc='Who has local Administrator?' }
    @{ id='patches';    name='Patch Compliance';       cat='Security';    admin=$false; path='MSP_Tier3_Toolkit\Security\Get-PatchCompliance.ps1';          desc='Pending updates + install history.' }
    @{ id='posture';    name='Security Posture Score'; cat='Security';    admin=$true;  path='MSP_Tier3_Toolkit\Security\Get-SecurityPostureScore.ps1';     desc='12-check 0-100 hardening score.' }
    @{ id='laps';       name='LAPS Password Check';    cat='Security';    admin=$false; path='MSP_Tier3_Toolkit\Security\Test-LAPSDeployment.ps1';         desc='LAPS deployment health and password age.' }
    @{ id='getlaps';    name='LAPS Password Retrieve'; cat='Emergency';    admin=$false; path='MSP_Tier3_Toolkit\Security\Get-LAPSPassword.ps1';            desc='Retrieve LAPS-managed local admin password from AD.' }
    @{ id='unlockadv';  name='Advanced AD Unlock';     cat='Emergency';    admin=$false; path='MSP_Tier3_Toolkit\Security\Unlock-ADAccountAdvanced.ps1';    desc='Unlock, reset password, clear badPwdCount, and force change on next logon.' }
    @{ id='resetadmin'; name='Reset Local Admin';      cat='Emergency';    admin=$true;  path='MSP_Tier3_Toolkit\Security\Reset-LocalAdminPassword.ps1';   desc='Reset built-in Administrator password (generates random if omitted).' }
    @{ id='bitlockerkey';name='BitLocker Recovery Key';cat='Emergency';    admin=$false; path='MSP_Tier3_Toolkit\Security\Test-BitLockerRecovery.ps1';     desc='Verify BitLocker recovery keys escrowed to AD/Azure AD.' }
    @{ id='cleanup';    name='Temp Cleanup';           cat='Maintenance'; admin=$true;  path='MSP_Tier3_Toolkit\Maintenance\ScheduledTempCleanup.ps1';      desc='Safe temp-folder cleanup with -WhatIf.' }
    @{ id='bloat';      name='OEM Bloatware Remover';  cat='Maintenance'; admin=$true;  path='MSP_Tier3_Toolkit\Maintenance\OEMBloatwareRemover.ps1';       desc='Remove Candy Crush, etc. (installed + provisioned).' }
    @{ id='profiles';   name='Cleanup Old Profiles';   cat='Maintenance'; admin=$true;  path='MSP_Tier3_Toolkit\CleanupOldProfiles.ps1';                    desc='SID-safe stale-profile removal.' }
    @{ id='wufix';      name='Windows Update Fix';     cat='Maintenance'; admin=$true;  path='MSP_Tier3_Toolkit\WindowsUpdateFix.ps1';                      desc='Reset WU components with backup.' }
    @{ id='spooler';    name='Printer Spooler Fix';    cat='Maintenance'; admin=$true;  path='MSP_Tier3_Toolkit\PrinterSpoolerFix.ps1';                     desc='Spooler restart + clear stuck jobs.' }
    @{ id='onedrive';   name='OneDrive Sync Health';   cat='M365';        admin=$false; path='MSP_Tier3_Toolkit\M365\OneDriveSyncHealthCheck.ps1';          desc='KFM coverage + last error per account.' }
    @{ id='inventory';  name='Asset Inventory Export'; cat='Inventory';   admin=$false; path='MSP_Tier3_Toolkit\Inventory\Export-AssetInventory.ps1';      desc='Full PSA-ready hardware+software dump.' }
)

# -----------------------------------------------------------------------
#  XAML
# -----------------------------------------------------------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MSP Toolkit Console" Height="780" Width="1280"
        WindowStartupLocation="CenterScreen" Background="#0E1322">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#5B6CFA"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border CornerRadius="5" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="#EAEEFA"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>
    <Style x:Key="Header" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#7D89B3"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="10,12,0,4"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="56"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="22"/>
    </Grid.RowDefinitions>

    <!-- Top bar -->
    <Border Grid.Row="0" Background="#181F36" BorderBrush="#293252" BorderThickness="0,0,0,1">
      <Grid Margin="20,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
          <Ellipse Width="10" Height="10" Fill="#5B6CFA" Margin="0,0,10,0"/>
          <TextBlock Text="MSP Toolkit" FontSize="18" FontWeight="Bold"/>
          <TextBlock Text="v4.0" Margin="8,4,0,0" Foreground="#7D89B3" FontSize="11"/>
        </StackPanel>
        <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Name="HostLabel" Text="" Foreground="#7D89B3" Margin="0,0,16,0"/>
          <Button Name="OpenReportsBtn"  Content="Open Reports"  Background="#222A47" Margin="0,0,8,0"/>
          <Button Name="StartApiBtn"     Content="Start REST API"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- Main layout -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="280"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- Sidebar -->
      <Border Grid.Column="0" Background="#181F36" BorderBrush="#293252" BorderThickness="0,0,1,0">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Name="ToolList"/>
        </ScrollViewer>
      </Border>

      <!-- Main panel -->
      <Grid Grid.Column="1" Margin="24">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Live metrics -->
        <UniformGrid Grid.Row="0" Columns="6" Rows="1" Height="80" Margin="0,0,0,20">
          <Border Background="#181F36" CornerRadius="8" Margin="0,0,8,0">
            <StackPanel Margin="14,12" VerticalAlignment="Center">
              <TextBlock Text="CPU" Foreground="#7D89B3" FontSize="10"/>
              <TextBlock Name="CpuMetric" Text="--%" FontSize="22" FontWeight="SemiBold"/>
            </StackPanel>
          </Border>
          <Border Background="#181F36" CornerRadius="8" Margin="0,0,8,0">
            <StackPanel Margin="14,12" VerticalAlignment="Center">
              <TextBlock Text="MEMORY" Foreground="#7D89B3" FontSize="10"/>
              <TextBlock Name="MemMetric" Text="--%" FontSize="22" FontWeight="SemiBold"/>
            </StackPanel>
          </Border>
          <Border Background="#181F36" CornerRadius="8" Margin="0,0,8,0">
            <StackPanel Margin="14,12" VerticalAlignment="Center">
              <TextBlock Text="DISK C:" Foreground="#7D89B3" FontSize="10"/>
              <TextBlock Name="DiskMetric" Text="--" FontSize="22" FontWeight="SemiBold"/>
            </StackPanel>
          </Border>
          <Border Background="#181F36" CornerRadius="8" Margin="0,0,8,0">
            <StackPanel Margin="14,12" VerticalAlignment="Center">
              <TextBlock Text="UPTIME" Foreground="#7D89B3" FontSize="10"/>
              <TextBlock Name="UptimeMetric" Text="-- h" FontSize="22" FontWeight="SemiBold"/>
            </StackPanel>
          </Border>
          <Border Background="#181F36" CornerRadius="8" Margin="0,0,8,0">
            <StackPanel Margin="14,12" VerticalAlignment="Center">
              <TextBlock Text="REBOOT" Foreground="#7D89B3" FontSize="10"/>
              <TextBlock Name="RebootMetric" Text="--" FontSize="22" FontWeight="SemiBold"/>
            </StackPanel>
          </Border>
          <Border Background="#181F36" CornerRadius="8">
            <StackPanel Margin="14,12" VerticalAlignment="Center">
              <TextBlock Text="ADMIN" Foreground="#7D89B3" FontSize="10"/>
              <TextBlock Name="AdminMetric" Text="--" FontSize="22" FontWeight="SemiBold"/>
            </StackPanel>
          </Border>
        </UniformGrid>

        <!-- Selected tool header + Run button -->
        <Border Grid.Row="1" Background="#181F36" CornerRadius="8" Padding="20" Margin="0,0,0,16">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Grid Grid.Row="0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0">
                <TextBlock Name="ToolName" Text="Select a tool" FontSize="18" FontWeight="SemiBold"/>
                <TextBlock Name="ToolDesc" Text="Pick something from the sidebar." Foreground="#7D89B3" Margin="0,4,0,0"/>
              </StackPanel>
              <StackPanel Grid.Column="1" Orientation="Horizontal">
                <Button Name="RunBtn"     Content="Run" IsEnabled="False" Margin="0,0,8,0"/>
                <Button Name="ExportBtn"  Content="Export JSON" IsEnabled="False" Background="#222A47" Margin="0,0,8,0"/>
                <Button Name="CopyBtn"    Content="Copy"        IsEnabled="False" Background="#222A47"/>
              </StackPanel>
            </Grid>
            <TextBlock Grid.Row="1" Name="ToolFlags" Margin="0,12,0,0" Foreground="#E8A93B"/>
            <ProgressBar Grid.Row="2" Name="ToolProgress" IsIndeterminate="True" Visibility="Collapsed"
                         Height="3" Margin="0,12,0,0" Background="Transparent" Foreground="#5B6CFA"/>
          </Grid>
        </Border>

        <!-- Output -->
        <Border Grid.Row="2" Background="#0E1322" BorderBrush="#293252" BorderThickness="1" CornerRadius="8">
          <ScrollViewer VerticalScrollBarVisibility="Auto">
            <TextBox Name="OutputBox" Background="Transparent" Foreground="#EAEEFA"
                     BorderThickness="0" FontFamily="Consolas" FontSize="12"
                     IsReadOnly="True" TextWrapping="Wrap" Padding="14"
                     Text="No tool run yet."/>
          </ScrollViewer>
        </Border>
      </Grid>
    </Grid>

    <!-- Status bar -->
    <Border Grid.Row="2" Background="#181F36" BorderBrush="#293252" BorderThickness="0,1,0,0">
      <DockPanel Margin="20,0">
        <TextBlock Name="StatusText" Text="Ready" Foreground="#7D89B3" VerticalAlignment="Center"/>
        <TextBlock Name="SessionText" Text="" Foreground="#7D89B3" VerticalAlignment="Center" HorizontalAlignment="Right"/>
      </DockPanel>
    </Border>
  </Grid>
</Window>
'@

# -----------------------------------------------------------------------
#  Wire up
# -----------------------------------------------------------------------
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$ctl = @{}
'HostLabel','OpenReportsBtn','StartApiBtn','ToolList','CpuMetric','MemMetric','DiskMetric',
'UptimeMetric','RebootMetric','AdminMetric','ToolName','ToolDesc','ToolFlags','RunBtn',
'ExportBtn','CopyBtn','OutputBox','StatusText','SessionText','ToolProgress' |
    ForEach-Object { $ctl[$_] = $window.FindName($_) }

$ctl.HostLabel.Text = "$env:COMPUTERNAME \ $env:USERNAME"
$ctl.SessionText.Text = "Session $(Get-MSPSessionId)"

# Build sidebar
$grouped = $Script:Catalog | Group-Object { $_.cat }
foreach ($g in ($grouped | Sort-Object Name)) {
    $hdr = New-Object Windows.Controls.TextBlock
    $hdr.Text = $g.Name.ToUpper()
    $hdr.Style = $window.FindResource('Header')
    [void]$ctl.ToolList.Children.Add($hdr)

    foreach ($t in $g.Group) {
        $btn = New-Object Windows.Controls.Button
        $btn.Content = $t.name
        $btn.HorizontalContentAlignment = 'Left'
        $btn.Background = [System.Windows.Media.Brushes]::Transparent
        $btn.BorderThickness = '0'
        $btn.Padding = '14,8'
        $btn.Margin = '6,1'
        $btn.Tag = $t
        $btn.Add_Click({
            $tool = $this.Tag
            $ctl.ToolName.Text = $tool.name
            $ctl.ToolDesc.Text = $tool.desc
            $ctl.ToolFlags.Text = if ($tool.admin -and -not (Test-MSPElevation)) {
                '* Requires Administrator. Re-launch as admin or this will likely fail.'
            } else { '' }
            $ctl.RunBtn.IsEnabled = $true
            $ctl.RunBtn.Tag = $tool
            $ctl.StatusText.Text = "Selected: $($tool.name)"
        })
        [void]$ctl.ToolList.Children.Add($btn)
    }
}

# -----------------------------------------------------------------------
#  Live metrics timer
# -----------------------------------------------------------------------
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(5)
$Script:CpuSamples = @()
$timer.Add_Tick({
    try {
        $cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        if ($null -ne $cpu) { $ctl.CpuMetric.Text = "$([math]::Round($cpu))%" }

        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $memPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100)
            $ctl.MemMetric.Text = "$memPct%"
            $ctl.UptimeMetric.Text = "$([math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours,0)) h"
        }
        $c = Get-PSDrive C -ErrorAction SilentlyContinue
        if ($c) { $ctl.DiskMetric.Text = "$([math]::Round($c.Free / 1GB)) GB" }

        $ctl.RebootMetric.Text = if ((Test-MSPPendingReboot).PendingReboot) { 'YES' } else { 'No' }
        $ctl.AdminMetric.Text  = if (Test-MSPElevation) { 'Yes' } else { 'No' }
    } catch { }
})
$timer.Start()

# -----------------------------------------------------------------------
#  Run / Export / Copy
# -----------------------------------------------------------------------
$Script:LastResult = $null
$Script:LastResultJson = ''

$ctl.RunBtn.Add_Click({
    $tool = $this.Tag
    if (-not $tool) { return }

    $scriptPath = Join-Path $ToolkitRoot $tool.path
    if (-not (Test-Path $scriptPath)) {
        $ctl.OutputBox.Text = "Script not found: $scriptPath"
        return
    }

    $ctl.RunBtn.IsEnabled = $false
    $ctl.ExportBtn.IsEnabled = $false
    $ctl.CopyBtn.IsEnabled = $false
    $ctl.ToolProgress.Visibility = 'Visible'
    $ctl.OutputBox.Text = "Running $($tool.name)..."
    $ctl.StatusText.Text = "Running $($tool.name)..."

    # Background runspace
    $ps = [powershell]::Create()
    [void]$ps.AddScript({
        param($modulePath, $scriptPath)
        Import-Module $modulePath -Force -ErrorAction SilentlyContinue
        & $scriptPath
    })
    [void]$ps.AddArgument($modulePath)
    [void]$ps.AddArgument($scriptPath)

    $handle = $ps.BeginInvoke()

    # Poll for completion via dispatcher timer
    $poll = New-Object System.Windows.Threading.DispatcherTimer
    $poll.Interval = [TimeSpan]::FromMilliseconds(300)
    $poll.Tag = @{ Ps=$ps; Handle=$handle; Tool=$tool }
    $poll.Add_Tick({
        $h = $this.Tag.Handle
        if (-not $h.IsCompleted) { return }
        $this.Stop()
        try {
            $output = $this.Tag.Ps.EndInvoke($h)
            $result = $output | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'schema' } | Select-Object -Last 1
            if (-not $result) { $result = $output | Select-Object -Last 1 }
            $Script:LastResult = $result
            $Script:LastResultJson = $result | ConvertTo-Json -Depth 10
            $ctl.OutputBox.Text = $Script:LastResultJson
            $statusWord = if ($result.PSObject.Properties.Name -contains 'status') { $result.status } else { 'Done' }
            $ctl.StatusText.Text = "$($this.Tag.Tool.name): $statusWord"
        } catch {
            $ctl.OutputBox.Text = "ERROR: $($_.Exception.Message)"
            $ctl.StatusText.Text = "$($this.Tag.Tool.name): error"
        } finally {
            $this.Tag.Ps.Dispose()
            $ctl.RunBtn.IsEnabled = $true
            $ctl.ExportBtn.IsEnabled = $true
            $ctl.CopyBtn.IsEnabled = $true
            $ctl.ToolProgress.Visibility = 'Collapsed'
        }
    })
    $poll.Start()
})

$ctl.ExportBtn.Add_Click({
    if (-not $Script:LastResultJson) { return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'JSON file (*.json)|*.json|All files (*.*)|*.*'
    $dlg.FileName = "result_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    if ($dlg.ShowDialog() -eq $true) {
        $Script:LastResultJson | Set-Content -LiteralPath $dlg.FileName -Encoding UTF8
        $ctl.StatusText.Text = "Saved to $($dlg.FileName)"
    }
})

$ctl.CopyBtn.Add_Click({
    if ($Script:LastResultJson) {
        [System.Windows.Clipboard]::SetText($Script:LastResultJson)
        $ctl.StatusText.Text = 'Result copied to clipboard.'
    }
})

$ctl.OpenReportsBtn.Add_Click({
    $paths = Get-MSPPaths
    Start-Process explorer.exe $paths.Reports
})

$ctl.StartApiBtn.Add_Click({
    $apiScript = Join-Path $ToolkitRoot 'Tools\Start-MSPApi.ps1'
    Start-Process powershell.exe -ArgumentList "-NoExit","-ExecutionPolicy","Bypass","-File","`"$apiScript`"","-OpenBrowser"
    $ctl.StatusText.Text = 'API launched in new window.'
})

$window.Add_Closed({
    $timer.Stop()
})

# -----------------------------------------------------------------------
#  Splash
# -----------------------------------------------------------------------
if (-not $NoSplash) {
    $splashXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Width="420" Height="220" WindowStartupLocation="CenterScreen" Topmost="True">
  <Border Background="#181F36" CornerRadius="14" BorderBrush="#5B6CFA" BorderThickness="1">
    <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
      <Ellipse Width="48" Height="48" Fill="#5B6CFA" Margin="0,0,0,16"/>
      <TextBlock Text="MSP Toolkit" Foreground="White" FontSize="28" FontWeight="Bold" HorizontalAlignment="Center"/>
      <TextBlock Text="v4.0 - Loading..." Foreground="#7D89B3" Margin="0,4,0,0" HorizontalAlignment="Center"/>
    </StackPanel>
  </Border>
</Window>
'@
    $splash = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$splashXaml)))
    $splash.Show()
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{ Start-Sleep -Milliseconds 600 }, 'Background')
    $splash.Close()
}

# Trigger first metrics tick before showing
$timer.Add_Tick.Invoke($null, $null) 2>$null

# Show
[void]$window.ShowDialog()
