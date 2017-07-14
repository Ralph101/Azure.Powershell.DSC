# Configuration Data for AD  
    param (
        [Parameter(Mandatory)]
        [String]$ConnectionBroker,
        
        [Parameter(Mandatory)]
        [String]$WebAccessServer,
    )

    @{
        AllNodes = @(
            @{
                NodeName="*"
                PSDscAllowPlainTextPassword=$true
                PSDscAllowDomainUser = $true
            },
            @{ 
                Nodename = "localhost"
                Role = "DC"
            },
            @{ 
                Nodename = $WebAccessServer
                Role = "GW"
            }
        )
    }
