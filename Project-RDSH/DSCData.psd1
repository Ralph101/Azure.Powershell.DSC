# Configuration Data for AD  
@{
    AllNodes = @(
        @{
            NodeName="*"
            PSDscAllowPlainTextPassword=$true
            PSDscAllowDomainUser = $true
        },
        @{ 
            Nodename = "ITSAZSWDOM01"
            Role = "DC"
        }
        @{ 
            Nodename = "ITSAZSWGW01"
            Role = "GW"
        }
    )
}
