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
                Nodename = $ConnectionBroker
                Role = "DC"
            }
            @{ 
                Nodename = 
                Role = "GW"
            }
        )
    }
