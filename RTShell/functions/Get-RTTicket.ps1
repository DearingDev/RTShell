function Get-RTTicket {
    <#
    .SYNOPSIS
        Retrieves metadata for one or more RT tickets by ID.

    .DESCRIPTION
        Calls GET /REST/2.0/ticket/{id} for each supplied ticket ID and returns
        a structured object containing the ticket fields.

        By default only the most useful fields are shown: Id, Subject, Status,
        Queue, Owner, Requestors, Created, Resolved, and LastUpdated.

        Use -Detailed to also include priority, time tracking, Cc/AdminCc,
        custom fields, and the raw API response.

    .PARAMETER Id
        One or more ticket IDs to retrieve. Accepts pipeline input.

    .PARAMETER Detailed
        Return all ticket fields including priority, time tracking, Cc/AdminCc,
        custom fields, and the raw API response object.

    .EXAMPLE
        Get-RTTicket -Id 12345

    .EXAMPLE
        Get-RTTicket -Id 100, 101, 102

    .EXAMPLE
        Search-RTTicket -Query "Queue='General' AND Status='open'" | Get-RTTicket

    .EXAMPLE
        Get-RTTicket -Id 12345 -Detailed

    .OUTPUTS
        PSCustomObject with ticket fields.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('TicketId','numerical_id')]
        [int[]]$Id,

        [switch]$Detailed
    )

    process {
        foreach ($ticketId in $Id) {
            Write-Verbose "Fetching ticket #$ticketId"

            $raw = Invoke-RTRequest -Path "ticket/$ticketId"

            $toDate = {
                param($val)
                if (-not $val) { return $null }
                try {
                    $dt = [datetime]$val
                    if ($dt.Year -le 1970) { return $null }
                    return $dt
                }
                catch { return $null }
            }

            $toName = {
                param($obj)
                if ($null -eq $obj)              { return $null }
                if ($obj -is [string])           { return $obj }
                if ($obj.id -and $obj.id -ne '') { return $obj.id }
                return $null
            }

            $toId = {
                param($obj)
                if ($null -eq $obj) { return $null }
                $url = if ($obj -is [string]) { $obj } else { $obj._url }
                if ($url) { return ($url | ConvertFrom-RTLinks) }
                if ($obj.id) { return $obj.id }
                return $null
            }

            $toNameList = {
                param($arr)
                if (-not $arr) { return @() }
                @($arr | ForEach-Object {
                    if ($_ -is [string]) { $_ }
                    elseif ($_.id)       { $_.id }
                })
            }

            # Resolve the Queue name from the queue record so we surface
            # the human-readable name rather than just the numeric ID.
            $queueName = & $toName $raw.Queue
            $queueId   = & $toId   $raw.Queue
            if ($queueId -and $queueId -match '^\d+$') {
                try {
                    $queueDetail = Invoke-RTRequest -Path "queue/$queueId"
                    $queueName   = $queueDetail.Name
                }
                catch {
                    Write-Verbose "Could not resolve queue name for ID $queueId"
                }
            }

            if ($Detailed) {
                [PSCustomObject]@{
                    PSTypeName      = 'RTShell.Ticket'
                    Id              = $raw.id
                    Subject         = $raw.Subject
                    Status          = $raw.Status
                    Queue           = $queueName
                    QueueId         = $queueId
                    Owner           = & $toName $raw.Owner
                    OwnerId         = & $toId   $raw.Owner
                    Requestors      = & $toNameList $raw.Requestor
                    Cc              = & $toNameList $raw.Cc
                    AdminCc         = & $toNameList $raw.AdminCc
                    Priority        = $raw.Priority
                    FinalPriority   = $raw.FinalPriority
                    InitialPriority = $raw.InitialPriority
                    TimeEstimated   = $raw.TimeEstimated
                    TimeWorked      = $raw.TimeWorked
                    TimeLeft        = $raw.TimeLeft
                    Created         = & $toDate $raw.Created
                    Starts          = & $toDate $raw.Starts
                    Started         = & $toDate $raw.Started
                    Due             = & $toDate $raw.Due
                    Resolved        = & $toDate $raw.Resolved
                    LastUpdated     = & $toDate $raw.LastUpdated
                    CustomFields    = $raw.CustomFields
                    _Raw            = $raw
                }
            } else {
                [PSCustomObject]@{
                    PSTypeName  = 'RTShell.Ticket'
                    Id          = $raw.id
                    Subject     = $raw.Subject
                    Status      = $raw.Status
                    Queue       = $queueName
                    Owner       = & $toName $raw.Owner
                    Requestors  = & $toNameList $raw.Requestor
                    Created     = & $toDate $raw.Created
                    Resolved    = & $toDate $raw.Resolved
                    LastUpdated = & $toDate $raw.LastUpdated
                }
            }
        }
    }
}
