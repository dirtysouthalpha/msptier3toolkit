@{
    RootModule        = 'MSPToolkit.psm1'
    ModuleVersion     = '25.0.0'
    GUID              = 'd5b1a0e2-9c5e-4f3d-8b8e-2b1f0a1f3c0a'
    Author            = 'Sentinel Recon contributors'
    CompanyName       = 'Sentinel'
    Copyright         = '(c) Sentinel Recon contributors'
    Description       = 'Sentinel Recon -- Cross-platform MSP diagnostics & automation platform. Discover. Diagnose. Deploy.'
    PowerShellVersion = '5.1'
    NestedModules     = @(
        'MSPToolkit.Config.psm1',
        'MSPToolkit.Logging.psm1',
        'MSPToolkit.Common.psm1',
        'MSPToolkit.Remote.psm1',
        'MSPToolkit.Fleet.psm1',
        'MSPToolkit.Playbook.psm1',
        'MSPToolkit.Tenant.psm1',
        'MSPToolkit.Audit.psm1',
        'MSPToolkit.Platform.psm1',
        'MSPToolkit.DC.psm1',
        'MSPToolkit.Orchestrator.psm1',
        'MSPToolkit.Reporting.psm1',
        'MSPToolkit.Webhooks.psm1',
        '..\Integrations\MSPToolkit.Notifications.psm1',
        '..\Integrations\MSPToolkit.Graph.psm1',
        '..\Integrations\MSPToolkit.PSA.psm1',
        '..\Integrations\MSPToolkit.RMM.psm1'
    )
    FunctionsToExport = @(
        # Config
        'Get-MSPConfig','Set-MSPConfigValue','Initialize-MSPDirectories',
        'Test-MSPAdminRights','Get-MSPSystemInfo',
        # Logging
        'Initialize-MSPLogging','Write-MSPLog','Write-MSPProgress',
        'Show-MSPBanner','Show-MSPSuccess','Show-MSPError','Show-MSPBox','Write-MSPTable',
        # Common
        'Test-MSPElevation','Assert-MSPElevation','Get-MSPPaths',
        'Invoke-MSPWithRetry','New-MSPResult','Save-MSPResult',
        'Get-MSPOSFacts','Test-MSPPendingReboot','ConvertTo-MSPSize','Get-MSPSessionId',
        # Remote
        'Invoke-MSPRemoteScript','Invoke-MSPRemoteScriptFile',
        'Get-MSPRemoteComputerStatus','Import-MSPComputerList',
        'New-MSPCredential','Get-MSPCredential',
        # Fleet
        'Invoke-MSPFleet',
        # Playbooks
        'Invoke-MSPPlaybook',
        # Tenants
        'Set-MSPTenant','Get-MSPTenant','Remove-MSPTenant',
        'Select-MSPTenant','Get-MSPCurrentTenant','Invoke-MSPAcross',
        # Platform
        'Get-MSPPlatform','Test-MSPElevation','Get-MSPPlatformFacts','Get-MSPDiskInfo',
        'Get-MSPNetworkInfo','Get-MSPSecurityStatus','Test-MSPPendingReboot',
        'Invoke-MSPNativeCommand','ConvertTo-MSPPlatformPath','Get-MSPPlatformUsers',
        # DC Operations
        'Get-MSPDCList','Get-MSPSiteForDC','Get-MSPFSMOInventory','Invoke-MSPRepAdmin',
        'Test-MSPPortDC','Get-MSPADDatabaseInfo','Get-MSPPasswordPolicy','Test-MSPLDAPBind','Get-MSPKRBTGTInfo',
        # Audit
        'Write-MSPAudit','Test-MSPAuditChain',
        # Notifications
        'Send-MSPTeamsMessage','Send-MSPSlackMessage','Send-MSPDiscordMessage',
        'Send-MSPEmail','Send-MSPNotification',
        # Graph
        'Set-MSPGraphCredential','Get-MSPGraphCredential',
        'Connect-MSPGraph','Invoke-MSPGraph',
        'Get-MSPGraphUser','Get-MSPGraphLicenseSummary',
        'Reset-MSPGraphUserPassword','Set-MSPGraphUserAccountState','Get-MSPGraphSignInRisk',
        # PSA
        'New-MSPTicket',
        # RMM
        'Sync-MSPNinjaOneDevice','New-MSPNinjaOneTicket',
        'Sync-MSPConnectWiseConfig','New-MSPConnectWiseTicket',
        'New-MSPDattoComponent','New-MSPAutotaskTicket',
        'Invoke-MSPDiagnosticToTicket','Sync-MSPBulkDeviceDiagnostics',
        # Orchestrator
        'New-MSPWorkflow','Invoke-MSPWorkflow','Get-MSPWorkflowStatus',
        'Set-MSPMaintenanceWindow','Test-MSPMaintenanceWindow',
        'New-MSPChangeRequest','Approve-MSPChangeRequest','Get-MSPChangeHistory',
        'Stop-MSPWorkflow','Resume-MSPWorkflow',
        # Reporting
        'New-MSPDashboard','Get-MSPSLAMetrics','Invoke-MSPCostOptimizer',
        'New-MSPComplianceReport','Export-MSPReport',
        'Get-MSPTenantScorecard','Get-MSPUtilizationTrend',
        # Webhooks
        'Register-MSPPlugin','Get-MSPPluginCatalog','New-MSPCustomTool',
        'Publish-MSPPlugin','New-MSPOpenApiSpec','Register-MSPWebhook',
        'Invoke-MSPWebhook','Get-MSPWebhookHistory',
        'Save-MSPWebhookState','Restore-MSPWebhookState','Save-MSPPluginState',
        'Save-MSPOrchestratorState','Restore-MSPOrchestratorState'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('Sentinel','Recon','MSP','Tier3','Helpdesk','Automation','Diagnostics','Windows','macOS','Linux','M365','ActiveDirectory','DC','RMM','PSA','Cross-Platform','Orchestration','Reporting','Webhooks','Backup','Cloud','Docker','Containers')
            ProjectUri   = 'https://github.com/dirtysouthalpha/sentinel-recon'
            LicenseUri   = 'https://github.com/dirtysouthalpha/sentinel-recon/blob/main/LICENSE'
            ReleaseNotes = 'v25.0.0 -- Sentinel Recon rebrand. Linux support, persistence layer, 11 playbooks, Docker/container health, multi-platform parity.'
        }
    }
}
