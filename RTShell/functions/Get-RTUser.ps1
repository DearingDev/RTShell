function Get-RTUser {
    <#
    .SYNOPSIS
        Retrieves an RT user record.

    .DESCRIPTION
        Returns account details for an RT user by numeric ID or login name.
        Useful for resolving the Owner and Requestors fields returned by
        Get-RTTicket into full contact records.

        By default only Name, RealName, and EmailAddress are shown.
        Use -Detailed to return all fields including address, phone numbers,
        and account status.

    .PARAMETER Id
        Numeric RT user ID.

    .PARAMETER Name
        RT login name (username) or email address. RT treats these
        interchangeably on the /user/{identifier} endpoint.

    .PARAMETER Detailed
        Return all user fields including address, phone numbers, organization,
        privilege level, and disabled status.

    .EXAMPLE
        Get-RTUser -Id 42

    .EXAMPLE
        Get-RTUser -Name jsmith

    .EXAMPLE
        Get-RTUser -Name jsmith@example.com

    .EXAMPLE
        Get-RTUser -Name jsmith -Detailed

    .EXAMPLE
        # Resolve the owner of a ticket
        $ticket = Get-RTTicket -Id 12345
        Get-RTUser -Name $ticket.Owner

    .OUTPUTS
        PSCustomObject with user fields.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [int]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Owner','Login','EmailAddress')]
        [string]$Name,

        [switch]$Detailed
    )

    process {
        $identifier = if ($PSCmdlet.ParameterSetName -eq 'ById') { $Id } else { $Name }
        Write-Verbose "Fetching user: $identifier"

        $raw = Invoke-RTRequest -Path "user/$identifier"

        if ($Detailed) {
            [PSCustomObject]@{
                PSTypeName    = 'RTShell.User'
                Id            = $raw.id
                Name          = $raw.Name
                RealName      = $raw.RealName
                NickName      = $raw.NickName
                EmailAddress  = $raw.EmailAddress
                Organization  = $raw.Organization
                Address1      = $raw.Address1
                Address2      = $raw.Address2
                City          = $raw.City
                State         = $raw.State
                Zip           = $raw.Zip
                Country       = $raw.Country
                HomePhone     = $raw.HomePhone
                WorkPhone     = $raw.WorkPhone
                MobilePhone   = $raw.MobilePhone
                Privileged    = $raw.Privileged
                Disabled      = $raw.Disabled
                _Raw          = $raw
            }
        } else {
            [PSCustomObject]@{
                PSTypeName   = 'RTShell.User'
                Name         = $raw.Name
                RealName     = $raw.RealName
                EmailAddress = $raw.EmailAddress
            }
        }
    }
}
