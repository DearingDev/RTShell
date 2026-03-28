function Add-RTTicketAttachment {
	<#
    .SYNOPSIS
        Uploads one or more file attachments to an RT ticket.

    .DESCRIPTION
        Posts a comment transaction carrying the file(s) as attachments via
        POST /REST/2.0/ticket/{id}/comment. RT requires attachments to be
        delivered as part of a transaction.

        Files are base64-encoded and embedded in the JSON request body.
        Binary and text files are both supported.

        Confirmation is requested by default, listing the ticket ID, subject,
        and filenames to be uploaded. Use -Force to suppress.

        Note: RT may impose a maximum attachment size limit depending on the
        server configuration.

    .PARAMETER Id
        The ticket ID to attach files to. Accepts pipeline input from
        Get-RTTicket or Search-RTTicket.

    .PARAMETER Path
        One or more file paths to upload. Accepts pipeline input and wildcards.

    .PARAMETER Comment
        Optional comment text to accompany the attachment transaction.
        Visible as an internal note in the ticket history.
        Defaults to 'Attachment uploaded via RTShell.'

    .PARAMETER Force
        Suppress the confirmation prompt and upload immediately.

    .PARAMETER PassThru
        Return the updated ticket object after a successful upload.

    .EXAMPLE
	    # Add a single attachment to ticket 12345.
        Add-RTTicketAttachment -Id 12345 -Path C:\Logs\error.log

    .EXAMPLE
	    # Upload multiple files matching a wildcard pattern, suppressing the confirmation prompt.
        Add-RTTicketAttachment -Id 12345 -Path C:\Reports\*.csv -Force

    .EXAMPLE
		# Pipe file objects from Get-ChildItem to upload them, adding a custom comment.
        Get-ChildItem C:\Captures\*.pcap |
            Add-RTTicketAttachment -Id 12345 -Comment 'Network captures for analysis.' -Force

    .OUTPUTS
        None by default. With -PassThru, returns a RTShell.Ticket object.
    #>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
	[OutputType([PSCustomObject])]
	param(
		[Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		[Alias('TicketId', 'numerical_id')]
		[int]$Id,

		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[Alias('FullName', 'FilePath')]
		[string[]]$Path,

		[string]$Comment = 'Attachment uploaded via RTShell.',

		[switch]$Force,

		[switch]$PassThru
	)

	process {
		# Resolve and validate paths
		$resolvedFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

		foreach ($p in $Path) {
			$expanded = $ExecutionContext.SessionState.Path.GetResolvedProviderPathFromPSPath($p, [ref]$null) 2>$null
			if (-not $expanded) {
				# Try treating as a literal path
				$expanded = [string[]]@($p)
			}
			foreach ($ep in $expanded) {
				if (-not (Test-Path -LiteralPath $ep -PathType Leaf)) {
					Write-Error "File not found or is a directory: $ep"
					continue
				}
				$resolvedFiles.Add([System.IO.FileInfo]$ep)
			}
		}

		if ($resolvedFiles.Count -eq 0) {
			Write-Error "No valid files to upload."
			return
		}

		# Fetch ticket for confirmation prompt
		Write-Verbose "Fetching ticket #$Id"
		$ticket = Get-RTTicket -Id $Id

		$fileList = $resolvedFiles | ForEach-Object { "  $($_.Name) ($([math]::Round($_.Length / 1KB, 1)) KB)" }
		$promptText = "Ticket #$Id — $($ticket.Subject)`nFiles to upload:`n$($fileList -join "`n")"

		if (-not $Force -and -not $PSCmdlet.ShouldProcess($promptText, 'Upload attachment(s)')) {
			return
		}

		# Encode files and build attachment list
		$attachments = [System.Collections.Generic.List[hashtable]]::new()

		foreach ($file in $resolvedFiles) {
			Write-Verbose "Encoding '$($file.Name)' ($($file.Length) bytes)"

			$bytes = [System.IO.File]::ReadAllBytes($file.FullName)
			$encoded = [Convert]::ToBase64String($bytes)
			$contentType = Get-RTFileMimeType -Extension $file.Extension

			$attachments.Add(@{
					FileName    = $file.Name
					FileType    = $contentType
					FileContent = $encoded
				})
		}

		# Build request body
		# RT REST v2 accepts attachments as an array in the comment body.
		$requestBody = @{
			Action      = 'comment'
			Content     = $Comment
			ContentType = 'text/plain'
			Attachments = $attachments.ToArray()
		}

		# Post
		Write-Verbose "Uploading $($resolvedFiles.Count) file(s) to ticket #$Id"
		$null = Invoke-RTWriteRequest -Path "ticket/$Id/comment" -Method POST -Body $requestBody

		$plural = if ($resolvedFiles.Count -eq 1) { 'attachment' } else { 'attachments' }
		Write-Host "$($resolvedFiles.Count) $plural uploaded to ticket #$Id." -ForegroundColor Green

		if ($PassThru) {
			Get-RTTicket -Id $Id
		}
	}
}


function Get-RTFileMimeType {
	<#
    .SYNOPSIS
        Internal helper. Returns a MIME type string for a given file extension.
        Falls back to application/octet-stream for unknown types.
    #>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory)]
		[string]$Extension
	)

	$map = @{
		'.txt'  = 'text/plain'
		'.csv'  = 'text/csv'
		'.html' = 'text/html'
		'.htm'  = 'text/html'
		'.xml'  = 'application/xml'
		'.json' = 'application/json'
		'.pdf'  = 'application/pdf'
		'.zip'  = 'application/zip'
		'.gz'   = 'application/gzip'
		'.tar'  = 'application/x-tar'
		'.log'  = 'text/plain'
		'.md'   = 'text/markdown'
		'.png'  = 'image/png'
		'.jpg'  = 'image/jpeg'
		'.jpeg' = 'image/jpeg'
		'.gif'  = 'image/gif'
		'.svg'  = 'image/svg+xml'
		'.docx' = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
		'.xlsx' = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
		'.pptx' = 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
		'.msg'  = 'application/vnd.ms-outlook'
		'.eml'  = 'message/rfc822'
		'.pcap' = 'application/vnd.tcpdump.pcap'
		'.ps1'  = 'text/plain'
		'.7z'   = 'application/x-7z-compressed'
	}

	$ext = $Extension.ToLower()
	if ($map.ContainsKey($ext)) { return $map[$ext] }
	return 'application/octet-stream'
}
