function Set-RTTicketField {
	<#
    .SYNOPSIS
        Sets one or more fields on an RT ticket.

    .DESCRIPTION
        Updates any combination of standard or custom fields on a ticket via
        PATCH /REST/2.0/ticket/{id}. Intended as the generic setter for fields
        not covered by the dedicated Set-RTTicket* cmdlets, including all
        custom fields.

        Standard fields (Subject, Owner, Queue, Status, Priority, etc.) can be
        updated here, but the dedicated cmdlets are preferred for those as they
        provide typed validation and clearer confirmation prompts.

        Custom fields are passed under the CustomFields key and must match the
        field names exactly as defined in RT.

        Confirmation is requested by default, listing each field and value to
        be updated. Use -Force to suppress.

    .PARAMETER Id
        The ticket ID to update. Accepts pipeline input from Get-RTTicket
        or Search-RTTicket.

    .PARAMETER Fields
        A hashtable of standard field name/value pairs to update.
        Example: @{ Subject = 'Updated subject'; TimeWorked = 30 }

    .PARAMETER CustomFields
        A hashtable of custom field name/value pairs to update.
        Keys must match field names exactly as defined in RT.
        Example: @{ 'ServiceCategory' = 'Network'; 'Impact' = 'High' }

    .PARAMETER Force
        Suppress the confirmation prompt and update immediately.

    .PARAMETER PassThru
        Return the updated ticket object after a successful update.

    .EXAMPLE
        # Update a standard field
        Set-RTTicketField -Id 12345 -Fields @{ Subject = 'Revised subject line' }

    .EXAMPLE
        # Update a custom field
        Set-RTTicketField -Id 12345 -CustomFields @{ 'ServiceCategory' = 'Network' }

    .EXAMPLE
        # Update both standard and custom fields in one call
        Set-RTTicketField -Id 12345 `
            -Fields       @{ TimeWorked = 60 } `
            -CustomFields @{ 'Impact' = 'High'; 'RootCause' = 'Hardware failure' } `
            -Force -PassThru

    .OUTPUTS
        None by default. With -PassThru, returns a RTShell.Ticket object.
    #>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
	[OutputType([PSCustomObject])]
	param(
		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[Alias('TicketId', 'numerical_id')]
		[int]$Id,

		[hashtable]$Fields,

		[hashtable]$CustomFields,

		[switch]$Force,

		[switch]$PassThru
	)

	process {
		# At least one of -Fields or -CustomFields must be supplied.
		if ((-not $Fields -or $Fields.Count -eq 0) -and (-not $CustomFields -or $CustomFields.Count -eq 0)) {
			$PSCmdlet.ThrowTerminatingError(
				[System.Management.Automation.ErrorRecord]::new(
					[System.ArgumentException]::new("At least one of -Fields or -CustomFields must be provided."),
					'NoFieldsSpecified',
					[System.Management.Automation.ErrorCategory]::InvalidArgument,
					$null
				)
			)
		}

		Write-Verbose "Fetching ticket #$Id"
		$ticket = Get-RTTicket -Id $Id

		# Build confirmation prompt
		$changeLines = [System.Collections.Generic.List[string]]::new()

		if ($Fields -and $Fields.Count -gt 0) {
			foreach ($key in $Fields.Keys) {
				$changeLines.Add("  $key = $($Fields[$key])")
			}
		}

		if ($CustomFields -and $CustomFields.Count -gt 0) {
			foreach ($key in $CustomFields.Keys) {
				$changeLines.Add("  [CF] $key = $($CustomFields[$key])")
			}
		}

		$promptText = "Ticket #$Id — $($ticket.Subject)`nFields to update:`n$($changeLines -join "`n")"

		if (-not $Force -and -not $PSCmdlet.ShouldProcess($promptText, 'Update fields')) {
			return
		}

		# Build request body
		$requestBody = @{}

		if ($Fields -and $Fields.Count -gt 0) {
			foreach ($key in $Fields.Keys) {
				$requestBody[$key] = $Fields[$key]
			}
		}

		if ($CustomFields -and $CustomFields.Count -gt 0) {
			$requestBody['CustomFields'] = $CustomFields
		}

		# Patch
		Write-Verbose "Patching $($requestBody.Count) field(s) on ticket #$Id"
		$null = Invoke-RTWriteRequest -Path "ticket/$Id" -Method PATCH -Body $requestBody

		Write-Host "Ticket #$Id updated." -ForegroundColor Green

		if ($PassThru) {
			Get-RTTicket -Id $Id
		}
	}
}
