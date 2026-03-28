function Get-RTTicketHistory {
    <#
    .SYNOPSIS
        Retrieves the transaction history (comments, replies, status changes)
        for an RT ticket.

    .DESCRIPTION
        Returns correspondence, comments, and file attachments for a ticket.
        Internal transactions (status changes, field updates, etc.) are
        excluded by default; use -Detailed to include them.

        On PowerShell 7+, transactions are fetched in parallel automatically.
        Use -ThrottleLimit to tune concurrency (default: 5).

        Note: parallel mode does not guarantee chronological order.
        Pipe through Sort-Object Created if order matters.

    .PARAMETER Id
        Ticket ID. Accepts pipeline input from Search-RTTicket / Get-RTTicket.

    .PARAMETER Type
        Filter to a single transaction type: Correspond, Comment, Create, etc.

    .PARAMETER Detailed
        Include all transaction types (status changes, field sets, etc.) and
        return the full RTShell.TicketTransaction object instead of the summary.

    .PARAMETER Raw
        Skip HTML stripping and quoted-reply removal. Returns content as-is
        from RT (useful for debugging or archiving).

    .PARAMETER ThrottleLimit
        PowerShell 7+ only. Maximum number of concurrent API requests when
        fetching transaction details. Default: 5. Has no effect on PS 5.1.

    .PARAMETER Page
        Page number for the history list. Defaults to 1.

    .PARAMETER PageSize
        Results per page (max 100). Defaults to 50.

    .EXAMPLE
        Get-RTTicketHistory -Id 12345

        Retrieve the transaction history for a ticket, showing correspondence and comments.

    .EXAMPLE
        Get-RTTicketHistory -Id 12345 -Type Correspond

        Retrieve only outbound correspondence transactions for a ticket.

    .EXAMPLE
        Get-RTTicketHistory -Id 12345 -Detailed

        Retrieve all transaction types including internal status changes and field updates.

    .EXAMPLE
        Get-RTTicketHistory -Id 12345 | Sort-Object Created | Format-List Created, CreatorName, Content

        Fetch the full thread for a ticket and display it in chronological order.

    .OUTPUTS
        RTShell.TicketHistory.Summary  (default)
        RTShell.TicketTransaction      (-Detailed)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('TicketId','numerical_id')]
        [int]$Id,

        [string]$Type,

        [switch]$Detailed,

        [switch]$Raw,

        [ValidateRange(1, 20)]
        [int]$ThrottleLimit = 5,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$Page     = 1,

        [ValidateRange(1, 100)]
        [int]$PageSize = 50
    )

    process {
        Write-Verbose "Fetching history for ticket #$Id"

        # 1. Fetch history list
        # Request Type inline so we can pre-filter before making per-transaction
        # detail calls. RT 4.4+ honours the fields parameter on list endpoints.
        # Older versions return their defaults — safe either way.
        $qp = @{
            page     = $Page
            per_page = $PageSize
            fields   = 'id,Type'
        }

        $result = Invoke-RTRequest -Path "ticket/$Id/history" -QueryParameters $qp
        if (-not $result.items -or $result.items.Count -eq 0) {
            Write-Verbose "No history items returned for ticket #$Id"
            return
        }

        Write-Verbose "History list returned $($result.items.Count) item(s)"

        $contentTypes = 'Correspond', 'Comment', 'Create'

        # 2. Pre-filter on summary Type if RT returned it
        # If RT populated Type on the list items we can skip the detail call
        # entirely for transactions we would discard anyway.
        # If Type is absent/null on an item we must pass it through — the
        # detail call will make the final decision.
        $candidates = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $result.items) {
            $summaryType = $item.Type

            if ($summaryType) {
                if (-not $Detailed -and $summaryType -notin $contentTypes) {
                    Write-Verbose "Pre-filtered transaction $($item.id) (Type=$summaryType)"
                    continue
                }
                if ($Type -and $summaryType -ne $Type) {
                    Write-Verbose "Pre-filtered transaction $($item.id) (Type=$summaryType, wanted=$Type)"
                    continue
                }
            }
            $candidates.Add($item)
        }

        Write-Verbose "$($candidates.Count) candidate transaction(s) after pre-filter"
        if ($candidates.Count -eq 0) { return }

        # 3. Snapshot session values for parallel runspaces
        $baseUri = $Script:RTSession.BaseUri
        $token   = $Script:RTSession.Token

        # 4. Execute — parallel (PS7+) or sequential (PS5.1)
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $candidates | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                $item         = $_
                $baseUri      = $using:baseUri
                $token        = $using:token
                $contentTypes = $using:contentTypes
                $Detailed     = $using:Detailed
                $Type         = $using:Type
                $Raw          = $using:Raw
                $Id           = $using:Id

                # Redefined inside the runspace — functions don't cross runspace boundaries.
                function Invoke-RTGetLocal {
                    param([string]$Uri, [string]$Token)
                    $headers = @{
                        'Accept'        = 'application/json'
                        'Authorization' = "token $Token"
                    }
                    try {
                        Invoke-RestMethod -Uri $Uri -Headers $headers -Method GET -ErrorAction Stop
                    } catch {
                        $sc = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
                        if ($sc -eq 403) { return $null }
                        throw
                    }
                }

                $detail = Invoke-RTGetLocal "$baseUri/REST/2.0/transaction/$($item.id)" $token
                if ($null -eq $detail) { return }

                if (-not $Detailed -and $detail.Type -notin $contentTypes) { return }
                if ($Type -and $detail.Type -ne $Type)                     { return }

                $creatorName = $detail.Creator.id
                $creatorId   = if ($detail.Creator._url -match '/(\d+)$') { [int]$Matches[1] } else { $null }
                $content     = $null
                $fileNames   = [System.Collections.Generic.List[string]]::new()

                if ($detail.Type -in $contentTypes) {
                    foreach ($link in @($detail._hyperlinks | Where-Object { $_.ref -eq 'attachment' })) {
                        $aId = if ($link._url -match '/(\d+)$') { [int]$Matches[1] } else { $null }
                        if (-not $aId) { continue }

                        $att = Invoke-RTGetLocal "$baseUri/REST/2.0/attachment/$aId" $token
                        if ($null -eq $att) { continue }

                        if (-not [string]::IsNullOrWhiteSpace($att.Filename)) { $fileNames.Add($att.Filename) }

                        if ($att.Content) {
                            $decoded = if ($att.ContentEncoding -in 'base64','base64url' -or
                                           $att.Content -match '^[A-Za-z0-9+/\r\n]+=*$') {
                                try {
                                    [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($att.Content))
                                } catch { $att.Content }
                            } else { $att.Content }

                            if ($att.ContentType -like 'text/plain*')                                    { $content = $decoded; break }
                            elseif ($att.ContentType -like 'text/html*')                                 { $content = $decoded }
                            elseif (-not $content -and $att.ContentType -notlike 'multipart/*')          { $content = $decoded }
                        }
                    }
                }

                if (-not $Raw -and $content) {
                    $content = $content -replace '(?is)<br[^>]*>',  "`n"
                    $content = $content -replace '(?is)</p>',       "`n"
                    $content = $content -replace '(?is)<[^>]+>',    ''
                    $content = [System.Net.WebUtility]::HtmlDecode($content)
                    $content = $content -replace '(?is)\r?\n[_-]{2,}\s*Original Message\s*[_-]{2,}.*', ''
                    $content = $content -replace '(?is)\r?\n[_-]{2,}\s*From:\s.*?Sent:\s.*',           ''
                    $content = $content -replace '(?is)\r?\nFrom:\s.*?Sent:\s.*',                       ''
                    $content = $content -replace '(?is)\r?\nOn\s.*?(?:wrote|sent):\s*.*',              ''
                    $content = $content -replace '(?sm)^-- \r?\n.*',                                    ''
                    $content = $content -replace '(?m)^[ \t]*>.*$',                                    ''
                    $content = $content -replace '(?m)^[-_=\*]{4,}\s*$',                              ''
                    $content = $content -replace '(?m)^[ \t]+|[ \t]+$',                               ''
                    $content = $content -replace '(\r?\n){3,}',                                        "`n`n"
                    $content = if ($content -match '^\s*$') { $null } else { $content.Trim() }
                }

                if (-not $Detailed) {
                    if ([string]::IsNullOrWhiteSpace($content) -and $fileNames.Count -eq 0) { return }
                    [PSCustomObject]@{
                        PSTypeName  = 'RTShell.TicketHistory.Summary'
                        TicketId    = $Id
                        Created     = if ($detail.Created) { [datetime]$detail.Created } else { $null }
                        CreatorName = $creatorName
                        Files       = if ($fileNames.Count -gt 0) { $fileNames -join ', ' } else { $null }
                        Content     = $content
                    }
                } else {
                    [PSCustomObject]@{
                        PSTypeName    = 'RTShell.TicketTransaction'
                        TransactionId = $detail.id
                        TicketId      = $Id
                        Type          = $detail.Type
                        Created       = if ($detail.Created) { [datetime]$detail.Created } else { $null }
                        CreatorName   = $creatorName
                        CreatorId     = $creatorId
                        Files         = if ($fileNames.Count -gt 0) { $fileNames -join ', ' } else { $null }
                        Content       = $content
                        Attachments   = $detail._hyperlinks | Where-Object { $_.ref -eq 'attachment' }
                        OldValue      = $detail.OldValue
                        NewValue      = $detail.NewValue
                        Field         = $detail.Field
                        _Raw          = $detail
                    }
                }
            }

        } else {
            # PS5.1 sequential path
            function Invoke-RTGetLocal {
                param([string]$Uri, [string]$Token)
                $headers = @{
                    'Accept'        = 'application/json'
                    'Authorization' = "token $Token"
                }
                try {
                    Invoke-RestMethod -Uri $Uri -Headers $headers -Method GET -ErrorAction Stop
                } catch {
                    $sc = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
                    if ($sc -eq 403) { return $null }
                    throw
                }
            }

            foreach ($item in $candidates) {
                $detail = Invoke-RTGetLocal "$baseUri/REST/2.0/transaction/$($item.id)" $token
                if ($null -eq $detail) { continue }

                if (-not $Detailed -and $detail.Type -notin $contentTypes) { continue }
                if ($Type -and $detail.Type -ne $Type)                     { continue }

                $creatorName = $detail.Creator.id
                $creatorId   = if ($detail.Creator._url -match '/(\d+)$') { [int]$Matches[1] } else { $null }
                $content     = $null
                $fileNames   = [System.Collections.Generic.List[string]]::new()

                if ($detail.Type -in $contentTypes) {
                    foreach ($link in @($detail._hyperlinks | Where-Object { $_.ref -eq 'attachment' })) {
                        $aId = if ($link._url -match '/(\d+)$') { [int]$Matches[1] } else { $null }
                        if (-not $aId) { continue }

                        $att = Invoke-RTGetLocal "$baseUri/REST/2.0/attachment/$aId" $token
                        if ($null -eq $att) { continue }

                        if (-not [string]::IsNullOrWhiteSpace($att.Filename)) { $fileNames.Add($att.Filename) }

                        if ($att.Content) {
                            $decoded = if ($att.ContentEncoding -in 'base64','base64url' -or
                                           $att.Content -match '^[A-Za-z0-9+/\r\n]+=*$') {
                                try {
                                    [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($att.Content))
                                } catch { $att.Content }
                            } else { $att.Content }

                            if ($att.ContentType -like 'text/plain*')                                    { $content = $decoded; break }
                            elseif ($att.ContentType -like 'text/html*')                                 { $content = $decoded }
                            elseif (-not $content -and $att.ContentType -notlike 'multipart/*')          { $content = $decoded }
                        }
                    }
                }

                if (-not $Raw -and $content) {
                    $content = $content -replace '(?is)<br[^>]*>',  "`n"
                    $content = $content -replace '(?is)</p>',       "`n"
                    $content = $content -replace '(?is)<[^>]+>',    ''
                    $content = [System.Net.WebUtility]::HtmlDecode($content)
                    $content = $content -replace '(?is)\r?\n[_-]{2,}\s*Original Message\s*[_-]{2,}.*', ''
                    $content = $content -replace '(?is)\r?\n[_-]{2,}\s*From:\s.*?Sent:\s.*',           ''
                    $content = $content -replace '(?is)\r?\nFrom:\s.*?Sent:\s.*',                       ''
                    $content = $content -replace '(?is)\r?\nOn\s.*?(?:wrote|sent):\s*.*',              ''
                    $content = $content -replace '(?sm)^-- \r?\n.*',                                    ''
                    $content = $content -replace '(?m)^[ \t]*>.*$',                                    ''
                    $content = $content -replace '(?m)^[-_=\*]{4,}\s*$',                              ''
                    $content = $content -replace '(?m)^[ \t]+|[ \t]+$',                               ''
                    $content = $content -replace '(\r?\n){3,}',                                        "`n`n"
                    $content = if ($content -match '^\s*$') { $null } else { $content.Trim() }
                }

                if (-not $Detailed) {
                    if ([string]::IsNullOrWhiteSpace($content) -and $fileNames.Count -eq 0) { continue }
                    [PSCustomObject]@{
                        PSTypeName  = 'RTShell.TicketHistory.Summary'
                        TicketId    = $Id
                        Created     = if ($detail.Created) { [datetime]$detail.Created } else { $null }
                        CreatorName = $creatorName
                        Files       = if ($fileNames.Count -gt 0) { $fileNames -join ', ' } else { $null }
                        Content     = $content
                    }
                } else {
                    [PSCustomObject]@{
                        PSTypeName    = 'RTShell.TicketTransaction'
                        TransactionId = $detail.id
                        TicketId      = $Id
                        Type          = $detail.Type
                        Created       = if ($detail.Created) { [datetime]$detail.Created } else { $null }
                        CreatorName   = $creatorName
                        CreatorId     = $creatorId
                        Files         = if ($fileNames.Count -gt 0) { $fileNames -join ', ' } else { $null }
                        Content       = $content
                        Attachments   = $detail._hyperlinks | Where-Object { $_.ref -eq 'attachment' }
                        OldValue      = $detail.OldValue
                        NewValue      = $detail.NewValue
                        Field         = $detail.Field
                        _Raw          = $detail
                    }
                }
            }
        }
    }
}
