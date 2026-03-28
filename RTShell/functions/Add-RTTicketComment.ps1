function Add-RTTicketComment {
	<#
    .SYNOPSIS
        Adds an internal comment to an RT ticket.

    .DESCRIPTION
        Posts a comment transaction to the ticket. Comments are internal notes
        visible only to RT users — no email is sent to the requestor.
        This is the equivalent of clicking "Comment" in the RT web interface.

        Confirmation is requested by default. The prompt displays the ticket ID,
        subject, and a preview of the comment body. Use -Force to suppress
        confirmation for scripted use.

        Body content can be supplied directly via -Body, piped in as strings,
        or derived from a response template via -TemplateName. When using a
        template, token resolution runs automatically against the ticket. Any
        tokens declared in the template's Prompts map trigger interactive
        Read-Host calls unless -TemplateValues is supplied.

    .PARAMETER Id
        The ticket ID to comment on. Accepts pipeline input from Get-RTTicket
        or Search-RTTicket.

    .PARAMETER Body
        The comment body as a string. Accepts pipeline input by value.
        Newlines are preserved. Cannot be used with -TemplateName.

    .PARAMETER TemplateName
        The key of a response template stored in ~/.rtshell/config.json.
        The template body is resolved against the ticket before posting.
        Cannot be used with -Body.

    .PARAMETER TemplateValues
        A hashtable of token name/value pairs used to satisfy template prompt
        tokens without interactive input. Intended for scripted/pipeline use.
        Example: @{ Resolution = 'Replaced NIC'; RootCause = 'Hardware failure' }

    .PARAMETER Force
        Suppress the confirmation prompt and post immediately.

    .PARAMETER PassThru
        Return the updated ticket object after a successful comment.

    .PARAMETER WhatIf
        Shows what would happen if the command runs. The command is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the command.

    .EXAMPLE
        Add-RTTicketComment -Id 12345 -Body "Checked with vendor — part on order."

        Add a simple internal comment to a ticket.

    .EXAMPLE
        Get-Content .\notes.txt -Raw | Add-RTTicketComment -Id 12345

        Pipe comment text from a file to a ticket.

    .EXAMPLE
        Add-RTTicketComment -Id 12345 -TemplateName 'escalation-note'

        Post a comment using a response template with interactive token prompts.

    .EXAMPLE
        Add-RTTicketComment -Id 12345 -Body "Automated check passed." -Force -PassThru

        Add a comment without confirmation and return the updated ticket object.

    .OUTPUTS
        None by default. With -PassThru, returns a RTShell.Ticket object.
    #>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'DirectBody')]
	[OutputType([PSCustomObject])]
	param(
		[Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		[Alias('TicketId', 'numerical_id')]
		[int]$Id,

		[Parameter(Mandatory, ParameterSetName = 'DirectBody', ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[ValidateNotNullOrEmpty()]
		[string]$Body,

		[Parameter(Mandatory, ParameterSetName = 'Template')]
		[ValidateNotNullOrEmpty()]
		[string]$TemplateName,

		[Parameter(ParameterSetName = 'Template')]
		[hashtable]$TemplateValues = @{},

		[switch]$Force,

		[switch]$PassThru
	)

	process {
		# Fetch ticket for confirmation prompt and token resolution
		Write-Verbose "Fetching ticket #$Id for comment"
		$ticket = Get-RTTicket -Id $Id

		# Resolve body
		if ($PSCmdlet.ParameterSetName -eq 'Template') {
			$Body = Resolve-RTTemplate `
				-TemplateName $TemplateName `
				-Ticket $ticket `
				-Values $TemplateValues `
				-Interactive:(-not $Force)
		}

		# Confirmation prompt
		$preview = if ($Body.Length -gt 200) { $Body.Substring(0, 200) + '…' } else { $Body }
		$promptText = "Ticket #$Id — $($ticket.Subject)`nComment preview:`n$preview"

		if (-not $Force -and -not $PSCmdlet.ShouldProcess($promptText, 'Add internal comment')) {
			return
		}

		# Build request body
		$requestBody = @{
			Action      = 'comment'
			Content     = $Body
			ContentType = 'text/plain'
		}

		# Post
		Write-Verbose "Posting internal comment to ticket #$Id"
		$null = Invoke-RTWriteRequest -Path "ticket/$Id/comment" -Method POST -Body $requestBody

		Write-Information "Comment added to ticket #$Id." -InformationAction Continue

		if ($PassThru) {
			Get-RTTicket -Id $Id
		}
	}
}
