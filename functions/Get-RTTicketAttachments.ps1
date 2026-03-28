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

    .EXAMPLE
        Get-RTTicketAttachments -Id 12345 | Save-RTTicketAttachment -DestinationPath ~/Downloads/RT

    .OUTPUTS
        PSCustomObject with attachment metadata per item.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('TicketId','numerical_id')]
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


function Save-RTTicketAttachment {
    <#
    .SYNOPSIS
        Downloads an RT ticket attachment to disk.

    .DESCRIPTION
        Fetches the content of an attachment from GET /REST/2.0/attachment/{id}
        and writes it to the specified destination folder. Content is decoded
        from base64 for binary files automatically.

    .PARAMETER AttachmentId
        The RT attachment ID. Sourced from Get-RTTicketAttachments output.

    .PARAMETER Filename
        Output filename. Defaults to the original filename from RT.

    .PARAMETER ContentEncoding
        Content encoding hint from the attachment record. Used to determine
        whether base64 decoding is needed.

    .PARAMETER DestinationPath
        Folder where the file will be saved. Created if it does not exist.
        Defaults to the current directory.

    .PARAMETER Force
        Overwrite an existing file with the same name.

    .EXAMPLE
        Get-RTTicketAttachments -Id 12345 | Save-RTTicketAttachment -DestinationPath ~/Downloads/RT

    .OUTPUTS
        System.IO.FileInfo for each file written.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [int]$AttachmentId,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Filename,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ContentEncoding,

        [string]$DestinationPath = '.',

        [switch]$Force
    )

    process {
        # Resolve ~ and relative paths -- [System.IO.File] is a .NET method and
        # does not understand PowerShell path syntax like ~ or relative segments.
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)

        if (-not (Test-Path -Path $resolvedPath -PathType Container)) {
            Write-Verbose "Creating destination folder: $resolvedPath"
            New-Item -ItemType Directory -Path $resolvedPath -Force | Out-Null
        }

        if ([string]::IsNullOrWhiteSpace($Filename)) {
            $Filename = "attachment_$AttachmentId"
        }

        $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
        $safeFilename = $Filename -replace "[$([regex]::Escape([string]$invalidChars))]", '_'
        $outPath      = Join-Path -Path $resolvedPath -ChildPath $safeFilename

        if ((Test-Path $outPath) -and -not $Force) {
            Write-Warning "File already exists: $outPath. Use -Force to overwrite."
            return
        }

        if ($PSCmdlet.ShouldProcess($outPath, "Save attachment $AttachmentId")) {
            Write-Verbose "Downloading attachment #$AttachmentId -> $outPath"

            $detail     = Invoke-RTRequest -Path "attachment/$AttachmentId"
            $rawContent = $detail.Content

            if ([string]::IsNullOrEmpty($rawContent)) {
                Write-Warning "Attachment #$AttachmentId has no content."
                return
            }

            # Use ContentType to decide encoding rather than heuristics.
            # Binary types (PDF, images, Office docs, zip, etc.) are always
            # base64 in RT. Plain text types are returned as UTF-8 strings.
            $textTypes = 'text/plain','text/html','text/csv','application/json','application/xml'
            $isText    = $detail.ContentType -and ($textTypes | Where-Object { $detail.ContentType -like "$_*" })

            if (-not $isText) {
                try {
                    $bytes = [Convert]::FromBase64String(($rawContent -replace '\s',''))
                    [System.IO.File]::WriteAllBytes($outPath, $bytes)
                    Write-Verbose "Wrote $($bytes.Length) bytes (base64 decoded binary)"
                }
                catch {
                    throw "Failed to base64 decode attachment #$AttachmentId ($($detail.ContentType)): $_"
                }
            }
            else {
                $textContent = $rawContent
                if ($detail.ContentEncoding -in 'base64','base64url') {
                    $bytes       = [Convert]::FromBase64String(($rawContent -replace '\s',''))
                    $textContent = [System.Text.Encoding]::UTF8.GetString($bytes)
                }
                [System.IO.File]::WriteAllText($outPath, $textContent, [System.Text.Encoding]::UTF8)
                Write-Verbose "Wrote as text ($($detail.ContentType))"
            }

            Get-Item -Path $outPath
        }
    }
}
