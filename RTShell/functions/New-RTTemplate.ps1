function New-RTTemplate {
	<#
    .SYNOPSIS
        Creates a new response template in the RTShell templates directory.

    .DESCRIPTION
        Writes a named response template to ~/.rtshell/templates/{name}.json.
        The templates directory is created automatically if it does not exist.

        Templates are used by Add-RTTicketReply and Add-RTTicketComment via
        the -TemplateName parameter, and can be shared with others by copying
        the individual .json files.

        Template bodies support {{Token}} placeholders. Automatic tokens are
        resolved from the ticket object at send time:
            {{TicketId}}        Ticket ID
            {{Subject}}         Ticket subject
            {{RequestorName}}   First requestor's first name (from RealName or email local part)
            {{RequestorEmail}}  First requestor's email address
            {{Owner}}           Ticket owner login
            {{Queue}}           Queue name
            {{Status}}          Ticket status

        Additional tokens requiring tech input at send time are declared via
        -Prompts. Each key is a token name and each value is the prompt string
        shown to the tech via Read-Host. In scripted use, values are supplied
        via -TemplateValues on the reply/comment cmdlet instead.

        Throws if a template file with the same name already exists. Use
        Set-RTTemplate to update an existing template.

    .PARAMETER Name
        The key used to reference this template. Must be unique. Lowercase
        with hyphens is recommended (e.g. 'rdp-instructions', 'phishing-report').
        This becomes the filename: ~/.rtshell/templates/{name}.json.

    .PARAMETER Description
        A short description of when to use this template. Displayed by
        Get-RTTemplate to aid discoverability.

    .PARAMETER Body
        The template body text. Supports {{Token}} placeholders.
        Accepts multiline strings.

    .PARAMETER Subject
        Optional subject line override. When supplied and the reply/comment
        cmdlet supports subject changes, this value is resolved and applied.
        Omit entirely if the subject should not change.

    .PARAMETER Prompts
        A hashtable declaring additional token names and the prompt text
        shown to the tech at send time.
        Example: @{ VpnGroup = 'Enter the VPN group name'; HostAddress = 'Enter the RDP host or IP' }

    .EXAMPLE
        New-RTTemplate -Name 'phishing-report' `
            -Description 'Initial response to a reported phishing email' `
            -Body "Hi {{RequestorName}},`n`nThank you for reporting a suspicious email.`nOur security team has been notified and will investigate.`n`nPlease do not click any links in the email.`n`nRegards,`nIT Support"

    .EXAMPLE
        New-RTTemplate -Name 'rdp-instructions' `
            -Description 'RDP setup instructions with VPN and host details' `
            -Body "Hi {{RequestorName}},`n`nTo connect via RDP:`n`n1. Connect to VPN group: {{VpnGroup}}`n2. Open Remote Desktop and connect to: {{HostAddress}}`n`nLet us know if you need further assistance.`n`nRegards,`nIT Support" `
            -Prompts @{ VpnGroup = 'Enter the VPN group name'; HostAddress = 'Enter the RDP host address or IP' }

    .EXAMPLE
        # Create a template with a subject override
        New-RTTemplate -Name 'password-reset' `
            -Description 'Password reset instructions' `
            -Subject 'Re: Password Reset — Action Required' `
            -Body "Hi {{RequestorName}},`n`nPlease use the following link to reset your password: {{ResetLink}}`n`nThis link expires in 24 hours." `
            -Prompts @{ ResetLink = 'Paste the password reset link' }

    .OUTPUTS
        None. Writes confirmation to host on success.
    #>
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Name,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Description,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Body,

		[string]$Subject,

		[hashtable]$Prompts = @{}
	)

	# Resolve template directory and file path
	$templateDir = Get-RTTemplateDirectory
	$templatePath = Join-Path -Path $templateDir -ChildPath "$Name.json"

	# Guard: no overwrite
	if (Test-Path -LiteralPath $templatePath) {
		throw "A template named '$Name' already exists at '$templatePath'. Use Set-RTTemplate to update it."
	}

	# Confirmation
	$promptCount = $Prompts.Count
	$promptText = "Template '$Name' — $Description"
	if ($promptCount -gt 0) {
		$promptText += " ($promptCount prompt token(s): $($Prompts.Keys -join ', '))"
	}

	if (-not $PSCmdlet.ShouldProcess($promptText, 'Create response template')) {
		return
	}

	# Build template object
	$newTemplate = @{
		Name        = $Name
		Description = $Description
		Subject     = if ($PSBoundParameters.ContainsKey('Subject')) { $Subject } else { $null }
		Body        = $Body
		Prompts     = $Prompts
	}

	# Write file
	$newTemplate | ConvertTo-Json -Depth 5 | Set-Content -Path $templatePath -Encoding UTF8

	Write-Host "Response template '$Name' created at '$templatePath'." -ForegroundColor Green

	if ($Prompts.Count -gt 0) {
		Write-Host "  Prompt tokens  : $($Prompts.Keys -join ', ')" -ForegroundColor Gray
	}
	Write-Host "  Use with       : Add-RTTicketReply -TemplateName '$Name'" -ForegroundColor Gray
	Write-Host "                   Add-RTTicketComment -TemplateName '$Name'" -ForegroundColor Gray
}
