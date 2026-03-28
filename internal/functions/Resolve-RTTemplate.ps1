function Resolve-RTTemplate {
    <#
    .SYNOPSIS
        Internal helper. Loads a named response template from the RTShell templates
        directory and resolves its body tokens against a ticket object.

    .DESCRIPTION
        Reads the template from ~/.rtshell/templates/{name}.json, then delegates
        to Resolve-RTTemplateTokens for two-pass substitution. Returns the
        resolved body string. The caller is responsible for using the result
        as a reply or comment body.

        Throws if the template file does not exist.

    .PARAMETER TemplateName
        Name of the template (without the .json extension).

    .PARAMETER Ticket
        RTShell.Ticket object to resolve automatic tokens against.

    .PARAMETER Values
        Supplemental token values for prompt tokens. Bypasses Read-Host.

    .PARAMETER Interactive
        When set, unresolved prompt tokens trigger Read-Host calls.

    .OUTPUTS
        [string] Resolved template body.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Ticket,

        [hashtable]$Values = @{},

        [switch]$Interactive
    )

    # Resolve template file
    $templateDir  = Get-RTTemplateDirectory -EnsureExists:$false
    $templatePath = Join-Path -Path $templateDir -ChildPath "$TemplateName.json"

    if (-not (Test-Path -LiteralPath $templatePath)) {
        $available = if (Test-Path -LiteralPath $templateDir) {
            $names = Get-ChildItem -Path $templateDir -Filter '*.json' |
                     ForEach-Object { $_.BaseName } |
                     Sort-Object
            if ($names) { $names -join ', ' } else { '(none)' }
        } else { '(none)' }

        throw "Response template '$TemplateName' not found. Available templates: $available"
    }

    $template = $null
    try {
        $template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Could not read template file '$templatePath': $_"
    }

    if ([string]::IsNullOrWhiteSpace($template.Body)) {
        throw "Response template '$TemplateName' has an empty body."
    }

    # Convert Prompts PSCustomObject back to hashtable for the resolver.
    $promptsHash = @{}
    if ($template.Prompts) {
        $template.Prompts |
            Get-Member -MemberType NoteProperty |
            ForEach-Object { $promptsHash[$_.Name] = $template.Prompts.$($_.Name) }
    }

    Resolve-RTTemplateTokens `
        -Text        $template.Body `
        -Ticket      $Ticket `
        -Prompts     $promptsHash `
        -Values      $Values `
        -Interactive:$Interactive
}
