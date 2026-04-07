function Search-RTTicket {
    <#
    .SYNOPSIS
        Searches for RT tickets using either structured parameters or a raw
        TicketSQL query string.

    .DESCRIPTION
        Provides two ways to search:

        1. STRUCTURED (default) — use individual parameters like -Status,
           -Queue, -Owner, -Requestor, and -Keyword. These are combined into
           a TicketSQL query automatically.

        2. RAW — pass a full TicketSQL query string via -Query for advanced
           searches not covered by the structured parameters.

        TicketSQL reference:
        https://rt-wiki.bestpractical.com/wiki/TicketSQL

    .PARAMETER Status
        Filter by ticket status. Accepts one or more values.
        Common values: new, open, stalled, resolved, rejected, deleted
        Defaults to 'open' when no other parameters imply a different scope.
        Pass '*' or 'any' to return tickets of all statuses.

    .PARAMETER Queue
        Filter by one or more queue names. Case-insensitive.
        Tab-completes from the cached queue list.

    .PARAMETER Owner
        Filter by owner username. Use 'Nobody' for unassigned tickets.

    .PARAMETER Requestor
        Filter by requestor email address or username.

    .PARAMETER Keyword
        One or more search terms to match against the ticket Subject (or body
        with -IncludeContent). Each value is treated as a phrase and matched
        as a substring using SQL LIKE '%term%' — spaces within a value are
        preserved, so 'Power Automate Premium' matches any subject containing
        that exact phrase. Multiple values default to AND logic; use -MatchAny
        for OR logic across terms.

    .PARAMETER IncludeContent
        When used with -Keyword, also searches message body content
        in addition to the Subject.

    .PARAMETER MatchAny
        When multiple -Keyword values are provided, use OR logic instead
        of the default AND logic.

    .PARAMETER Query
        A raw TicketSQL query string. Use this for advanced searches.
        When specified, all structured parameters are ignored.

    .PARAMETER OrderBy
        Field to sort results by. Defaults to 'id'.

    .PARAMETER Order
        Sort direction. Defaults to DESC.

    .PARAMETER Page
        Page number. Defaults to 1.

    .PARAMETER PageSize
        Results per page (max 100). Defaults to 50.

    .PARAMETER All
        Automatically fetch all pages and return every matching ticket.
        Ignores -Page. -PageSize still controls the batch size per request
        (default 50; raise to 100 to minimise round-trips on large result sets).

    .EXAMPLE
        Search-RTTicket

        Retrieve all open tickets (default behavior).

    .EXAMPLE
        Search-RTTicket -Queue 'HelpDesk'

        Search for open tickets in a specific queue.

    .EXAMPLE
        Search-RTTicket -Status new, open, stalled -Owner jsmith

        Find unresolved tickets owned by a specific user.

    .EXAMPLE
        Search-RTTicket -Keyword 'VPN'

        Search for tickets with a single keyword in the subject.

    .EXAMPLE
        Search-RTTicket -Keyword 'Power Automate Premium'

        Search for tickets matching a multi-word phrase.

    .EXAMPLE
        Search-RTTicket -Keyword 'VPN', 'timeout'

        Search for tickets matching multiple keywords using AND logic.

    .EXAMPLE
        Search-RTTicket -Keyword 'Power Automate Premium' -IncludeContent

        Search for a phrase in both subject and body content.

    .EXAMPLE
        Search-RTTicket -Requestor 'user@example.com' -Status any

        Find all tickets from a requestor regardless of ticket status.

    .EXAMPLE
        Search-RTTicket -Query "Queue='Network' AND Priority >= 50 AND Created > '2026-01-01'"

        Execute a raw TicketSQL query for complex searches.

    .EXAMPLE
        Search-RTTicket -Keyword 'Solidworks' -Status any -All

        Retrieve all matching tickets across every page.

    .EXAMPLE
        Search-RTTicket -Keyword 'Solidworks' -Status any -All -PageSize 100

        Fetch all results with a larger batch size to reduce API round-trips.

    .OUTPUTS
        PSCustomObject per matching ticket (summary). Pipe to Get-RTTicket for full detail.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Structured')]
    [OutputType([PSCustomObject])]
    param(
        # Structured parameters
        [Parameter(ParameterSetName = 'Structured')]
        [ValidateSet('new','open','stalled','resolved','rejected','deleted','any')]
        [string[]]$Status = @('open'),

        [Parameter(ParameterSetName = 'Structured')]
        [string[]]$Queue,

        [Parameter(ParameterSetName = 'Structured')]
        [string]$Owner,

        [Parameter(ParameterSetName = 'Structured')]
        [string]$Requestor,

        [Parameter(ParameterSetName = 'Structured')]
        [string[]]$Keyword,

        [Parameter(ParameterSetName = 'Structured')]
        [switch]$IncludeContent,

        [Parameter(ParameterSetName = 'Structured')]
        [switch]$MatchAny,

        # Raw TicketSQL
        [Parameter(Mandatory, ParameterSetName = 'Raw')]
        [ValidateNotNullOrEmpty()]
        [string]$Query,

        # Shared parameters
        [string]$OrderBy   = 'id',

        [ValidateSet('ASC', 'DESC')]
        [string]$Order     = 'DESC',

        [ValidateRange(1, [int]::MaxValue)]
        [int]$Page         = 1,

        [ValidateRange(1, 100)]
        [int]$PageSize     = 50,

        [switch]$All
    )

    # Build TicketSQL from structured parameters
    if ($PSCmdlet.ParameterSetName -eq 'Structured') {
        $clauses = [System.Collections.Generic.List[string]]::new()

        # Status
        $statusAny = $Status | Where-Object { $_ -in '*','any','all' }
        if (-not $statusAny) {
            if ($Status.Count -eq 1) {
                $clauses.Add("Status='$($Status[0])'")
            }
            else {
                $statusParts = $Status | ForEach-Object { "Status='$_'" }
                $clauses.Add("($($statusParts -join ' OR '))")
            }
        }
        # If status is 'any'/'*', no status clause added -- returns all statuses

        # Queue
        if ($Queue) {
            if ($Queue.Count -eq 1) {
                $clauses.Add("Queue='$($Queue[0])'")
            }
            else {
                $queueParts = $Queue | ForEach-Object { "Queue='$_'" }
                $clauses.Add("($($queueParts -join ' OR '))")
            }
        }

        # Owner
        if ($Owner) {
            $clauses.Add("Owner='$Owner'")
        }

        # Requestor
        if ($Requestor) {
            # RT accepts both email and username on this field
            $clauses.Add("Requestor.EmailAddress='$Requestor' OR Requestor='$Requestor'")
            # Wrap in parens since this is an OR internally
            $last = $clauses[$clauses.Count - 1]
            $clauses[$clauses.Count - 1] = "($last)"
        }

        # Keywords
        if ($Keyword) {
            $logic       = if ($MatchAny) { ' OR ' } else { ' AND ' }
            $keywordParts = [System.Collections.Generic.List[string]]::new()

            foreach ($kw in $Keyword) {
                $escaped = $kw -replace "'", "''"   # escape single quotes
                if ($IncludeContent) {
                    $keywordParts.Add("(Subject LIKE '$escaped' OR Content LIKE '$escaped')")
                }
                else {
                    $keywordParts.Add("Subject LIKE '$escaped'")
                }
            }

            if ($keywordParts.Count -eq 1) {
                $clauses.Add($keywordParts[0])
            }
            else {
                $clauses.Add("($($keywordParts -join $logic))")
            }
        }

        if ($clauses.Count -eq 0) {
            # No filters at all -- default to open tickets
            $Query = "Status='open'"
        }
        else {
            $Query = $clauses -join ' AND '
        }

        Write-Verbose "Built query: $Query"
    }
    else {
        Write-Verbose "Using raw query: $Query"
    }

    # Execute search

    # Helper: emit PSCustomObjects from a single page result.
    $emitPage = {
        param($result)
        foreach ($item in $result.items) {
            $obj = [PSCustomObject]@{
                PSTypeName  = 'RTShell.TicketSummary'
                Id          = $item.id
                Subject     = $item.Subject
                Status      = $item.Status
                Queue       = if ($item.Queue.Name) { $item.Queue.Name }
                              elseif ($item.Queue.id) {
                                  $queueId   = $item.Queue.id
                                  $cached    = $Script:RTSession.QueueCache | Where-Object { $_.Id -eq $queueId } | Select-Object -First 1
                                  if ($cached) { $cached.Name } else { $queueId }
                              }
                              else { $null }
                Owner       = if ($item.Owner.id)   { $item.Owner.id }
                              elseif ($item.Owner -is [string]) { $item.Owner }
                              else { $null }
                Created     = if ($item.Created)     { try { [datetime]$item.Created }     catch { $null } } else { $null }
                LastUpdated = if ($item.LastUpdated) { try { [datetime]$item.LastUpdated } catch { $null } } else { $null }
            }
            $obj
            # Add numerical_id alias so Get-RTTicket can consume via pipeline
            $obj | Add-Member -NotePropertyName 'numerical_id' -NotePropertyValue $item.id -Force
        }
    }

    $qp = @{
        query    = $Query
        orderby  = $OrderBy
        order    = $Order
        per_page = $PageSize
        fields   = 'id,Subject,Status,Queue,Owner,Created,LastUpdated'
    }

    if ($All) {
        # ── Auto-paginate: fetch page 1, then continue until all pages done ──
        $qp['page'] = 1
        $result = Invoke-RTRequest -Path 'tickets' -QueryParameters $qp

        if ($null -eq $result -or $result.count -eq 0) {
            Write-Verbose "No tickets matched the query."
            return
        }

        $totalPages = [math]::Ceiling($result.total / $PageSize)
        Write-Verbose "Query returned $($result.total) total match(es) across $totalPages page(s). Fetching all."

        & $emitPage $result

        for ($p = 2; $p -le $totalPages; $p++) {
            Write-Verbose "Fetching page $p of $totalPages..."
            $qp['page'] = $p
            $result = Invoke-RTRequest -Path 'tickets' -QueryParameters $qp
            if ($null -eq $result -or $result.count -eq 0) { break }
            & $emitPage $result
        }
    }
    else {
        # Single page
        $qp['page'] = $Page
        $result = Invoke-RTRequest -Path 'tickets' -QueryParameters $qp

        if ($null -eq $result -or $result.count -eq 0) {
            Write-Verbose "No tickets matched the query."
            return
        }

        $totalPages = [math]::Ceiling($result.total / $PageSize)
        Write-Verbose "Query returned $($result.total) total match(es); page $($result.page) of $totalPages."

        & $emitPage $result
    }
}
