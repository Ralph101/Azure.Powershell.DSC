Configuration xADConfig {
    param (
        [Parameter(Mandatory)]
        [String] $domainName,

        [Parameter(Mandatory)]
        [PSCredential]$adminCreds,

        [Parameter(Mandatory)]
        [String]$connectionBroker,
        
        [Parameter(Mandatory)]
        [String]$webAccessServer,

        [String]$externalFqdn,
        
        [Int]$numberOfRdshInstances,
        [String]$sessionHostNamingPrefix,

        [String]$collectionName,

        [String]$collectionDescription,

        [int]$retryCount = 60,
        [int]$retryIntervalSec = 30
    )

    Import-DscResource -ModuleName xActiveDirectory, xNetworking, xStorage, xPendingReboot, xRemoteDesktopSessionHost, xComputerManagement
    Import-DscResource -ModuleName PSDesiredStateConfiguration -ModuleVersion 1.1
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($AdminCreds.UserName)", $AdminCreds.Password)    
    
    $Interface = Get-NetAdapter | Where-Object Name -like "Ethernet*" | Select-Object -First 1
    $InterfaceAlias = $($Interface.Name)

    if ($sessionHostNamingPrefix)
        { 
            $sessionHosts = @( 0..($numberOfRdshInstances-1) | % { "$sessionHostNamingPrefix$_.$domainname"} )
        }
    else
        {
            $sessionHosts = @( $localhost )
        }

    if (-not $collectionName)         { $collectionName = "Desktop Collection" }
    if (-not $collectionDescription)  { $collectionDescription = "A sample RD Session collection up in cloud." }

        
    node localhost {

        LocalConfigurationManager 
        {
            ActionAfterReboot = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }

        xFirewall FirewallRuleWSManHTTPTCPIn 
        {
            Direction = "Inbound"
            Name = "FirewallRule-WSManHTTP-TCP-In"
            #Description = "Inbound rule for CB to allow TCP traffic for configuring GW and RDSH machines during deployment."
            Group = "WinRM"
            Enabled = "True"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = "5985"
            Ensure = "Present"
        }

        xFirewall FirewallRule-WSManHTTPSTCPIn 
        {
            Direction = "Inbound"
            Name = "Firewall-5986-TCP-In"
            #Description = "Inbound rule for CB to allow TCP traffic for configuring GW and RDSH machines during deployment."
            Group = "WinRM"
            Enabled = "True"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = "5986"
            Ensure = "Present"
        }

        WindowsFeature DNS 
        {
            Name = "DNS"
            Ensure = "Present"
        }

        WindowsFeature DNSTools 
        {
            Name = "RSAT-DNS-Server"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]DNS"
        }

        xDNSServerAddress DNSServerAddress 
        {
            Address = "127.0.0.1","8.8.8.8"
            InterfaceAlias = $InterfaceAlias
            AddressFamily = "IPv4"
            DependsOn = "[WindowsFeature]DNS"
        }

        xWaitForDisk Disk2 
        {
            DiskId = 2
            RetryIntervalSec = $retryIntervalSec
            RetryCount = $retryCount
        }

        xDisk NVolume 
        {
            DiskId = 2
            DriveLetter = "N"
            FSFormat = "NTFS"
            FSLabel = "Active Directory Data"
            DependsOn = "[xWaitForDisk]Disk2"
        }

        WindowsFeature ADDSInstall 
        {
            Name = "AD-Domain-Services"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature ADAdminCenter
        {
            Ensure = "Present"
            Name = "RSAT-AD-AdminCenter"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        WindowsFeature ADDSTools 
        {
            Name = "RSAT-ADDS"
            Ensure = "Present"
            IncludeAllSubFeature = $True
        }

        xADDomain FirstADS 
        {
            DomainName = $domainName
            DomainAdministratorCredential = $domainCreds
            SafemodeAdministratorPassword = $domainCreds
            DatabasePath = "N:\NTDS"
            LogPath = "N:\NTDS"
            SysvolPath = "N:\SYSVOL"
            DependsOn = @("[xDisk]NVolume", "[WindowsFeature]ADDSInstall")
        }

        WaitForAll DomainJoinGW
        {
            ResourceName = "[WindowsFeature]RD-Web-Access"
            NodeName = $WebAccessServer
            RetryIntervalSec = 30 
            RetryCount = 120
            
            PsDscRunAsCredential = $domainCreds
        }

        WindowsFeature RSAT-RDS-Tools 
        {
            Name = "RSAT-RDS-Tools"
            Ensure = "Present"
            IncludeAllSubFeature = $True
        }

        WindowsFeature RDS-Licensing {
            Name = "RDS-Licensing"
            Ensure = "Present"
        }

        xRDSessionDeployment Deployment {
            ConnectionBroker = $ConnectionBroker
            WebAccessServer = $WebAccessServer
            SessionHosts = $sessionHosts

            PsDscRunAsCredential = $domainCreds
        }

        xRDServer AddLicenseServer {
            Role = "RDS-Licensing"
            Server = $ConnectionBroker
            DependsOn = "[xRDSessionDeployment]Deployment"

            PsDscRunAsCredential = $domainCreds
        }

        xRDLicenseConfiguration LicenseConfiguration {
            ConnectionBroker = $ConnectionBroker
            LicenseServers = $ConnectionBroker
            LicenseMode = "PerUser"

            DependsOn = "[xRDServer]AddLicenseServer"

            PsDscRunAsCredential = $domainCreds
        }

        xRDServer AddGatewayServer {
            Role = "RDS-Gateway"
            Server = $WebAccessServer
            GatewayExternalFQDN = $WebAccessServer

            DependsOn = "[xRDLicenseConfiguration]LicenseConfiguration"

            PsDscRunAsCredential = $domainCreds
        }

        xRDGatewayConfiguration GatewayConfiguration {
            ConnectionBroker = $ConnectionBroker
            GatewayServer = $WebAccessServer
            ExternalFQDN = $WebAccessServer
            GatewayMode = "Custom"
            LogonMethod = "Password"
            UseCachedCredentials = $True
            BypassLocal = $False

            DependsOn = "[xRDServer]AddGatewayServer"

            PsDscRunAsCredential = $domainCreds
        }

        xRDSessionCollection Collection {
            ConnectionBroker = $ConnectionBroker
            CollectionName = $CollectionName
            CollectionDescription = $collectionDescription
            SessionHosts = $sessionHosts 
            
            DependsOn = "[xRDGatewayConfiguration]GatewayConfiguration"

            PsDscRunAsCredential = $domainCreds
        }
    }
}
Configuration xGateway {
    param(
        [parameter(Mandatory)]
        [string]$domainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$AdminCreds,

        [int]$retryCount = 60,
        [int]$retryIntervalSec = 30
    )

    Import-DscResource -ModuleName xActiveDirectory, xPendingReboot, xComputerManagement, xNetworking
    Import-DscResource -ModuleName PSDesiredStateConfiguration -ModuleVersion 1.1
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($AdminCreds.UserName)", $AdminCreds.Password)    
    
    node localhost {
        
        LocalConfigurationManager 
        {
            ActionAfterReboot = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true        
        }

        WindowsFeature ADPowershell 
        {
            Name = "RSAT-AD-PowerShell"
            Ensure = "Present"
        }

        xWaitForADDomain DscForestWait 
        { 
            DomainName = $domainName 
            DomainUserCredential= $domainCreds
            RetryCount = $RetryCount 
            RetryIntervalSec = $RetryIntervalSec 
            DependsOn = "[WindowsFeature]ADPowershell" 
        }

        xComputer DomainJoinGW
        {
            Name = $env:COMPUTERNAME
            DomainName = $domainName
            Credential = $domainCreds
            DependsOn = "[xWaitForADDomain]DscForestWait" 
        }

        xFirewall FirewallRuleWSManHTTPTCPIn 
        {
            Direction = "Inbound"
            Name = "FirewallRule-WSManHTTP-TCP-In"
            Description = "Inbound rule for CB to allow TCP traffic for configuring GW and RDSH machines during deployment."
            Group = "WinRM"
            Enabled = "True"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = "5985"
            Ensure = "Present"
        }

        xFirewall FirewallRule-WSManHTTPSTCPIn 
        {
            Direction = "Inbound"
            Name = "Firewall-5986-TCP-In"
            Description = "Inbound rule for CB to allow TCP traffic for configuring GW and RDSH machines during deployment."
            Group = "WinRM"
            Enabled = "True"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = "5986"
            Ensure = "Present"
        }

        WindowsFeature RDS-Gateway 
        {
            Ensure = "Present"
            Name = "RDS-Gateway"
        }

        WindowsFeature RDS-Web-Access 
        {
            Ensure = "Present"
            Name = "RDS-Web-Access"
        }
    }
}

Configuration xSessionHost {
    param(
        [parameter(Mandatory)]
        [string]$domainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$AdminCreds,

        [int]$retryCount = 60,
        [int]$retryIntervalSec = 30
    )
    
    Import-DscResource -ModuleName xActiveDirectory, xPendingReboot, xComputerManagement, xNetworking
    Import-DscResource -ModuleName PSDesiredStateConfiguration -ModuleVersion 1.1
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($AdminCreds.UserName)", $AdminCreds.Password)    
    
    node localhost{

        LocalConfigurationManager {
            ActionAfterReboot = 'ContinueConfiguration'
            RebootNodeIfNeeded = $true
            ConfigurationMode = "ApplyOnly"
        }

        WindowsFeature ADPowershell {
            Name = "RSAT-AD-PowerShell"
            Ensure = "Present"
        }   

        xWaitForADDomain DscForestWait {
            DomainName = $domainName
            DomainUserCredential = $domainCreds
            RetryIntervalSec = $retryIntervalSec
            RetryCount = $retryCount
            DependsOn = "[WindowsFeature]ADPowerShell"
        }

        xComputer DomainJoin {
            Name = $env:COMPUTERNAME
            DomainName = $domainName
            Credential = $DomainCreds
            DependsOn = "[xWaitForADDomain]DscForestWait"
        }

        xFirewall FirewallRuleWSManHTTPTCPIn 
        {
            Direction = "Inbound"
            Name = "FirewallRule-WSManHTTP-TCP-In"
            #Description = "Inbound rule for CB to allow TCP traffic for configuring GW and RDSH machines during deployment."
            Group = "WinRM"
            Enabled = "True"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = "5985"
            Ensure = "Present"
        }

        xFirewall FirewallRule-WSManHTTPSTCPIn 
        {
            Direction = "Inbound"
            Name = "Firewall-5986-TCP-In"
            #Description = "Inbound rule for CB to allow TCP traffic for configuring GW and RDSH machines during deployment."
            Group = "WinRM"
            Enabled = "True"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = "5986"
            Ensure = "Present"
        }

        xFirewall FirewallRuleWSManHTTPTCPOut 
        {
            Direction = "Outbound"
            Name = "FirewallRule-WSMan-HTTP-TCP-Out"
            #Description = "Inbound rule for CB to allow TCP traffic for configuring GW and RDSH machines during deployment."
            Group = "WinRM"
            Enabled = "True"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = "5985"
            Ensure = "Present"
        }

        xFirewall FirewallRuleWSCIMHTTPS 
        {
            Direction = "Outbound"
            Name = "FirewallRule-WSMan-HTTPS-TCP-Out"
            #Description = "Inbound rule for CB to allow TCP traffic for configuring GW and RDSH machines during deployment."
            Group = "WinRM"
            Enabled = "True"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = "5986"
            Ensure = "Present"
        }

        WindowsFeature RDS-RD-Server {
            Name = "RDS-RD-Server"
            Ensure = "Present"
        }
    }
}
