Configuration xConfig {
    param (
        [Parameter(Mandatory)][String] $DomainName,
        [Parameter(Mandatory)][PSCredential] $AdminCreds,
        [Parameter(Mandatory)][String] $ConnectionBroker,
        [Parameter(Mandatory)][String] $WebAccessServer,
        [Parameter(Mandatory)][Int] $NumberOfRdshInstances,
        [Parameter(Mandatory)][String] $SessionHostNamingPrefix,
        [String] $CollectionName,
        [String] $CollectionDescription,
        [Int] $RetryCount = 60,
        [Int] $RetryIntervalSec = 30
    )

    Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName xNetworking
    Import-DscResource -ModuleName xStorage
    Import-DscResource -ModuleName xRemoteDesktopSessionHost
    Import-DscResource -ModuleName xComputerManagement

    $DomainCreds = New-Object System.Management.Automation.PSCredential ("$DomainName\$($AdminCreds.UserName)", $adminCreds.Password)

    $Interface = Get-NetAdapter | Where-Object Name -like "Ethernet*" | Select-Object -First 1
    $InterfaceAlias = $($Interface.Name)

    if ($SessionHostNamingPrefix) {$SessionHosts = @(0..($NumberOfRdshInstances -1) | ForEach-Object {"$SessionHostNamingPrefix$_.$DomainName"})}
    $LastRdshHost = $SessionHostNamingPrefix+($NumberOfRdshInstances-1) ##Catches the latest RDSH so we can check if the RDSH Role is installed on it

    #if (!$CollectionName) {$CollectionName = "Desktop Collection"}
    #if (!$CollectionDescription) {$CollectionDescription = "A Sample RD Session collection up in cloud."}

        node $AllNodes.Where{$_.Role -eq "vmName-AZSWDOM"}.Nodename {
            
            LocalConfigurationManager {
                ConfigurationMode = "ApplyOnly"
                RebootNodeIfNeeded = $true
            }

            Script DisableFirewall 
            {
                GetScript = {
                    @{
                        GetScript = $GetScript
                        SetScript = $SetScript
                        TestScript = $TestScript
                        Result = -not('True' -in (Get-NetFirewallProfile -All).Enabled)
                    }
                }
            
                SetScript = {
                    Set-NetFirewallProfile -All -Enabled False -Verbose
                }
            
                TestScript = {
                    $Status = -not('True' -in (Get-NetFirewallProfile -All).Enabled)
                    $Status -eq $True
                }
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

            xDNSServerAddress DNSServerIP {
                Address = "127.0.0.1", "8.8.8.8"
                InterfaceAlias = $InterfaceAlias
                AddressFamily = "IPv4"
                DependsOn = "[WindowsFeature]DNS"
            }

            xWaitForDisk ADDisk {
                DiskId = 2
                RetryIntervalSec = $RetryIntercalSec
                RetryCount = $RetryCount
            }

            xDisk ADVolume {
                DiskId = 2
                DriveLetter = "N"
                FSFormat = "NTFS"
                FSLabel = "Active Directory Data"
                DependsOn = "[xWaitForDisk]ADDisk"
            }

            WindowsFeature ADDSInstall {
                Name = "AD-Domain-Services"
                Ensure = "Present"
                DependsOn = "[WindowsFeature]DNS"
            }

            WindowsFeature ADDSTools {
                Name = "RSAT-ADDS"
                Ensure = "Present"
                IncludeAllSubFeature = $true
                DependsOn = "[WindowsFeature]ADDSInstall"
            }

            xADDomain ConfigureAD {
                DomainName = $DomainName
                DomainAdministratorCredential = $DomainCreds
                SafeModeAdministratorPassword = $DomainCreds
                DatabasePath = "N:\NTDS"
                LogPath = "N:\NTDS"
                SysvolPath = "N:\SYSVOL"
                DependsOn = @("[xDisk]ADVolume", "[WindowsFeature]ADDSInstall")
            }
        }

        node $AllNodes.Where{$_.Role -eq "vmName-AZSWRDSH"}.Nodename {
            
            LocalConfigurationManager {
                ConfigurationMode = "ApplyOnly"
                RebootNodeIfNeeded = $true
            }
    
            Script DisableFirewall {
                GetScript = {
                    @{
                        GetScript = $GetScript
                        SetScript = $SetScript
                        TestScript = $TestScript
                        Result = -not('True' -in (Get-NetFirewallProfile -All).Enabled)
                    }
                }
            
                SetScript = {
                    Set-NetFirewallProfile -All -Enabled False -Verbose
                }
            
                TestScript = {
                    $Status = -not('True' -in (Get-NetFirewallProfile -All).Enabled)
                    $Status -eq $True
                }
            }
    
            xDNSServerAddress ConfigureDNS {
                Address = "10.0.2.254", "8.8.8.8"
                InterfaceAlias = $InterfaceAlias
                AddressFamily = "IPv4"
            }
            
            WindowsFeature RDS-RD-Server {
                Name = "RDS-RD-Server"
                Ensure = "Present"
            }
    
            WaitForAll ConfigureAD {
                ResourceName = "[xADDomain]ConfigureAD"
                NodeName = $ConnectionBroker
                RetryIntervalSec = $RetryIntervalSec
                RetryCount = $RetryCount
            }
    
            xComputer DomainJoin-AZSWRDSH {
                Name = $env:COMPUTERNAME
                DomainName = $DomainName
                Credential = $DomainCreds
                DependsOn = "[WaitForAll]ConfigureAD"
            }
        }

        node $AllNodes.Where{$_.Role -eq "vmName-AZSWGW"}.Nodename {
                    
            LocalConfigurationManager {
                ConfigurationMode = "ApplyOnly"
                RebootNodeIfNeeded = $true
            }

            Script DisableFirewall {
                GetScript = {
                    @{
                        GetScript = $GetScript
                        SetScript = $SetScript
                        TestScript = $TestScript
                        Result = -not('True' -in (Get-NetFirewallProfile -All).Enabled)
                    }
                }
            
                SetScript = {
                    Set-NetFirewallProfile -All -Enabled False -Verbose
                }
            
                TestScript = {
                    $Status = -not('True' -in (Get-NetFirewallProfile -All).Enabled)
                    $Status -eq $True
                }
            }

            xDNSServerAddress ConfigureDNS {
                Address = "10.0.2.254", "8.8.8.8"
                InterfaceAlias = $InterfaceAlias
                AddressFamily = "IPv4"
            }

            WindowsFeature RDS-Gateway {
                Ensure = "Present"
                Name = "RDS-Gateway"
            }

            WindowsFeature RDS-Web-Access {
                Ensure = "Present"
                Name = "RDS-Web-Access"
            }

            WaitForAll ConfigureAD {
                ResourceName = "[xADDomain]ConfigureAD"
                NodeName = $ConnectionBroker 
                RetryIntervalSec = $RetryIntervalSec
                RetryCount = $RetryCount
            }

            xComputer DomainJoin-AZSWGW {
                Name = $env:COMPUTERNAME
                DomainName = $DomainName
                Credential = $DomainCreds
                DependsOn = "[WaitForAll]ConfigureAD"
            }
        }

        node $AllNodes.Where{$_.Role -eq "vmName-AZSWDOM"}.Nodename {
        
            LocalConfigurationManager {
              ConfigurationMode = "ApplyOnly"
              RebootNodeIfNeeded = $true
            }

            WaitForAll ConfigureAD {
                ResourceName = "[xADDomain]ConfigureAD"
                NodeName = $ConnectionBroker
                RetryIntervalSec = $RetryIntervalSec
                RetryCount = $RetryCount
            }

            WindowsFeature RSAT-RDS-Tools {
                Name = "RSAT-RDS-Tools"
                Ensure = "Present"
                IncludeAllSubFeature = $True
                DependsOn = "[WaitForAll]ConfigureAD"
            }

            WindowsFeature RDS-Licensing {
                Name = "RDS-Licensing"
                Ensure = "Present"
                DependsOn = "[WaitForAll]ConfigureAD"                
            }

            <#xRDSessionDeployment Deployment {
                ConnectionBroker = $ConnectionBroker
                WebAccessServer = $WebAccessServer
                SessionHosts = $sessionHosts
                PsDscRunAsCredential = $domainCreds
                DependsOn = "[WaitForAll]DisableFirewall"
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
            }#>
        }
}