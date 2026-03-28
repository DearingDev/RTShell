function Invoke-RTWriteRequest {
	<#
    .SYNOPSIS
        Internal helper. Sends an authenticated write request (POST, PUT,
        DELETE) to the RT REST v2 API.

    .DESCRIPTION
        Companion to Invoke-RTRequest for mutating operations. 

        Note on PATCH: This function originally supported PATCH, but it has been 
        switched to PUT to maximize compatibility with corporate proxies and 
        firewalls that often block the PATCH verb. RT REST v2 treats PUT 
        identically to PATCH for partial ticket updates.

    .PARAMETER Path
        RT REST v2 path, relative to /REST/2.0/. E.g. 'ticket/123/correspond'

    .PARAMETER Method
        HTTP method. Defaults to POST.

    .PARAMETER Body
        Request body as a hashtable. Serialized to JSON automatically.
        Required for POST and PUT. Ignored for DELETE.

    .OUTPUTS
        PSCustomObject — deserialized RT response body, or $null for 204.
	.EXAMPLE
		# Add correspondence to ticket 123
		Invoke-RTWriteRequest -Path 'ticket/123/correspond' -Method 'POST' -Body @{ Text = "This is a comment." }
    #>
	[CmdletBinding()]
	[OutputType([PSCustomObject])]
	param(
		[Parameter(Mandatory)]
		[string]$Path,

		[ValidateSet('POST', 'PUT', 'PATCH', 'DELETE')]
		[string]$Method = 'POST',

		[hashtable]$Body
	)

	$Script:RTSession.AssertConnected()

	# Compatibility Mapping
	# If a caller still passes 'PATCH', we map it to 'PUT' for better 
	# compatibility with infrastructure that blocks the PATCH verb.
	$effectiveMethod = if ($Method -eq 'PATCH') { 'PUT' } else { $Method }

	# Build URI
	$uriBuilder = [System.UriBuilder]("$($Script:RTSession.BaseUri)/REST/2.0/$Path")
	$uriBuilder.Query = ''

	# Build request
	$requestHeaders = $Script:RTSession.GetHeaders()

	$invokeParams = @{
		Uri         = $uriBuilder.Uri.AbsoluteUri
		Method      = $effectiveMethod
		Headers     = $requestHeaders
		ErrorAction = 'Stop'
	}

	if ($Body -and $effectiveMethod -in 'POST', 'PUT') {
		$invokeParams['Body'] = ($Body | ConvertTo-Json -Depth 10)
		$requestHeaders['Content-Type'] = 'application/json'
	}

	# Execute
	try {
		$response = Invoke-WebRequest @invokeParams

		# 204 No Content — success with no body (e.g. DELETE operations).
		if ($response.StatusCode -eq 204) {
			Write-Verbose "RT returned 204 No Content for $effectiveMethod $Path"
			return $null
		}

		# Guard against unexpectedly empty body on other 2xx responses.
		if ([string]::IsNullOrWhiteSpace($response.Content)) {
			Write-Verbose "RT returned $($response.StatusCode) with empty body for $effectiveMethod $Path"
			return $null
		}

		$parsed = $response.Content | ConvertFrom-Json -AsHashtable
		if ($null -eq $parsed) { return $null }
		return ConvertTo-RTObject $parsed
	}
	catch {
		# Extract status code
		$statusCode = $null
		$rtMessage = $null

		if ($_.Exception.Response) {
			$statusCode = [int]$_.Exception.Response.StatusCode
		}

		# Try to extract RT's own error message from the response body
		# RT returns validation errors as JSON: { "message": "...", "errors": [...] }
		$rawBody = $_.ErrorDetails.Message
		if (-not [string]::IsNullOrWhiteSpace($rawBody)) {
			try {
				$errObj = $rawBody | ConvertFrom-Json -AsHashtable
				$parts = [System.Collections.Generic.List[string]]::new()

				if ($errObj.message) { $parts.Add($errObj.message) }
				if ($errObj.errors -and $errObj.errors.Count -gt 0) {
					if ($errObj.errors -is [System.Collections.IList]) {
						foreach ($e in $errObj.errors) { $parts.Add("  - $e") }
					}
					elseif ($errObj.errors -is [System.Collections.Hashtable]) {
						foreach ($field in $errObj.errors.Keys) {
							$parts.Add("  - $field`: $($errObj.errors[$field])")
						}
					}
				}
				if ($parts.Count -gt 0) { $rtMessage = $parts -join "`n" }
			}
			catch {
				$rtMessage = $rawBody
			}
		}

		# Fall back to the .NET exception message if RT gave us nothing useful.
		if ([string]::IsNullOrWhiteSpace($rtMessage)) {
			$rtMessage = $_.Exception.Message
		}

		# Throw a structured, actionable error
		switch ($statusCode) {
			401 { throw "RT Authentication failed (401). Check your API token." }
			403 { throw "RT Authorization denied (403). You do not have permission to perform this operation on: $Path" }
			404 { throw "RT resource not found (404): $Path" }
			409 { throw "RT Conflict (409) on $effectiveMethod $Path — the resource may have been modified concurrently.`n$rtMessage" }
			422 { throw "RT rejected the request (422 Unprocessable Entity) for $effectiveMethod $Path — check field values.`n$rtMessage" }
			501 { throw "The server or a proxy returned 501 Not Implemented. This infrastructure may be blocking HTTP $effectiveMethod.`n$rtMessage" }
			default {
				$code = if ($statusCode) { $statusCode } else { 'unknown' }
				throw "RT API error $code on $effectiveMethod $Path.`n$rtMessage"
			}
		}
	}
}
