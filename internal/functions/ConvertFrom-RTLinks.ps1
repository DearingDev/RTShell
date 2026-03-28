function ConvertFrom-RTLinks {
    <#
    .SYNOPSIS
        Internal helper. Flattens RT's hypermedia '_url' fields into plain IDs.

    .DESCRIPTION
        RT REST v2 returns objects with a '_url' field on nested references
        (e.g. Owner, Queue). This helper extracts just the numeric ID from
        those URLs so callers get clean, usable values.

        Input example : https://rt.example.com/REST/2.0/user/42
        Output        : 42
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Url
    )

    process {
        if ($Url -match '/(\d+)$') {
            return [int]$Matches[1]
        }
        return $Url   # Return as-is if no trailing ID found
    }
}
