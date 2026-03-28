function Get-RTTemplateDirectory {
	<#
    .SYNOPSIS
        Internal helper. Returns the path to the RTShell templates directory and
        optionally ensures it exists.

    .DESCRIPTION
        The templates directory is always ~/.rtshell/templates/. When -EnsureExists
        is set (the default), the directory is created if it does not exist.
        Pass -EnsureExists:$false for read-only callers that should not create
        the directory as a side effect (e.g. Get-RTTemplate, Remove-RTTemplate).

    .PARAMETER EnsureExists
        When $true (default), creates the directory if absent.
        When $false, returns the path without touching the filesystem.

    .OUTPUTS
        [string] Absolute path to the templates directory.
	.EXAMPLE
		Get-RTTemplateDirectory -EnsureExists:$false

		Returns the templates directory path without creating it if it doesn't exist.
    #>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[bool]$EnsureExists = $true
	)

	$dir = Join-Path -Path ([System.Environment]::GetFolderPath('UserProfile')) -ChildPath '.rtshell' |
		Join-Path -ChildPath 'templates'

	if ($EnsureExists -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
		New-Item -ItemType Directory -Path $dir -Force | Out-Null
		Write-Verbose "Created templates directory: $dir"
	}

	return $dir
}
