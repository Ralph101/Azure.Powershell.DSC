Configuration xRDSHMaster {
    param (
        [Parameter(Mandatory)]
        [String] $domainName,

        [Parameter(Mandatory)]
        [PSCredential]$adminCreds,

        [Int]$retryCount=20,
        [Int]$retryIntervalSec=30
    )

    ## Import all the neccesary modules, you can get these modules on GitHub
    Import-DscResource -ModuleName xActiveDirectory, xNetworking, xStorage, xPendingReboot, xRemoteDesktopSessionHost 
    ## Import the domain credentials into the $domainCreds
    $domainCreds = New-Object System.Management.Automation.PSCredential ("$domainName\$($adminCreds.UserName)", $adminCreds.Password)    
    
    Node localhost {
        
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ConfigurationMode = "ApplyOnly"
        }

        WindowsFeature DNS {
            Name = "DNS"
            Ensure = "Present"
        }

        WindowsFeature DNSTools {
            Name = "RSAT-DNS-Server"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]DNS"
        }

        xDNSServerAddress DNSServerAddress {
            Address = "127.0.0.1, 8.8.8.8"
            InterfaceAlias = $InterfaceAlias
            AddressFamily = "IPv4"
            DependsOn = "[WindowsFeature]DNS"
        }

        xWaitForDisk Disk2 {
            DiskId = 2
            RetryIntervalSec = $retryIntervalSec
            RetryCount = $retryCount
        }

        xDisk NVolume {
            DiskId = 2
            DriveLetter = "N"
            FSFormat = "NTFS"
            FSLabel = "Active Directory Data"
            DependsOn = "[xWaitForDisk]Disk2"
        }

        WindowsFeature ADDSInstall {
            Name = "AD-Domain-Services"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]DNS"
        }

        xADDomain FirstADS {
            DomainName = $domainName
            DomainAdministratorCredential = $domainCreds
            SafemodeAdministratorPassword = $domainCreds
            DatabasePath = "N:\NTDS"
            LogPath = "N:\NTDS"
            SysvolPath = "N:\SYSVOL"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        WindowsFeature RDS-Gateway {
            Name = "RDS-Gateway"
            Ensure = "Present"
            DependsOn = "[xADDomain]FirstADS"
        }

        WindowsFeature RDS-Web-Access {
            Name = "RDS-Web-Access"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]RDS-Gateway"
        }

        WindowsFeature RSAT-RDS-Tools {
            Name = "RSAT-RDS-Tools"
            Ensure = "Present"
            IncludeAllSubFeature = $True
        }
    }
}

Configuration xSessionHost {
    param(
        [parameter(Mandatory)]
        [string]$domainName,

        [Parameter(Mandatory)]
        [PSCredential]$adminCreds,

        [int]$retryCount = 20,
        [int]$retryIntervalSec = 30
    )
    ## Import all the neccesary modules, you can get these modules on GitHub
    Import-DscResource -ModuleName xActiveDirectory, xComputerManagement, xNetworking
    ##$securePassword = ConvertTo-SerucreString -AsPlainText $adminPassword -Force;
    ##$domainCreds = New-Object System.Management.Automation.PSCredential($adminUsername, $securePassword);

    ## Import the domain credentials into the $domainCreds
    $domainCreds = New-Object System.Management.Automation.PSCredential ("$domainName\$($adminCreds.UserName)", $adminCreds.Password)
    
    node localhost{

        LocalConfigurationManager {
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
            Credential = $domainCreds
            DependsOn = "[xWaitForADDomain]DscForestWait"
        }

        xFirewall FirewallRuleForGWRDSH {
            Direction = "Inbound"
            Name = "Firewall-GW-RDSH-TCP-In"
            Description = "Inbound rule for CB to allow TCP traffic for configuring GW and RDSH machines during deployment."
            Group = "Connection Broker"
            Enabled = "True"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = "5985"
            Ensure = "Present"
        }

        WindowsFeature RDS-RD-Server {
            Name = "RDS-RD-Server"
            Ensure = "Present"
        }
    }
}
