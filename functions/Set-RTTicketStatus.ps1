function Set-RTTicketStatus {
    <#
    .SYNOPSIS
        Sets the status of an RT ticket.

    .DESCRIPTION
        Updates the Status field on a ticket via PUT /REST/2.0/ticket/{id}.
        Confirmation is requested by default for interactive use. 
        Use -Force to suppress the confirmation prompt.

    .PARAMETER Id
        The ticket ID to update. Accepts pipeline input from Get-RTTicket
        or Search-RTTicket.

    .PARAMETER Status
        The new status value.
        Valid values: new, open, stalled, resolved, rejected, deleted.

    .PARAMETER Force
        Suppress the confirmation prompt and update immediately.

    .PARAMETER PassThru
        Return the updated ticket object after a successful update.

    .EXAMPLE
        Set-RTTicketStatus -Id 12345 -Status resolved

    .EXAMPLE
        Set-RTTicketStatus -Id 12345 -Status stalled -Force

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
        [ValidateSet('new', 'open', 'stalled', 'resolved', 'rejected', 'deleted')]
        [string]$Status,

        [switch]$Force,

        [switch]$PassThru
    )

    process {
        Write-Verbose "Fetching ticket #$Id"
        $ticket = Get-RTTicket -Id $Id

        $promptText = "Ticket #$Id — $($ticket.Subject)`nStatus: $($ticket.Status) → $Status"

        # Logic: If -Force is set, we bypass ShouldProcess
        # This prevents the "Double Prompt" issue when manually passing -Confirm
        # while ConfirmImpact is set to High.
        if (-not $Force -and -not $PSCmdlet.ShouldProcess($promptText, 'Set status')) {
            return
        }

        Write-Verbose "Setting status on ticket #$Id to '$Status'"
        $null = Invoke-RTWriteRequest -Path "ticket/$Id" -Method PUT -Body @{ Status = $Status }

        Write-Host "Ticket #$Id status set to '$Status'." -ForegroundColor Green

        if ($PassThru) {
            Get-RTTicket -Id $Id
        }
    }
}