function Set-RTTicketPriority {
	<#
    .SYNOPSIS
        Sets the priority of an RT ticket.

    .DESCRIPTION
        Updates the Priority field on a ticket via PATCH /REST/2.0/ticket/{id}.
        RT's default priority range is 0–100, though some instances are
        configured with different scales.

        Confirmation is requested by default, showing the ticket ID, subject,
        current priority, and proposed new priority. Use -Force to suppress.

    .PARAMETER Id
        The ticket ID to update. Accepts pipeline input from Get-RTTicket
        or Search-RTTicket.

    .PARAMETER Priority
        The new numeric priority value (0–100).

    .PARAMETER Force
        Suppress the confirmation prompt and update immediately.

    .PARAMETER PassThru
        Return the updated ticket object after a successful update.

    .EXAMPLE
        Set-RTTicketPriority -Id 12345 -Priority 80

    .EXAMPLE
        Set-RTTicketPriority -Id 12345 -Priority 100 -Force

    .EXAMPLE
        # Elevate priority on all stalled tickets in a queue
        Search-RTTicket -Queue 'HelpDesk' -Status stalled |
            Set-RTTicketPriority -Priority 75 -Force

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
		[ValidateRange(0, 100)]
		[int]$Priority,

		[switch]$Force,

		[switch]$PassThru
	)

	process {
		Write-Verbose "Fetching ticket #$Id"
		$ticket = Get-RTTicket -Id $Id

		$currentPriority = if ($null -ne $ticket.Priority) { $ticket.Priority } else { 'unset' }
		$promptText = "Ticket #$Id — $($ticket.Subject)`nPriority: $currentPriority → $Priority"

		if (-not $Force -and -not $PSCmdlet.ShouldProcess($promptText, 'Set priority')) {
			return
		}

		Write-Verbose "Setting priority on ticket #$Id to $Priority"
		$null = Invoke-RTWriteRequest -Path "ticket/$Id" -Method PATCH -Body @{ Priority = $Priority }

		Write-Host "Ticket #$Id priority set to $Priority." -ForegroundColor Green

		if ($PassThru) {
			Get-RTTicket -Id $Id
		}
	}
}
