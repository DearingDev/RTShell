function New-RTTicket {
	<#
    .SYNOPSIS
        Creates a new RT ticket.

    .DESCRIPTION
        Posts a new ticket to RT via POST /REST/2.0/ticket. Supports all
        standard ticket fields plus custom fields and an optional initial
        message body.

        Confirmation is requested by default, displaying the queue, subject,
        requestor, and body preview before creation. Use -Force to suppress
        confirmation for scripted use.

        On success the new ticket ID is written to the host. Use -PassThru
        to receive the full ticket object for further pipeline operations.

    .PARAMETER Queue
        The queue to create the ticket in. Required.

    .PARAMETER Subject
        The ticket subject line. Required.

    .PARAMETER Requestor
        One or more requestor email addresses. If omitted, RT assigns the
        authenticated user as the requestor.

    .PARAMETER Body
        Initial message body. Sent as the ticket's first correspondence.
        Optional — some workflows create the ticket then reply separately.

    .PARAMETER Owner
        Username to assign the ticket to on creation. Defaults to Nobody.

    .PARAMETER Cc
        One or more Cc email addresses.

    .PARAMETER AdminCc
        One or more AdminCc email addresses.

    .PARAMETER Priority
        Numeric priority value. RT's default range is 0–100.

    .PARAMETER Status
        Initial ticket status. Defaults to 'new'.
        Common values: new, open, stalled.

    .PARAMETER CustomFields
        A hashtable of custom field name/value pairs to set at creation time.
        Keys should match the field names as defined in RT.
        Example: @{ 'ServiceCategory' = 'Network'; 'Impact' = 'High' }

    .PARAMETER Force
        Suppress the confirmation prompt and create immediately.

    .PARAMETER PassThru
        Return the newly created ticket object.

    .PARAMETER WhatIf
        Shows what would happen if the command runs. The command is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the command.

    .EXAMPLE
        New-RTTicket -Queue 'HelpDesk' -Subject 'VPN not connecting' -Requestor 'jsmith@example.com'

        Create a ticket with minimal required parameters.

    .EXAMPLE
        New-RTTicket -Queue 'HelpDesk' `
                     -Subject 'New starter setup' `
                     -Requestor 'manager@example.com' `
                     -Owner 'jtech' `
                     -Priority 50 `
                     -Body "Please set up accounts for new starter Jane Doe starting Monday."

        Create a ticket with owner assignment, priority, and initial body text.

    .EXAMPLE
        New-RTTicket -Queue 'Network' `
                     -Subject 'Switch port flapping' `
                     -Requestor 'noc@example.com' `
                     -CustomFields @{ 'ServiceCategory' = 'Network'; 'Impact' = 'High' } `
                     -PassThru

        Create a ticket with custom field values and return the new ticket object.

    .EXAMPLE
        New-RTTicket -Queue 'HelpDesk' -Subject 'Password reset' -Requestor 'user@example.com' -Force -PassThru |
            Add-RTTicketReply -TemplateName 'password-reset' -Force

        Create a ticket and immediately send a templated reply in a script.

    .OUTPUTS
        None by default. With -PassThru, returns a RTShell.Ticket object.
    #>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
	[OutputType([PSCustomObject])]
	param(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Queue,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Subject,

		[string[]]$Requestor,

		[string]$Body,

		[string]$Owner,

		[string[]]$Cc,

		[string[]]$AdminCc,

		[ValidateRange(0, 100)]
		[int]$Priority,

		[ValidateSet('new', 'open', 'stalled')]
		[string]$Status = 'new',

		[hashtable]$CustomFields,

		[switch]$Force,

		[switch]$PassThru
	)

	# Confirmation prompt
	$requestorDisplay = if ($Requestor) { $Requestor -join ', ' } else { '(authenticated user)' }
	$bodyPreview = if ($Body) {
		$preview = if ($Body.Length -gt 200) { $Body.Substring(0, 200) + '…' } else { $Body }
		"`nBody preview:`n$preview"
	}
 else { '' }

	$promptText = "Queue: $Queue | Subject: $Subject | Requestor: $requestorDisplay$bodyPreview"

	if (-not $Force -and -not $PSCmdlet.ShouldProcess($promptText, 'Create ticket')) {
		return
	}

	# Build request body
	$requestBody = @{
		Queue   = $Queue
		Subject = $Subject
		Status  = $Status
	}

	if ($Requestor -and $Requestor.Count -gt 0) {
		# RT accepts a single string or an array depending on version.
		# Always send as array for consistency with RT 5.x.
		$requestBody['Requestor'] = $Requestor
	}

	if ($Owner) {
		$requestBody['Owner'] = $Owner
	}

	if ($Cc -and $Cc.Count -gt 0) {
		$requestBody['Cc'] = $Cc
	}

	if ($AdminCc -and $AdminCc.Count -gt 0) {
		$requestBody['AdminCc'] = $AdminCc
	}

	if ($PSBoundParameters.ContainsKey('Priority')) {
		$requestBody['Priority'] = $Priority
	}

	if ($Body) {
		$requestBody['Content'] = $Body
		$requestBody['ContentType'] = 'text/plain'
	}

	# Custom fields are passed as a nested object under 'CustomFields'.
	# RT expects keys as the field name exactly as defined in RT.
	if ($CustomFields -and $CustomFields.Count -gt 0) {
		$requestBody['CustomFields'] = $CustomFields
	}

	# Post
	Write-Verbose "Creating new ticket in queue '$Queue'"
	$response = Invoke-RTWriteRequest -Path 'ticket' -Method POST -Body $requestBody

	# RT returns the new ticket ID in the response. Surface it regardless of
	# -PassThru so the tech always knows what was created.
	$newId = $response.id
	Write-Information "Ticket #$newId created in queue '$Queue'." -InformationAction Continue

	if ($PassThru) {
		Get-RTTicket -Id $newId
	}
}
