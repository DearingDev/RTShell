function Set-RTTemplate {
	<#
    .SYNOPSIS
        Updates an existing response template in the RTShell templates directory.

    .DESCRIPTION
        Modifies one or more fields of a named response template stored at
        ~/.rtshell/templates/{name}.json. Only the parameters explicitly supplied
        are updated — omitted parameters retain their current values.

        To replace the Prompts map entirely, pass a new hashtable via -Prompts.
        To clear all prompts, pass an empty hashtable: -Prompts @{}

        Throws if the named template file does not exist. Use New-RTTemplate to
        create a new template.

    .PARAMETER Name
        The name of the template to update (without the .json extension).
        Must already exist.

    .PARAMETER Description
        New description text. Replaces the existing description.

    .PARAMETER Body
        New body text. Replaces the existing body entirely.
        Supports {{Token}} placeholders.

    .PARAMETER Subject
        New subject line. Pass an empty string to clear the subject override.

    .PARAMETER Prompts
        Replacement Prompts map. Replaces the existing prompts entirely.
        Pass @{} to remove all prompts.

    .EXAMPLE
        # Update only the body
        Set-RTTemplate -Name 'phishing-report' -Body "Hi {{RequestorName}},`n`nUpdated response text..."

    .EXAMPLE
        # Update description and add prompts
        Set-RTTemplate -Name 'rdp-instructions' `
            -Description 'RDP setup — includes VPN group and host' `
            -Prompts @{ VpnGroup = 'Enter the VPN group'; HostAddress = 'Enter the host or IP' }

    .EXAMPLE
        # Clear the subject override
        Set-RTTemplate -Name 'password-reset' -Subject ''

    .OUTPUTS
        None. Writes confirmation to host on success.
    #>
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory, Position = 0)]
		[ValidateNotNullOrEmpty()]
		[string]$Name,

		[string]$Description,

		[string]$Body,

		[string]$Subject,

		[hashtable]$Prompts
	)

	# Resolve template file path
	$templateDir = Get-RTTemplateDirectory -EnsureExists:$false
	$templatePath = Join-Path -Path $templateDir -ChildPath "$Name.json"

	if (-not (Test-Path -LiteralPath $templatePath)) {
		$available = if (Test-Path -LiteralPath $templateDir) {
			$names = Get-ChildItem -Path $templateDir -Filter '*.json' |
				ForEach-Object { $_.BaseName } |
					Sort-Object
			if ($names) { $names -join ', ' } else { '(none)' }
		}
		else { '(none)' }

		throw "Template '$Name' not found. Available templates: $available"
	}

	# Check at least one field is being changed
	$changing = 'Description', 'Body', 'Subject', 'Prompts' |
		Where-Object { $PSBoundParameters.ContainsKey($_) }

	if ($changing.Count -eq 0) {
		Write-Warning "No fields specified to update. Provide at least one of: -Description, -Body, -Subject, -Prompts."
		return
	}

	# Load existing template
	$existing = $null
	try {
		$existing = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json
	}
	catch {
		throw "Could not read template file '$templatePath': $_"
	}

	# Normalise to a plain hashtable so we can safely write back.
	$updated = @{
		Name        = $Name
		Description = $existing.Description
		Subject     = $existing.Subject
		Body        = $existing.Body
		Prompts     = @{}
	}

	# Get existing Prompts from PSCustomObject.
	if ($existing.Prompts) {
		$existing.Prompts |
			Get-Member -MemberType NoteProperty |
				ForEach-Object { $updated.Prompts[$_.Name] = $existing.Prompts.$($_.Name) }
	}

	# Apply changes and build confirmation lines
	$changeLines = [System.Collections.Generic.List[string]]::new()

	if ($PSBoundParameters.ContainsKey('Description')) {
		$changeLines.Add("  Description : '$($updated.Description)' → '$Description'")
		$updated.Description = $Description
	}

	if ($PSBoundParameters.ContainsKey('Body')) {
		$preview = if ($Body.Length -gt 80) { $Body.Substring(0, 80) + '…' } else { $Body }
		$changeLines.Add("  Body        : (replaced) '$preview'")
		$updated.Body = $Body
	}

	if ($PSBoundParameters.ContainsKey('Subject')) {
		$changeLines.Add("  Subject     : '$($updated.Subject)' → '$Subject'")
		$updated.Subject = $Subject
	}

	if ($PSBoundParameters.ContainsKey('Prompts')) {
		$oldKeys = $updated.Prompts.Keys -join ', '
		$newKeys = $Prompts.Keys -join ', '
		$changeLines.Add("  Prompts     : { $oldKeys } → { $newKeys }")
		$updated.Prompts = $Prompts
	}

	# Confirmation
	$promptText = "Template '$Name' ($templatePath):`n$($changeLines -join "`n")"

	if (-not $PSCmdlet.ShouldProcess($promptText, 'Update response template')) {
		return
	}

	# Write back
	$updated | ConvertTo-Json -Depth 5 | Set-Content -Path $templatePath -Encoding UTF8

	Write-Host "Response template '$Name' updated." -ForegroundColor Green
	$changeLines | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
}
