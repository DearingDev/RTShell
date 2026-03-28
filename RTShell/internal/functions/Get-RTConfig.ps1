function Get-RTConfig {
	<#
    .SYNOPSIS
        Retrieves the RTShell configuration from the user's profile.

    .DESCRIPTION
        This internal helper function reads the RTShell configuration,
        typically stored in a JSON file within the user's profile directory
        (e.g., ~/.rtshell/config.json). It provides the base URI and other
        settings required for connecting to the RT instance.

        This function does not handle sensitive data like API tokens directly;
        those are managed separately, often via SecretManagement.

    .EXAMPLE
        # Get the current configuration
        $config = Get-RTConfig

    .OUTPUTS
        PSCustomObject. Returns a PSCustomObject representing the RTShell
        configuration, or $null if no configuration is found.
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
