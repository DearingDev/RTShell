function Resolve-RTTemplateTokens {
	<#
    .SYNOPSIS
        Internal helper. Resolves {{Token}} placeholders in a template string
        against a ticket object and optional supplemental values.

    .DESCRIPTION
        Performs token substitution in two passes:

        Pass 1 — Automatic tokens derived from a RTShell.Ticket object:
            {{TicketId}}       Ticket ID
            {{Subject}}        Ticket subject
            {{RequestorName}}  First requestor's First Name (from Real Name or email local part)
            {{RequestorEmail}} First requestor's email address (if distinct from name)
            {{Owner}}          Owner login name
            {{Queue}}          Queue name
            {{Status}}         Ticket status

        Pass 2 — Supplemental tokens from -Values hashtable or interactive
        Read-Host prompts declared in the template's Prompts map.

        Any token that cannot be resolved from either pass is left in place
        as {{Token}} and a warning is written so the tech can address it.

    .PARAMETER Text
        The template string containing {{Token}} placeholders.

    .PARAMETER Ticket
        A RTShell.Ticket object (from Get-RTTicket). Used to resolve automatic
        tokens in Pass 1. Optional — if omitted, Pass 1 is skipped entirely.

    .PARAMETER Prompts
        A hashtable of token-name to prompt-string mappings declared in the
        template definition. Used to drive interactive Read-Host calls for
        any tokens not resolved in Pass 1.

    .PARAMETER Values
        A hashtable of token-name to value mappings supplied by the caller.
        Takes precedence over interactive prompts. Intended for scripted /
        pipeline use where prompts would be disruptive.

    .PARAMETER Interactive
        When set, any token that has a declared Prompt entry but no Value
        will trigger a Read-Host call. When not set (default for scripted
        paths), undeclared/unsupplied tokens fall through to the warn-and-
        leave behavior.

    .OUTPUTS
        [string] The resolved text with substitutions applied.
	.EXAMPLE
		Get-RTTicket -Id 12345 | Resolve-RTTemplate -TemplateName 'followup' -Interactive

		Resolve tokens in template "followup" against ticket #12345, prompting for any undeclared tokens.
    .NOTES
        Token names are case-insensitive. Leading/trailing whitespace inside
        braces is ignored, so {{ TicketId }} and {{TicketId}} both match.
    #>
	[CmdletBinding()]
	[OutputType([string])]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
	param(
		[Parameter(Mandatory)]
		[string]$Text,

		[Parameter()]
		[PSCustomObject]$Ticket,

		[Parameter()]
		[hashtable]$Prompts = @{},

		[Parameter()]
		[hashtable]$Values = @{},

		[Parameter()]
		[switch]$Interactive
	)

	# Build the automatic token map from the ticket object
	# Keys are lowercase for case-insensitive lookup later.
	$autoTokens = @{}

	if ($null -ne $Ticket) {
		# RequestorName / RequestorEmail — RT returns Requestors as a list.
		# We use the first entry for template purposes. We cast to an array 
		# specifically to prevent PowerShell from indexing into a single string 
		# (which would return only the first character).
		$requestorList = @($Ticket.Requestors)
		$firstRequestor = if ($requestorList.Count -gt 0) { $requestorList[0] } else { $null }

		$requestorName = $firstRequestor
		$requestorEmail = $firstRequestor

		if ($firstRequestor) {
			# Attempt a just-in-time lookup to get the RealName from RT
			try {
				# SilentlyContinue ensures we don't break the template if the user lookup fails
				$rtUser = Get-RTUser -Name $firstRequestor -ErrorAction SilentlyContinue
                
				if ($rtUser) {
					if (-not [string]::IsNullOrWhiteSpace($rtUser.RealName)) {
						# Extract just the first name by splitting on whitespace
						$requestorName = ($rtUser.RealName.Trim() -split '\s+')[0]
					}
					elseif ($firstRequestor -match '^[^@]+@[^@]+\.[^@]+$') {
						# Fallback if email: split by @, then optionally split by . for first.last@
						$requestorName = (($firstRequestor -split '@')[0] -split '\.')[0]
					}

					if (-not [string]::IsNullOrWhiteSpace($rtUser.EmailAddress)) {
						$requestorEmail = $rtUser.EmailAddress
					}
				}
				elseif ($firstRequestor -match '^[^@]+@[^@]+\.[^@]+$') {
					# Fallback if user lookup returned empty but it's an email
					$requestorName = (($firstRequestor -split '@')[0] -split '\.')[0]
				}
			}
			catch {
				# Fallback if lookup throws an exception
				if ($firstRequestor -match '^[^@]+@[^@]+\.[^@]+$') {
					$requestorName = (($firstRequestor -split '@')[0] -split '\.')[0]
				}
			}
		}

		$autoTokens['ticketid'] = if ($null -ne $Ticket.Id) { [string]$Ticket.Id }      else { $null }
		$autoTokens['subject'] = if ($Ticket.Subject) { $Ticket.Subject }          else { $null }
		$autoTokens['requestorname'] = $requestorName
		$autoTokens['requestoremail'] = $requestorEmail
		$autoTokens['owner'] = if ($Ticket.Owner) { $Ticket.Owner }            else { $null }
		$autoTokens['queue'] = if ($Ticket.Queue) { $Ticket.Queue }            else { $null }
		$autoTokens['status'] = if ($Ticket.Status) { $Ticket.Status }           else { $null }
	}

	# Normalize -Values keys to lowercase for case-insensitive lookup.
	$normalizedValues = @{}
	foreach ($key in $Values.Keys) {
		$normalizedValues[$key.ToLower()] = $Values[$key]
	}

	# Normalize -Prompts keys to lowercase.
	$normalizedPrompts = @{}
	foreach ($key in $Prompts.Keys) {
		$normalizedPrompts[$key.ToLower()] = $Prompts[$key]
	}

	# Find all unique tokens in the text
	# Pattern: {{ whitespace? TokenName whitespace? }}
	# Token names may contain letters, digits, dots, and hyphens.
	$tokenPattern = '\{\{\s*([\w.\-]+)\s*\}\}'
	$match = [regex]::Matches($Text, $tokenPattern)
	$uniqueTokens = $match |
		ForEach-Object { $_.Groups[1].Value } |
			Select-Object -Unique

	if ($uniqueTokens.Count -eq 0) {
		Write-Verbose "No tokens found in template text."
		return $Text
	}

	Write-Verbose "Found $($uniqueTokens.Count) unique token(s): $($uniqueTokens -join ', ')"

	# Resolve each token
	$resolved = @{}   # token (original case) -> resolved value

	foreach ($token in $uniqueTokens) {
		$keyLower = $token.ToLower()

		# Priority 1: explicit -Values supplied by caller
		if ($normalizedValues.ContainsKey($keyLower)) {
			$resolved[$token] = $normalizedValues[$keyLower]
			Write-Verbose "Token '{{$token}}' resolved from -Values: '$($resolved[$token])'"
			continue
		}

		# Priority 2: automatic ticket-derived tokens
		if ($autoTokens.ContainsKey($keyLower)) {
			$value = $autoTokens[$keyLower]
			if ($null -ne $value) {
				$resolved[$token] = $value
				Write-Verbose "Token '{{$token}}' resolved from ticket: '$value'"
			}
			else {
				# The token is a known automatic token but has no value on this ticket.
				Write-Warning "Token '{{$token}}' is a known automatic token but has no value on ticket #$($Ticket.Id). It will be left in place."
				$resolved[$token] = "{{$token}}"
			}
			continue
		}

		# Priority 3: interactive prompt (only when -Interactive is set)
		if ($Interactive -and $normalizedPrompts.ContainsKey($keyLower)) {
			$promptText = $normalizedPrompts[$keyLower]
			$promptedValue = Read-Host -Prompt $promptText
			$resolved[$token] = $promptedValue
			Write-Verbose "Token '{{$token}}' resolved via prompt: '$promptedValue'"
			continue
		}

		# Priority 4: declared prompt but -Interactive not set, and no -Values supplied.
		# This covers scripted paths where the caller forgot to pass -Values.
		if ($normalizedPrompts.ContainsKey($keyLower)) {
			Write-Warning "Token '{{$token}}' has a declared prompt but -Interactive was not set and no value was supplied via -Values. It will be left in place."
			$resolved[$token] = "{{$token}}"
			continue
		}

		# Fallback: unknown token — warn and leave.
		Write-Warning "Token '{{$token}}' could not be resolved. It will be left in place."
		$resolved[$token] = "{{$token}}"
	}

	# Apply substitutions
	$result = $Text
	foreach ($token in $resolved.Keys) {
		$escapedToken = [regex]::Escape($token)
		$replacePattern = "\{\{\s*$escapedToken\s*\}\}"
		$rx = [regex]::new($replacePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
		$result = $rx.Replace($result, [string]$resolved[$token])
	}

	return $result
}
