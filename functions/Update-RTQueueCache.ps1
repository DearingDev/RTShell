function Update-RTQueueCache {
    <#
    .SYNOPSIS
        Refreshes the local queue name cache from the RT server.

    .DESCRIPTION
        Fetches all queues from RT and stores them in ~/.rtshell/config.json.
        The cache is used by Search-RTTicket for tab completion and by
        Get-RTQueue to avoid repeated API calls.

        Connect-RT automatically populates the cache on first connect if
        it is empty or older than 24 hours. Call this manually when queues
        have been added, renamed, or disabled in RT.

    .EXAMPLE
        Update-RTQueueCache

    .EXAMPLE
        # Check when the cache was last updated
        (Get-Content ~/.rtshell/config.json | ConvertFrom-Json).QueueCacheDate

    .OUTPUTS
        None. Updates ~/.rtshell/config.json.
    #>
    [CmdletBinding()]
    param()

    $Script:RTSession.AssertConnected()

    Write-Verbose "Refreshing queue cache from RT..."

    $result = Invoke-RTRequest -Path 'queues/all'

    if (-not $result.items -or $result.items.Count -eq 0) {
        Write-Warning "No queues returned from RT. Cache not updated."
        return
    }

    $queues = foreach ($item in $result.items) {
        $detail = Invoke-RTRequest -Path "queue/$($item.id)"
        @{
            Id          = $detail.id
            Name        = $detail.Name
            Description = $detail.Description
            Disabled    = [bool][int]$detail.Disabled
        }
    }

    $config = Get-RTConfig
    if (-not $config) { $config = @{} }

    $configHash = @{
        BaseUri        = $config.BaseUri
        QueueCache     = @($queues)
        QueueCacheDate = (Get-Date -Format 'o')
    }

    Save-RTConfig -Config $configHash

    # Update the in-memory session so the current session benefits immediately.
    $Script:RTSession.LoadQueueCache($queues)

    Write-Host "Queue cache updated: $($Script:RTSession.QueueCache.Count) queue(s) cached." -ForegroundColor Green
}
