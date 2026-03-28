function Get-RTConfig {
    <#
    .SYNOPSIS
        Internal helper. Reads the RTShell config file from ~/.rtshell/config.json.
    #>
    [CmdletBinding()]
    param()

    $configPath = Join-Path -Path ([System.Environment]::GetFolderPath('UserProfile')) -ChildPath '.rtshell' |
                  Join-Path -ChildPath 'config.json'

    if (-not (Test-Path $configPath)) {
        return $null
    }

    try {
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
        return $config
    }
    catch {
        Write-Warning "Could not read RTShell config at '$configPath': $_"
        return $null
    }
}
