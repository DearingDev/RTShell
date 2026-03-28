function Connect-RT {
    <#
    .SYNOPSIS
        Establishes a session with a Request Tracker instance.

    .DESCRIPTION
        Connects to RT using the provided credentials, or automatically loads
        saved credentials from ~/.rtshell/ if no parameters are passed.

        To save credentials for automatic use, run Save-RTConfiguration first:
          $tok = Read-Host -AsSecureString -Prompt 'RT API Token'
          Save-RTConfiguration -BaseUri 'https://rt.example.com' -Token $tok

        Then connect without parameters in future sessions:
          Connect-RT

        Authentication uses an Authorization header on every request.

        The queue cache is loaded from ~/.rtshell/config.json on connect but is
        never automatically refreshed. Run Update-RTQueueCache after adding
        or renaming queues in RT.

    .PARAMETER BaseUri
        The root URL of your RT instance. If omitted, loaded from config.

    .PARAMETER Token
        API token as a SecureString. If omitted, loaded from ~/.rtshell/token.

    .PARAMETER TokenPlainText
        API token as plain text. Useful for CI/scripting.

    .EXAMPLE
        # First time setup
        $tok = Read-Host -AsSecureString -Prompt 'RT API Token'
        Save-RTConfiguration -BaseUri 'https://rt.example.com' -Token $tok
        Connect-RT

    .EXAMPLE
        # Subsequent sessions
        Connect-RT

    .EXAMPLE
        # Override saved config
        Connect-RT -BaseUri 'https://rt.example.com' -TokenPlainText $env:RT_TOKEN

    .OUTPUTS
        None. Sets module session state on success.
    #>
    [CmdletBinding(DefaultParameterSetName = 'FromConfig')]
    param(
        [Parameter(ParameterSetName = 'FromConfig')]
        [Parameter(ParameterSetName = 'SecureToken', Mandatory)]
        [Parameter(ParameterSetName = 'PlainToken',  Mandatory)]
        [string]$BaseUri,

        [Parameter(Mandatory, ParameterSetName = 'SecureToken')]
        [System.Security.SecureString]$Token,

        [Parameter(Mandatory, ParameterSetName = 'PlainToken')]
        [ValidateNotNullOrEmpty()]
        [string]$TokenPlainText
    )

    # Resolve credentials
    if ($PSCmdlet.ParameterSetName -eq 'FromConfig' -and -not $BaseUri) {
        $config = Get-RTConfig
        if (-not $config -or -not $config.BaseUri) {
            throw "No saved configuration found. Run Save-RTConfiguration first."
        }
        $BaseUri = $config.BaseUri

        try {
            $TokenPlainText = Get-Secret -Name 'RTShell_Token' -AsPlainText -ErrorAction Stop
        } catch {
            throw "Could not retrieve 'RTShell_Token' from SecretManagement. Make sure your vault is unlocked or run Save-RTConfiguration to save your token."
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'FromConfig' -and $BaseUri) {
        try {
            $TokenPlainText = Get-Secret -Name 'RTShell_Token' -AsPlainText -ErrorAction Stop
        } catch {
            throw "No token provided and could not retrieve 'RTShell_Token' from SecretManagement."
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'SecureToken') {
        $bstr           = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
        $TokenPlainText = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }

    # Test connectivity
    # Build headers locally for the pre-connect test — the session isn't
    # marked Connected yet, so $Script:RTSession.GetHeaders() would throw.
    $testHeaders = @{
        'Accept'        = 'application/json'
        'Authorization' = "token $TokenPlainText"
    }
    $testUri = "$($BaseUri.TrimEnd('/'))/REST/2.0/queues/all"

    Write-Verbose "Testing connection to $BaseUri ..."
    try {
        $null = Invoke-RestMethod -Uri $testUri -Headers $testHeaders -Method GET -ErrorAction Stop
        Write-Verbose "Connection test succeeded."
    }
    catch {
        throw "Could not connect to RT at '$BaseUri'. Error: $_"
    }

    # Persist session
    $Script:RTSession.Connect($BaseUri, $TokenPlainText)

    $config = Get-RTConfig
    if ($config -and $config.QueueCache -and $config.QueueCache.Count -gt 0) {
        $Script:RTSession.LoadQueueCache($config.QueueCache)
        Write-Verbose "Loaded $($Script:RTSession.QueueCache.Count) queue(s) from cache."
    }
    else {
        Write-Verbose "No queue cache found. Run Update-RTQueueCache to populate it."
    }

    $queueCount = $Script:RTSession.QueueCache.Count
    Write-Host "Connected to RT at $($Script:RTSession.BaseUri)" -ForegroundColor Green
    if ($queueCount -gt 0) {
        Write-Host "  Queues cached : $queueCount (run Update-RTQueueCache to refresh)" -ForegroundColor Gray
    }
    else {
        Write-Host "  Queue cache   : empty -- run Update-RTQueueCache to populate" -ForegroundColor Yellow
    }
}

function Disconnect-RT {
    <#
    .SYNOPSIS
        Clears the current RT session from module state.

    .DESCRIPTION
        Removes the stored base URI, token, and queue cache from memory.
        Saved configuration in ~/.rtshell/ is not affected.

    .EXAMPLE
        Disconnect-RT
    #>
    [CmdletBinding()]
    param()

    $Script:RTSession.Disconnect()
    Write-Host "Disconnected from RT." -ForegroundColor Yellow
}
