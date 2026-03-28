function Save-RTConfig {
    <#
    .SYNOPSIS
        Internal helper. Writes the RTShell config to ~/.rtshell/config.json.

    .DESCRIPTION
        Persists non-secret configuration (BaseUri, queue cache) to disk.
        Response templates are stored separately as individual files under
        ~/.rtshell/templates/ and are not managed by this function.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $rtshellDir    = Join-Path -Path ([System.Environment]::GetFolderPath('UserProfile')) -ChildPath '.rtshell'
    $configPath = Join-Path -Path $rtshellDir -ChildPath 'config.json'

    if (-not (Test-Path $rtshellDir)) {
        New-Item -ItemType Directory -Path $rtshellDir -Force | Out-Null
    }

    $Config | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
    Write-Verbose "Saved config to $configPath"
}
