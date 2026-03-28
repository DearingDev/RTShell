function Get-RTTemplate {
    <#
    .SYNOPSIS
        Retrieves one or all response templates from the RTShell templates directory.

    .DESCRIPTION
        Reads response template files from ~/.rtshell/templates/*.json and returns
        them as structured objects. Each template is stored as its own .json file,
        named {templatename}.json.

        When called without parameters, all templates are returned.
        Use -Name to retrieve a specific template by key.

        Templates are displayed with their name, description, whether they
        have prompt tokens, and a truncated body preview. Use -Detailed to
        include the full body and prompt definitions.

    .PARAMETER Name
        The name of a specific template to retrieve (without the .json extension).
        If omitted, all templates are returned.

    .PARAMETER Detailed
        Include the full Body text and Prompts map in the output instead of
        the truncated preview.

    .EXAMPLE
        # List all templates
        Get-RTTemplate

    .EXAMPLE
        # View a specific template
        Get-RTTemplate -Name 'rdp-instructions'

    .EXAMPLE
        # View full body and prompts
        Get-RTTemplate -Name 'rdp-instructions' -Detailed

    .OUTPUTS
        PSCustomObject per template with name, description, prompt count, and
        body preview (or full detail with -Detailed).
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [switch]$Detailed
    )

    $templateDir = Get-RTTemplateDirectory -EnsureExists:$false

    if (-not (Test-Path -LiteralPath $templateDir -PathType Container)) {
        Write-Host "No templates directory found at '$templateDir'. Use New-RTTemplate to create a template." -ForegroundColor Yellow
        return
    }

    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        # Single template by name
        $templatePath = Join-Path -Path $templateDir -ChildPath "$Name.json"

        if (-not (Test-Path -LiteralPath $templatePath)) {
            $available = Get-ChildItem -Path $templateDir -Filter '*.json' |
                         ForEach-Object { $_.BaseName } |
                         Sort-Object
            $availableStr = if ($available) { $available -join ', ' } else { '(none)' }
            throw "Template '$Name' not found. Available templates: $availableStr"
        }

        $files = @(Get-Item -LiteralPath $templatePath)
    }
    else {
        # All templates
        $files = @(Get-ChildItem -Path $templateDir -Filter '*.json' | Sort-Object Name)

        if ($files.Count -eq 0) {
            Write-Host "No response templates are configured. Use New-RTTemplate to create one." -ForegroundColor Yellow
            return
        }
    }

    foreach ($file in $files) {
        $t = $null
        try {
            $t = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        }
        catch {
            Write-Warning "Could not parse template file '$($file.FullName)': $_"
            continue
        }

        # Normalise Prompts back to a hashtable for consistent output.
        # ConvertFrom-Json deserialises nested objects as PSCustomObject.
        $promptsHash = @{}
        if ($t.Prompts) {
            $t.Prompts |
                Get-Member -MemberType NoteProperty |
                ForEach-Object { $promptsHash[$_.Name] = $t.Prompts.$($_.Name) }
        }

        $promptCount = $promptsHash.Count
        $bodyPreview = if ($t.Body -and $t.Body.Length -gt 120) {
            $t.Body.Substring(0, 120) + '…'
        } else { $t.Body }

        # Use the filename stem as the canonical Name.
        $templateName = $file.BaseName

        if ($Detailed) {
            [PSCustomObject]@{
                PSTypeName  = 'RTShell.ResponseTemplate'
                Name        = $templateName
                Description = $t.Description
                Subject     = $t.Subject
                Body        = $t.Body
                Prompts     = $promptsHash
                PromptCount = $promptCount
                FilePath    = $file.FullName
            }
        }
        else {
            [PSCustomObject]@{
                PSTypeName  = 'RTShell.ResponseTemplate'
                Name        = $templateName
                Description = $t.Description
                Subject     = $t.Subject
                PromptCount = $promptCount
                BodyPreview = $bodyPreview
                FilePath    = $file.FullName
            }
        }
    }
}
