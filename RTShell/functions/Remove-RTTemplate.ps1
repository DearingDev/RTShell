function Remove-RTTemplate {
    <#
    .SYNOPSIS
        Removes a response template from the RTShell templates directory.

    .DESCRIPTION
        Deletes the template file ~/.rtshell/templates/{name}.json. This operation
        is permanent — the file cannot be recovered after removal.

        Confirmation is requested by default, displaying the template name and
        description. Use -Force to suppress for scripted use.

    .PARAMETER Name
        The name of the template to remove (without the .json extension).
        Must already exist.

    .PARAMETER Force
        Suppress the confirmation prompt and remove immediately.

    .EXAMPLE
        Remove-RTTemplate -Name 'phishing-report'

    .EXAMPLE
        Remove-RTTemplate -Name 'old-template' -Force

    .OUTPUTS
        None. Writes confirmation to host on success.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [switch]$Force
    )

    process {
        # Resolve template file path
        $templateDir  = Get-RTTemplateDirectory -EnsureExists:$false
        $templatePath = Join-Path -Path $templateDir -ChildPath "$Name.json"

        if (-not (Test-Path -LiteralPath $templatePath)) {
            $available = if (Test-Path -LiteralPath $templateDir) {
                $names = Get-ChildItem -Path $templateDir -Filter '*.json' |
                         ForEach-Object { $_.BaseName } |
                         Sort-Object
                if ($names) { $names -join ', ' } else { '(none)' }
            } else { '(none)' }

            throw "Template '$Name' not found. Available templates: $available"
        }

        # Read description for the confirmation prompt
        $description = $null
        try {
            $t = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json
            $description = $t.Description
        }
        catch {
            Write-Verbose "Could not read description from '$templatePath': $_"
        }

        $promptText = "Template '$Name' — $description"

        # Confirmation
        if ($Force) {
            $PSCmdlet.ShouldProcess($promptText, 'Permanently remove response template') | Out-Null
        }
        elseif (-not $PSCmdlet.ShouldProcess($promptText, 'Permanently remove response template')) {
            return
        }

        # Delete file
        Remove-Item -LiteralPath $templatePath -Force

        Write-Host "Response template '$Name' removed." -ForegroundColor Yellow
    }
}
