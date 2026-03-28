function Save-RTConfiguration {
	<#
    .SYNOPSIS
        Persists the RT base URI and API token to ~/.rtshell/ for use in future
        sessions.

    .DESCRIPTION
        Saves connection details to disk so Connect-RT can be called without
        parameters. Config is stored in:
          ~/.rtshell/config.json  -- BaseUri and queue cache (no secrets)

        Once saved, Connect-RT can be called with no parameters:
          Connect-RT

        To update stored values, run Save-RTConfiguration again with new values.
        To remove stored config, delete ~/.rtshell/ manually.

    .PARAMETER BaseUri
        The root URL of your RT instance, e.g. https://rt.example.com

    .PARAMETER Token
        API token as a SecureString (recommended for interactive use).

    .PARAMETER TokenPlainText
        API token as plain text. Useful for scripting/CI environments.

    .EXAMPLE
        $tok = Read-Host -AsSecureString -Prompt 'RT API Token'
        Save-RTConfiguration -BaseUri 'https://rt.example.com' -Token $tok

        Save configuration using a secure string token.

    .EXAMPLE
        Save-RTConfiguration -BaseUri 'https://rt.example.com' -TokenPlainText $env:RT_TOKEN

        Save configuration using a plain text token from an environment variable.

    .OUTPUTS
        None.
    #>
	[CmdletBinding(DefaultParameterSetName = 'SecureToken')]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
	param(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$BaseUri,

		[Parameter(Mandatory, ParameterSetName = 'SecureToken')]
		[System.Security.SecureString]$Token,

		[Parameter(Mandatory, ParameterSetName = 'PlainToken')]
		[ValidateNotNullOrEmpty()]
		[string]$TokenPlainText
	)

	$BaseUri = $BaseUri.TrimEnd('/')

	# Convert PlainText to SecureString for the SecretManagement module if needed
	if ($PSCmdlet.ParameterSetName -eq 'PlainToken') {
		# PSScriptAnalyzer ignore PSAvoidUsingConvertToSecureStringWithPlainText
		$Token = ConvertTo-SecureString -String $TokenPlainText -AsPlainText -Force
	}

	# Load existing config to preserve queue cache if present
	$existing = Get-RTConfig
	$config = @{
		BaseUri        = $BaseUri
		QueueCache     = if ($existing.QueueCache) { $existing.QueueCache } else { @() }
		QueueCacheDate = if ($existing.QueueCacheDate) { $existing.QueueCacheDate } else { $null }
	}

	# Save non-secret config to disk
	Save-RTConfig -Config $config
    
	# Ensure a vault exists before trying to save
	Initialize-RTSecretVault

	# Save the token to SecretManagement
	Set-Secret -Name 'RTShell_Token' -Secret $Token -NoClobber:$false

	Write-Information "Configuration saved." -InformationAction Continue
	Write-Information "  BaseUri : $BaseUri (saved to ~/.rtshell/config.json)" -InformationAction Continue
	Write-Information "  Token   : saved to SecretManagement vault as 'RTShell_Token'" -InformationAction Continue
}
