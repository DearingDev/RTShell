function Set-RTTicketQueue {
	<#
    .SYNOPSIS
        Moves an RT ticket to a different queue.

    .DESCRIPTION
        Updates the Queue field on a ticket via PATCH /REST/2.0/ticket/{id}.
        Confirmation is requested by default, showing the ticket ID, subject,
        current queue, and destination queue. Use -Force to suppress.

    .PARAMETER Id
        The ticket ID to update. Accepts pipeline input from Get-RTTicket
        or Search-RTTicket.

    .PARAMETER Queue
        The name of the destination queue.

    .PARAMETER Force
        Suppress the confirmation prompt and update immediately.

    .PARAMETER PassThru
        Return the updated ticket object after a successful update.

    .PARAMETER WhatIf
        Shows what would happen if the command runs. The command is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the command.

    .EXAMPLE
        Set-RTTicketQueue -Id 12345 -Queue 'Network'

        Move a ticket to a different queue with confirmation.

    .EXAMPLE
        Set-RTTicketQueue -Id 12345 -Queue 'Network' -Force -PassThru

        Move a ticket to a queue without confirmation and return the updated object.

    .EXAMPLE
        Search-RTTicket -Queue 'General' -Keyword 'firewall' |
            Set-RTTicketQueue -Queue 'Network' -Force

        Move all open tickets matching a keyword to a different queue.

    .OUTPUTS
        None by default. With -PassThru, returns a RTShell.Ticket object.
    #>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
	[OutputType([PSCustomObject])]
	param(
		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[Alias('TicketId', 'numerical_id')]
		[int]$Id,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Queue,

		[switch]$Force,

		[switch]$PassThru
	)

	process {
		Write-Verbose "Fetching ticket #$Id"
		$ticket = Get-RTTicket -Id $Id

		$promptText = "Ticket #$Id — $($ticket.Subject)`nQueue: $($ticket.Queue) → $Queue"

		if (-not $Force -and -not $PSCmdlet.ShouldProcess($promptText, 'Move to queue')) {
			return
		}

		Write-Verbose "Moving ticket #$Id to queue '$Queue'"
		$null = Invoke-RTWriteRequest -Path "ticket/$Id" -Method PATCH -Body @{ Queue = $Queue }

		Write-Information "Ticket #$Id moved to queue '$Queue'." -InformationAction Continue

		if ($PassThru) {
			Get-RTTicket -Id $Id
		}
	}
}
