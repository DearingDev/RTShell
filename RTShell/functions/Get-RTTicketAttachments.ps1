function Get-RTTicketAttachments {
	<#
    .SYNOPSIS
        Lists file attachments on an RT ticket.

    .DESCRIPTION
        Retrieves the attachment list for a ticket, filtering out MIME
        structure parts (multipart/mixed, text/html email bodies, etc.)
        and returning only real file attachments -- those with a filename.

    .PARAMETER Id
        The ticket ID to list attachments for.

    .PARAMETER IncludeAll
        Include all attachment parts including MIME structure parts.
        By default only named file attachments are returned.

    .EXAMPLE
        Get-RTTicketAttachments -Id 12345

        List file attachments for a ticket.

    .EXAMPLE
        Get-RTTicketAttachments -Id 12345 | Save-RTTicketAttachment -DestinationPath ~/Downloads/RT

        Download all attachments from a ticket to a local directory.

    .OUTPUTS
        PSCustomObject with attachment metadata per item.
    #>
	[CmdletBinding()]
	[OutputType([PSCustomObject])]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
	param(
		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[Alias('TicketId', 'numerical_id')]
		[int]$Id,

		[switch]$IncludeAll
	)

	process {
		Write-Verbose "Fetching attachments for ticket #$Id"

		$result = Invoke-RTRequest -Path "ticket/$Id/attachments"

		if (-not $result.items -or $result.items.Count -eq 0) {
			Write-Verbose "No attachments found on ticket #$Id"
			return
		}

		foreach ($item in $result.items) {
			$detail = Invoke-RTRequest -Path "attachment/$($item.id)"

			if (-not $IncludeAll -and [string]::IsNullOrWhiteSpace($detail.Filename)) {
				Write-Verbose "Skipping MIME part #$($item.id) ($($detail.ContentType)) -- no filename"
				continue
			}

			[PSCustomObject]@{
				PSTypeName      = 'RTShell.Attachment'
				AttachmentId    = $detail.id
				TicketId        = $Id
				Filename        = $detail.Filename
				ContentType     = $detail.ContentType
				ContentEncoding = $detail.ContentEncoding
				Created         = if ($detail.Created) { [datetime]$detail.Created } else { $null }
				Creator         = $detail.Creator.id
				_Raw            = $detail
			}
		}
	}
}