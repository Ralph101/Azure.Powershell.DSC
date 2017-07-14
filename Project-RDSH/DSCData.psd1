# Configuration Data for AD  
@{
    AllNodes = @(
        @{
            NodeName="*"
            PSDscAllowPlainTextPassword=$true
            PSDscAllowDomainUser = $true
        },
        @{ 
            Nodename = $ConnectionBroker
            Role = "DC"
        }
        @{ 
            Nodename = $WebAccessServer
            Role = "GW"
        }
    )
}
