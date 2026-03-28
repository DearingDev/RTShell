class RTSession {
    # Properties
    [string]   $BaseUri
    [string]   hidden $Token        # plain-text; hidden keeps it out of Format-List / Select-Object *
    [bool]     $Connected
    [System.Collections.Generic.List[hashtable]] $QueueCache

    # * 'hidden' suppresses the property from default display and Get-Member output,
    #   but it is still accessible via $Script:RTSession.Token when needed internally.

    # Constructor
    RTSession() {
        $this.Connected  = $false
        $this.QueueCache = [System.Collections.Generic.List[hashtable]]::new()
    }

    # Connection management

    # Called by Connect-RT after credentials have been resolved and the
    # connectivity test has passed.
    [void] Connect([string]$baseUri, [string]$token) {
        $this.BaseUri   = $baseUri.TrimEnd('/')
        $this.Token     = $token
        $this.Connected = $true
    }

    # Called by Disconnect-RT.
    [void] Disconnect() {
        $this.BaseUri    = $null
        $this.Token      = $null
        $this.Connected  = $false
        $this.QueueCache.Clear()
    }

    # Guard
    # Call at the top of any function that requires an active session.
    # Throws a consistent, actionable error if not connected.
    [void] AssertConnected() {
        if (-not $this.Connected) {
            throw "Not connected to an RT instance. Run Connect-RT first."
        }
    }

    # Header factory

    # Returns a fresh hashtable of HTTP request headers derived from the
    # current token. Invoke-RTRequest calls this instead of cloning a stored
    # hashtable, so there is no risk of a stale header copy floating around.
    [hashtable] GetHeaders() {
        $this.AssertConnected()
        return @{
            'Accept'        = 'application/json'
            'Authorization' = "token $($this.Token)"
        }
    }

    # Queue cache helpers

    [void] LoadQueueCache([object[]]$queues) {
        $this.QueueCache.Clear()
        foreach ($q in $queues) {
            # Accept both hashtables (from Update-RTQueueCache) and
            # PSCustomObjects (deserialised from config.json via ConvertFrom-Json)
            if ($q -is [hashtable]) {
                $this.QueueCache.Add($q)
            } else {
                $this.QueueCache.Add(@{
                    Id          = $q.Id
                    Name        = $q.Name
                    Description = $q.Description
                    Disabled    = $q.Disabled
                })
            }
        }
    }

    # Display

    [string] ToString() {
        if ($this.Connected) {
            return "[RTSession Connected: $($this.BaseUri) ($($this.QueueCache.Count) queues cached)]"
        }
        return "[RTSession Disconnected]"
    }
}
