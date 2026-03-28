function Disconnect-RT {
	<#
    .SYNOPSIS
        Clears the current RT session from module state.

    .DESCRIPTION
        Removes the stored base URI, token, and queue cache from memory.
        Saved configuration in ~/.rtshell/ is not affected.

    .EXAMPLE
        Disconnect-RT
    #>
	[CmdletBinding()]
	param()

	$Script:RTSession.Disconnect()
	Write-Host "Disconnected from RT." -ForegroundColor Yellow
}
