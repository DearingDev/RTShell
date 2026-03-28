function Add-RTTicketReply {
    <#
    .SYNOPSIS
        Sends a reply (outbound correspondence) on an RT ticket.

    .DESCRIPTION
        Posts a correspond transaction to the ticket, which sends an email to
        the requestor(s) and any Cc addresses. This is the equivalent of
        clicking "Reply" in the RT web interface.

        Confirmation is requested by default. The prompt displays the ticket ID,
        subject, and a preview of the reply body so the tech can verify before
        sending. Use -Force to suppress confirmation for scripted use.

        Body content can be supplied directly via -Body, piped in as strings,
        or derived from a response template via -TemplateName. When using a
        template, token resolution runs automatically against the ticket. Any
        tokens declared in the template's Prompts map trigger interactive
        Read-Host calls unless -TemplateValues is supplied.

    .PARAMETER Id
        The ticket ID to reply on. Accepts pipeline input from Get-RTTicket
        or Search-RTTicket.

    .PARAMETER Body
        The reply body as a string. Accepts pipeline input by value.
        Newlines are preserved. Cannot be used with -TemplateName.

    .PARAMETER TemplateName
        The key of a response template stored in ~/.rtshell/config.json.
        The template body is resolved against the ticket before sending.
        Cannot be used with -Body.

    .PARAMETER TemplateValues
        A hashtable of token name/value pairs used to satisfy template prompt
        tokens without interactive input. Intended for scripted/pipeline use.
        Example: @{ VpnGroup = 'CORP-VPN'; HostAddress = '10.0.1.50' }

    .PARAMETER Cc
        One or more additional email addresses to copy on this reply.

    .PARAMETER Force
        Suppress the confirmation prompt and send immediately.

    .PARAMETER PassThru
        Return the updated ticket object after a successful reply.

    .EXAMPLE
        Add-RTTicketReply -Id 12345 -Body "Hi, we have resolved your issue."

    .EXAMPLE
        # Pipe body text from a file
        Get-Content .\reply.txt -Raw | Add-RTTicketReply -Id 12345

    .EXAMPLE
        # Use a response template interactively
        Add-RTTicketReply -Id 12345 -TemplateName 'rdp-instructions'

    .EXAMPLE
        # Use a template in a script, supplying prompt values
        Add-RTTicketReply -Id 12345 -TemplateName 'rdp-instructions' `
            -TemplateValues @{ VpnGroup = 'CORP-VPN'; HostAddress = '10.0.1.50' } `
            -Force

    .EXAMPLE
        # Pipeline from search
        Search-RTTicket -Queue 'HelpDesk' -Keyword 'VPN' |
            Get-RTTicket |
            Add-RTTicketReply -TemplateName 'vpn-reset' -Force

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

        [string[]]$Cc,

        [switch]$Force,

        [switch]$PassThru
    )

    process {
        # Fetch ticket for confirmation prompt and token resolution
        Write-Verbose "Fetching ticket #$Id for reply"
        $ticket = Get-RTTicket -Id $Id

        # Resolve body
        if ($PSCmdlet.ParameterSetName -eq 'Template') {
            $Body = Resolve-RTTemplate `
                -TemplateName $TemplateName `
                -Ticket       $ticket `
                -Values       $TemplateValues `
                -Interactive:(-not $Force)
        }

        # Confirmation prompt
        $preview    = if ($Body.Length -gt 200) { $Body.Substring(0, 200) + '…' } else { $Body }
        $promptText = "Ticket #$Id — $($ticket.Subject)`nReply preview:`n$preview"

        if (-not $Force -and -not $PSCmdlet.ShouldProcess($promptText, 'Send reply')) {
            return
        }

        # Build request body
        $requestBody = @{
            Action      = 'correspond'
            Content     = $Body
            ContentType = 'text/plain'
        }

        if ($Cc -and $Cc.Count -gt 0) {
            $requestBody['Cc'] = $Cc -join ', '
        }

        # Post
        Write-Verbose "Posting reply to ticket #$Id"
        $null = Invoke-RTWriteRequest -Path "ticket/$Id/correspond" -Method POST -Body $requestBody

        Write-Host "Reply sent on ticket #$Id." -ForegroundColor Green

        if ($PassThru) {
            Get-RTTicket -Id $Id
        }
    }
}
