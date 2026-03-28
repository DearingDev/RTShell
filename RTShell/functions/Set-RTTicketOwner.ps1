function Set-RTTicketOwner {
	<#
    .SYNOPSIS
        Sets the owner of an RT ticket.

    .DESCRIPTION
        Updates the Owner field on a ticket via PATCH /REST/2.0/ticket/{id}.
        Accepts any valid RT username. Pass 'Nobody' to unassign the ticket.

        Confirmation is requested by default, showing the ticket ID, subject,
        current owner, and proposed new owner. Use -Force to suppress.

    .PARAMETER Id
        The ticket ID to update. Accepts pipeline input from Get-RTTicket
        or Search-RTTicket.

    .PARAMETER Owner
        The RT username to assign as owner. Use 'Nobody' to unassign.

    .PARAMETER Force
        Suppress the confirmation prompt and update immediately.

    .PARAMETER PassThru
        Return the updated ticket object after a successful update.

    .PARAMETER WhatIf
        Shows what would happen if the command runs. The command is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the command.

    .EXAMPLE
        Set-RTTicketOwner -Id 12345 -Owner jsmith

        Assign a ticket to a user with confirmation.

    .EXAMPLE
        Set-RTTicketOwner -Id 12345 -Owner $env:USERNAME -Force

        Take ownership of a ticket using the current user's name.

    .EXAMPLE
        Set-RTTicketOwner -Id 12345 -Owner Nobody

        Unassign a ticket (set owner to Nobody).

    .EXAMPLE
        Search-RTTicket -Queue 'HelpDesk' -Owner Nobody |
            Set-RTTicketOwner -Owner jsmith -Force

        Assign all unowned tickets in a queue to a specific technician.

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
		[string]$Owner,

		[switch]$Force,

		[switch]$PassThru
	)

	process {
		Write-Verbose "Fetching ticket #$Id"
		$ticket = Get-RTTicket -Id $Id

		$currentOwner = if ($ticket.Owner) { $ticket.Owner } else { 'Nobody' }
		$promptText = "Ticket #$Id — $($ticket.Subject)`nOwner: $currentOwner → $Owner"

		if (-not $Force -and -not $PSCmdlet.ShouldProcess($promptText, 'Set owner')) {
			return
		}

		Write-Verbose "Setting owner on ticket #$Id to '$Owner'"
		$null = Invoke-RTWriteRequest -Path "ticket/$Id" -Method PATCH -Body @{ Owner = $Owner }

		Write-Information "Ticket #$Id owner set to '$Owner'." -InformationAction Continue

		if ($PassThru) {
			Get-RTTicket -Id $Id
		}
	}
}
