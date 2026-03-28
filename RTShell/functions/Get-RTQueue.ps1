function Get-RTQueue {
    <#
    .SYNOPSIS
        Retrieves RT queue information.

    .DESCRIPTION
        When called with -Id, returns details for a specific queue.
        When called without parameters, lists all queues visible to the
        authenticated user.

        Knowing queue names is essential for building TicketSQL queries
        with Search-RTTicket.

    .PARAMETER Id
        Queue ID to retrieve. If omitted, all accessible queues are listed.

    .PARAMETER Name
        Queue name to look up. Performs a client-side filter on the full list.

    .EXAMPLE
        Get-RTQueue

        List all queues visible to the authenticated user.

    .EXAMPLE
        Get-RTQueue -Id 3

        Retrieve a specific queue by its numeric ID.

    .EXAMPLE
        Get-RTQueue -Name 'HelpDesk'

        Search for a queue by name.

    .OUTPUTS
        PSCustomObject per queue.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [int]$Id,

        [Parameter(ParameterSetName = 'List')]
        [string]$Name
    )

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        Write-Verbose "Fetching queue #$Id"
        $raw = Invoke-RTRequest -Path "queue/$Id"
        return ConvertTo-RTQueueObject $raw
    }

    # List all queues
    Write-Verbose "Fetching all queues"
    $result = Invoke-RTRequest -Path 'queues/all'

    $queues = foreach ($item in $result.items) {
        $detail = Invoke-RTRequest -Path "queue/$($item.id)"
        ConvertTo-RTQueueObject $detail
    }

    if ($Name) {
        $queues = $queues | Where-Object { $_.Name -like "*$Name*" }
    }

    $queues
}


function ConvertTo-RTQueueObject {
    param($raw)
    [PSCustomObject]@{
        PSTypeName          = 'RTShell.Queue'
        Id                  = $raw.id
        Name                = $raw.Name
        Description         = $raw.Description
        CorrespondAddress   = $raw.CorrespondAddress
        CommentAddress      = $raw.CommentAddress
        SLADisabled         = $raw.SLADisabled
        Disabled            = $raw.Disabled
        _Raw                = $raw
    }
}
