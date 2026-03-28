function Invoke-RTRequest {
	<#
    .SYNOPSIS
        Internal helper. Sends an authenticated request to the RT REST v2 API.

    .DESCRIPTION
        Uses Invoke-WebRequest so that JSON deserialization can be performed
        with ConvertFrom-Json -AsHashtable. This preserves key casing, which
        is required because RT's transaction endpoint returns both 'type' (the
        RT object class, e.g. "transaction") and 'Type' (the transaction type,
        e.g. "Correspond") on the same object. 
        
        The resulting hashtable is converted to a PSCustomObject tree by
        ConvertTo-RTObject so all callers can use dot notation. The lowercase
        'type' key is stripped during that pass as it is an RT-internal marker
        never used by any caller.
	.EXAMPLE
		# Get the first page of tickets in the Support queue
		Invoke-RTRequest -Path 'tickets' -QueryParameters @{ Queue = 'Support' }
    #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Path,

		[ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
		[string]$Method = 'GET',

		[hashtable]$Body,

		[hashtable]$QueryParameters
	)

	$Script:RTSession.AssertConnected()

	# Build URI
	$uriBuilder = [System.UriBuilder]("$($Script:RTSession.BaseUri)/REST/2.0/$Path")
	$qsParts = [System.Collections.Generic.List[string]]::new()

	if ($QueryParameters -and $QueryParameters.Count -gt 0) {
		foreach ($key in $QueryParameters.Keys) {
			$qsParts.Add(
				"$([Uri]::EscapeDataString($key))=$([Uri]::EscapeDataString($QueryParameters[$key].ToString()))"
			)
		}
	}

	$uriBuilder.Query = if ($qsParts.Count -gt 0) { $qsParts -join '&' } else { '' }

	# Build request
	$requestHeaders = $Script:RTSession.GetHeaders()

	$invokeParams = @{
		Uri         = $uriBuilder.Uri.AbsoluteUri
		Method      = $Method
		Headers     = $requestHeaders
		ErrorAction = 'Stop'
	}

	if ($Body -and $Method -in 'POST', 'PUT') {
		$invokeParams['Body'] = ($Body | ConvertTo-Json -Depth 10)
		$requestHeaders['Content-Type'] = 'application/json'
	}

	# Execute
	try {
		$response = Invoke-WebRequest @invokeParams

		# Guard against empty body (e.g. RT returns 200 OK with no content
		# on some list endpoints when there are no items).
		if ([string]::IsNullOrWhiteSpace($response.Content)) {
			return [PSCustomObject]@{ items = @(); total = 0; count = 0; page = 1 }
		}

		# Deserialize with -AsHashtable to preserve key casing, then convert
		# the hashtable tree to PSCustomObject so callers use dot notation.
		$parsed = $response.Content | ConvertFrom-Json -AsHashtable
		if ($null -eq $parsed) {
			return [PSCustomObject]@{ items = @(); total = 0; count = 0; page = 1 }
		}
		return ConvertTo-RTObject $parsed
	}
	catch {
		$statusCode = $null
		$detail = $_.Exception.Message
		if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
		if ($_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }

		switch ($statusCode) {
			401 { throw "RT Authentication failed (401). Check your API token." }
			403 { throw "RT Authorization denied (403). Insufficient permissions for: $Path" }
			404 { throw "RT resource not found (404): $Path" }
			default { throw "RT API error $(if ($statusCode) { $statusCode } else { 'unknown' }) for '$Path': $detail" }
		}
	}
}

function ConvertTo-RTObject {
	<#
    .SYNOPSIS
        Internal helper. Recursively converts a hashtable (from
        ConvertFrom-Json -AsHashtable) into a PSCustomObject tree,
        preserving key casing throughout.
    #>
	param(
		# Not Mandatory — null is a valid input (empty fields, empty responses).
		# [Parameter(Mandatory)] validation runs before the function body, so
		# a null guard inside the body would never be reached if Mandatory were set.
		$InputObject
	)

	# Guard: null arrives when RT returns an empty/missing field, or when
	# ConvertFrom-Json yields null for an empty response body.
	if ($null -eq $InputObject) { return $null }

	if ($InputObject -is [System.Collections.Hashtable]) {
		$obj = [PSCustomObject]@{}
		foreach ($key in $InputObject.Keys) {
			# Skip the lowercase 'type' key — it is RT's internal object class
			# marker (e.g. "transaction", "queue", "ticket") and is never used
			# by any caller. The uppercase 'Type' key carries the value we want
			# (e.g. "Correspond", "Status") and is added normally.
			if ($key -ceq 'type') { continue }
			$obj | Add-Member -NotePropertyName $key -NotePropertyValue (ConvertTo-RTObject $InputObject[$key])
		}
		return $obj
	}

	if ($InputObject -is [System.Collections.IList] -and $InputObject -isnot [string]) {
		return @($InputObject | ForEach-Object { ConvertTo-RTObject $_ })
	}

	return $InputObject
}
