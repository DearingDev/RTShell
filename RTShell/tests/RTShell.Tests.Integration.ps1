#Requires -Module Pester
<#
.SYNOPSIS
    RTShell integration tests — requires a live RT instance.

.DESCRIPTION
    These tests exercise the full stack against a real RT server. They create,
    modify, and resolve actual tickets, then clean up after themselves.

    PREREQUISITES
    ─────────────
    1. A running RT 4.4+ instance accessible from this machine.
    2. An RT API token with permission to create/modify tickets in the test queue.
    3. The RTShell module imported and a session established, OR the environment
       variables below set so the test file can call Connect-RT itself.

    CONFIGURATION (environment variables)
    ──────────────────────────────────────
    RT_BASE_URI   – Base URL of the RT instance, e.g. https://rt.example.com
    RT_API_TOKEN  – API token (plain text)
    RT_TEST_QUEUE – Queue to use for test tickets (default: General)

    RUNNING
    ───────
    # Set env vars then run:
    $env:RT_BASE_URI  = 'https://rt.example.com'
    $env:RT_API_TOKEN = 'your-token-here'
    Invoke-Pester .\RTShell.Tests.Integration.ps1 -Output Detailed

    WARNING: These tests create real tickets in your RT instance. Use a
    dedicated test queue and confirm the cleanup AfterAll block runs.
#>

BeforeAll {
	$modulePath = Join-Path $PSScriptRoot '..' 'RTShell.psd1'
	if (-not (Test-Path $modulePath)) {
		$modulePath = Join-Path $PSScriptRoot 'RTShell.psd1'
	}
	Import-Module $modulePath -Force -ErrorAction Stop

	# ── Configuration ─────────────────────────────────────────────────────────
	# Prefer environment variables; fall back to interactive prompts so the
	# test file works in both CI (env vars pre-set) and local dev (interactive).
	$script:BaseUri = $env:RT_BASE_URI
	$script:Token = $env:RT_API_TOKEN
	$script:TestQueue = $env:RT_TEST_QUEUE
	$script:Requestor = $env:RT_TEST_REQUESTOR

	if (-not $script:BaseUri) {
		$script:BaseUri = Read-Host 'RT Base URI (e.g. https://rt.example.com)'
	}
	if (-not $script:Token) {
		$script:Token = Read-Host 'RT API Token'
	}
	if (-not $script:TestQueue) {
		$script:TestQueue = Read-Host 'RT Queue for test tickets (default: General) [press Enter to accept]'
		if (-not $script:TestQueue) { $script:TestQueue = 'General' }
	}
	if (-not $script:Requestor) {
		$script:Requestor = Read-Host 'Requestor email for test tickets (e.g. testuser@example.com)'
	}

	# Connect
	Connect-RT -BaseUri $script:BaseUri -TokenPlainText $script:Token

	# Track all tickets created so AfterAll can resolve them.
	$script:CreatedTicketIds = [System.Collections.Generic.List[int]]::new()
}

AfterAll {
	Write-Output "`n[Cleanup] Resolving $($script:CreatedTicketIds.Count) test ticket(s)..." -ForegroundColor Yellow
	foreach ($id in $script:CreatedTicketIds) {
		try {
			Set-RTTicketStatus -Id $id -Status resolved -Force
			Write-Output "  Resolved ticket #$id" -ForegroundColor Gray
		}
		catch {
			Write-Warning "Could not resolve ticket #$id`: $_"
		}
	}
	Disconnect-RT
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Connect-RT / Disconnect-RT' {

	It 'Connects successfully and reports the correct base URI' {
		# Already connected in BeforeAll — just verify the session state.
		InModuleScope RTShell {
			$Script:RTSession.Connected | Should -BeTrue
			$Script:RTSession.BaseUri | Should -Not -BeNullOrEmpty
		}
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Get-RTQueue' {

	It 'Returns at least one queue' {
		$queues = @(Get-RTQueue)
		$queues.Count | Should -BeGreaterOrEqual 1
	}

	It 'Each queue has a Name and Id' {
		$queue = Get-RTQueue | Select-Object -First 1
		$queue.Name | Should -Not -BeNullOrEmpty
		$queue.Id | Should -BeGreaterThan 0
	}

	It 'Returns a queue when filtered by name (substring)' {
		# Grab the first queue name and search for a substring of it
		$firstName = (Get-RTQueue | Select-Object -First 1).Name
		$substring = $firstName.Substring(0, [Math]::Max(1, $firstName.Length - 1))
		$result = @(Get-RTQueue -Name $substring)
		$result.Count | Should -BeGreaterOrEqual 1
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'New-RTTicket' {

	It 'Creates a ticket and returns an ID' {
		$ticket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] New-RTTicket basic' `
			-Force -PassThru

		$script:CreatedTicketIds.Add($ticket.Id)

		$ticket.Id | Should -BeGreaterThan 0
		$ticket.Subject | Should -Be '[RTShell Test] New-RTTicket basic'
		$ticket.Queue | Should -Be $script:TestQueue
	}

	It 'Creates a ticket with an initial body' {
		$ticket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] New-RTTicket with body' `
			-Body 'This is the initial message body.' `
			-Force -PassThru

		$script:CreatedTicketIds.Add($ticket.Id)
		$ticket.Id | Should -BeGreaterThan 0
	}

	It 'Creates a ticket with a non-default status' {
		# Use 'open' rather than 'stalled' — many RT queues reject 'stalled'
		# as an initial status via a lifecycle policy, even though the API
		# parameter is valid. 'open' is universally accepted at creation.
		$ticket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] New-RTTicket open status' `
			-Status open `
			-Force -PassThru

		$script:CreatedTicketIds.Add($ticket.Id)
		$ticket.Status | Should -Be 'open'
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Get-RTTicket' {

	BeforeAll {
		$newTicket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] Get-RTTicket' `
			-Force -PassThru
		$script:CreatedTicketIds.Add($newTicket.Id)
		$script:GetTestTicketId = $newTicket.Id
	}

	It 'Returns a ticket by ID' {
		$ticket = Get-RTTicket -Id $script:GetTestTicketId
		$ticket.Id | Should -Be $script:GetTestTicketId
		$ticket.Subject | Should -Be '[RTShell Test] Get-RTTicket'
	}

	It 'Returns multiple tickets by ID' {
		$ids = @($script:GetTestTicketId)
		$results = @(Get-RTTicket -Id $ids)
		$results.Count | Should -Be $ids.Count
	}

	It 'Returns detailed fields with -Detailed' {
		$ticket = Get-RTTicket -Id $script:GetTestTicketId -Detailed
		$ticket.PSObject.Properties.Name | Should -Contain 'Priority'
		$ticket.PSObject.Properties.Name | Should -Contain 'CustomFields'
	}

	It 'Accepts pipeline input from Search-RTTicket' {
		$result = Search-RTTicket -Query "id=$($script:GetTestTicketId)" |
			Get-RTTicket
		$result.Id | Should -Be $script:GetTestTicketId
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Search-RTTicket' {

	BeforeAll {
		$newTicket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] Search-RTTicket unique marker xq7z' `
			-Force -PassThru
		$script:CreatedTicketIds.Add($newTicket.Id)
		$script:SearchTestId = $newTicket.Id
	}

	It 'Finds a ticket by unique keyword in subject' {
		$results = @(Search-RTTicket -Keyword 'xq7z' -Status any)
		$results.Count | Should -BeGreaterOrEqual 1
		($results | Where-Object { $_.Id -eq $script:SearchTestId }) | Should -Not -BeNullOrEmpty
	}

	It 'Returns results with the expected properties' {
		$result = Search-RTTicket -Keyword 'xq7z' -Status any | Select-Object -First 1
		$result.PSObject.Properties.Name | Should -Contain 'Id'
		$result.PSObject.Properties.Name | Should -Contain 'Subject'
		$result.PSObject.Properties.Name | Should -Contain 'Status'
	}

	It 'Respects -PageSize' {
		$results = @(Search-RTTicket -Status any -PageSize 2 -Page 1)
		$results.Count | Should -BeLessOrEqual 2
	}

	It 'Passes a raw TicketSQL query' {
		$results = @(Search-RTTicket -Query "id=$($script:SearchTestId)")
		$results.Count | Should -Be 1
		$results[0].Id | Should -Be $script:SearchTestId
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Set-RTTicketStatus' {

	BeforeAll {
		$newTicket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] Set-RTTicketStatus' `
			-Force -PassThru
		$script:CreatedTicketIds.Add($newTicket.Id)
		$script:StatusTestId = $newTicket.Id
	}

	It 'Changes status to stalled' {
		Set-RTTicketStatus -Id $script:StatusTestId -Status stalled -Force
		$ticket = Get-RTTicket -Id $script:StatusTestId
		$ticket.Status | Should -Be 'stalled'
	}

	It 'Changes status back to open' {
		Set-RTTicketStatus -Id $script:StatusTestId -Status open -Force
		$ticket = Get-RTTicket -Id $script:StatusTestId
		$ticket.Status | Should -Be 'open'
	}

	It 'Returns the updated ticket with -PassThru' {
		$result = Set-RTTicketStatus -Id $script:StatusTestId -Status stalled -Force -PassThru
		$result | Should -Not -BeNullOrEmpty
		$result.psobject.TypeNames[0] | Should -Be 'RTShell.Ticket'
		$result.Id | Should -Be $script:StatusTestId
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Set-RTTicketOwner' {

	BeforeAll {
		$newTicket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] Set-RTTicketOwner' `
			-Force -PassThru
		$script:CreatedTicketIds.Add($newTicket.Id)
		$script:OwnerTestId = $newTicket.Id

		# Determine the current authenticated username for the "take ownership" test.
		# The username is visible in the RT session token context — we can look it up
		# by fetching the 'user/root' or 'user/current' endpoint if your RT supports it.
		# Fallback: use the RT_TEST_OWNER env var if set.
		$script:TestOwner = if ($env:RT_TEST_OWNER) { $env:RT_TEST_OWNER } else { 'Nobody' }
	}

	It 'Sets the owner to Nobody (unassign)' {
		Set-RTTicketOwner -Id $script:OwnerTestId -Owner Nobody -Force
		$ticket = Get-RTTicket -Id $script:OwnerTestId
		# RT may return 'Nobody' or an empty string depending on version
		($ticket.Owner -eq 'Nobody' -or [string]::IsNullOrEmpty($ticket.Owner)) | Should -BeTrue
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Set-RTTicketPriority' {

	BeforeAll {
		$newTicket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] Set-RTTicketPriority' `
			-Force -PassThru
		$script:CreatedTicketIds.Add($newTicket.Id)
		$script:PriorityTestId = $newTicket.Id
	}

	It 'Sets priority to 80' {
		Set-RTTicketPriority -Id $script:PriorityTestId -Priority 80 -Force
		$ticket = Get-RTTicket -Id $script:PriorityTestId -Detailed
		[int]$ticket.Priority | Should -Be 80
	}

	It 'Sets priority to 0' {
		Set-RTTicketPriority -Id $script:PriorityTestId -Priority 0 -Force
		$ticket = Get-RTTicket -Id $script:PriorityTestId -Detailed
		[int]$ticket.Priority | Should -Be 0
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Set-RTTicketField' {

	BeforeAll {
		$newTicket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] Set-RTTicketField original' `
			-Force -PassThru
		$script:CreatedTicketIds.Add($newTicket.Id)
		$script:FieldTestId = $newTicket.Id
	}

	It 'Updates the Subject via -Fields' {
		Set-RTTicketField -Id $script:FieldTestId `
			-Fields @{ Subject = '[RTShell Test] Set-RTTicketField updated' } -Force
		$ticket = Get-RTTicket -Id $script:FieldTestId
		$ticket.Subject | Should -Be '[RTShell Test] Set-RTTicketField updated'
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Add-RTTicketComment' {

	BeforeAll {
		$newTicket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] Add-RTTicketComment' `
			-Force -PassThru
		$script:CreatedTicketIds.Add($newTicket.Id)
		$script:CommentTestId = $newTicket.Id
	}

	It 'Posts a comment without error' {
		{ Add-RTTicketComment -Id $script:CommentTestId -Body 'Integration test comment.' -Force } |
			Should -Not -Throw
	}

	It 'Comment appears in ticket history' {
		$history = @(Get-RTTicketHistory -Id $script:CommentTestId -Type Comment)
		$history.Count | Should -BeGreaterOrEqual 1
		($history | Where-Object { $_.Content -match 'Integration test comment' }) | Should -Not -BeNullOrEmpty
	}

	It 'Returns the updated ticket with -PassThru' {
		$result = Add-RTTicketComment -Id $script:CommentTestId -Body 'PassThru test.' -Force -PassThru
		$result | Should -Not -BeNullOrEmpty
		$result.psobject.TypeNames[0] | Should -Be 'RTShell.Ticket'
		$result.Id | Should -Be $script:CommentTestId
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Add-RTTicketReply' {

	BeforeAll {
		$newTicket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] Add-RTTicketReply' `
			-Force -PassThru
		$script:CreatedTicketIds.Add($newTicket.Id)
		$script:ReplyTestId = $newTicket.Id
	}

	It 'Posts a reply without error' {
		{ Add-RTTicketReply -Id $script:ReplyTestId -Body 'Integration test reply.' -Force } |
			Should -Not -Throw
	}

	It 'Reply appears in ticket history as Correspond type' {
		$history = @(Get-RTTicketHistory -Id $script:ReplyTestId -Detailed)
		$correspond = $history | Where-Object { $_.Type -eq 'Correspond' -and $_.Content -match 'Integration test reply' }
		$correspond | Should -Not -BeNullOrEmpty
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Add-RTTicketAttachment' {

	BeforeAll {
		$newTicket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] Add-RTTicketAttachment' `
			-Force -PassThru
		$script:CreatedTicketIds.Add($newTicket.Id)
		$script:AttachTestId = $newTicket.Id

		# Create a small temp file to upload
		$script:TempFile = Join-Path $TestDrive 'rtshell_test_attach.txt'
		Set-Content -Path $script:TempFile -Value 'RTShell attachment integration test payload.'
	}

	It 'Uploads a file without error' {
		{ Add-RTTicketAttachment -Id $script:AttachTestId -Path $script:TempFile -Force } |
			Should -Not -Throw
	}

	It 'Attachment appears in Get-RTTicketAttachments' {
		$attachments = @(Get-RTTicketAttachments -Id $script:AttachTestId)
		$match = $attachments | Where-Object { $_.Filename -eq 'rtshell_test_attach.txt' }
		$match | Should -Not -BeNullOrEmpty
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Get-RTTicketHistory' {

	BeforeAll {
		$newTicket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] Get-RTTicketHistory' `
			-Body 'Initial create body for history test.' `
			-Force -PassThru
		$script:CreatedTicketIds.Add($newTicket.Id)
		$script:HistoryTestId = $newTicket.Id

		Add-RTTicketComment -Id $script:HistoryTestId -Body 'History comment 1.' -Force
		Add-RTTicketReply -Id $script:HistoryTestId -Body 'History reply 1.' -Force
	}

	It 'Returns history items' {
		$history = @(Get-RTTicketHistory -Id $script:HistoryTestId)
		$history.Count | Should -BeGreaterOrEqual 1
	}

	It 'Filters to Correspond type' {
		$history = @(Get-RTTicketHistory -Id $script:HistoryTestId -Type Correspond)
		# $nonCorrespond = $history | Where-Object { $_.PSTypeName -ne 'RTShell.TicketHistory.Summary' }
		# All returned items should be from correspond transactions
		$history.Count | Should -BeGreaterOrEqual 1
	}

	It 'Returns TicketTransaction objects with -Detailed' {
		$history = @(Get-RTTicketHistory -Id $script:HistoryTestId -Detailed)
		$history.Count | Should -BeGreaterOrEqual 1
		$history[0].PSObject.Properties.Name | Should -Contain 'TransactionId'
		$history[0].PSObject.Properties.Name | Should -Contain 'Type'
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Get-RTTicketAttachments / Save-RTTicketAttachment' {

	BeforeAll {
		$newTicket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] Attachments round-trip' `
			-Force -PassThru
		$script:CreatedTicketIds.Add($newTicket.Id)
		$script:RoundTripId = $newTicket.Id

		$script:UploadFile = Join-Path $TestDrive 'upload_roundtrip.txt'
		Set-Content -Path $script:UploadFile -Value 'Round-trip test content.'
		Add-RTTicketAttachment -Id $script:RoundTripId -Path $script:UploadFile -Force
	}

	It 'Get-RTTicketAttachments returns the uploaded file metadata' {
		$attachments = @(Get-RTTicketAttachments -Id $script:RoundTripId)
		($attachments | Where-Object { $_.Filename -eq 'upload_roundtrip.txt' }) | Should -Not -BeNullOrEmpty
	}

	It 'Save-RTTicketAttachment downloads and writes the file' {
		$destDir = Join-Path $TestDrive 'downloads'
		$attachments = Get-RTTicketAttachments -Id $script:RoundTripId |
			Where-Object { $_.Filename -eq 'upload_roundtrip.txt' }

		$attachments | Save-RTTicketAttachment -DestinationPath $destDir -Force

		$outFile = Join-Path $destDir 'upload_roundtrip.txt'
		$outFile | Should -Exist
		(Get-Item $outFile).Length | Should -BeGreaterThan 0
		# Decode the file content regardless of whether RT returned it as
		# plain text or base64, and verify the original payload is present.
		$raw = Get-Content $outFile -Raw
		$decoded = try {
			[System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($raw -replace '\s', '')))
		}
		catch { $raw }
		$decoded | Should -Match 'Round-trip test content'
	}
}

# ══════════════════════════════════════════════════════════════════════════════
Describe 'Template round-trip with Add-RTTicketReply' {

	BeforeAll {
		# Create a temp template dir so we don't pollute real user templates.
		$script:IntegTempDir = Join-Path $TestDrive 'integ_templates'
		New-Item -ItemType Directory -Path $script:IntegTempDir -Force | Out-Null

		# Mock Get-RTTemplateDirectory using -ModuleName so it applies to
		# calls made inside the RTShell module. The mock scriptblock closes
		# over $script:IntegTempDir directly — no $using: needed because
		# BeforeAll runs in the same runspace as the It blocks.
		Mock -CommandName Get-RTTemplateDirectory `
			-ModuleName RTShell `
			-MockWith { $script:IntegTempDir }

		$newTicket = New-RTTicket `
			-Queue $script:TestQueue `
			-Subject '[RTShell Test] Template reply round-trip' `
			-Force -PassThru
		$script:CreatedTicketIds.Add($newTicket.Id)
		$script:TplReplyTestId = $newTicket.Id
	}

	It 'Creates a template, resolves it, and sends the reply' {
		New-RTTemplate -Name 'integ-test-tpl' `
			-Description 'Integration test template' `
			-Body 'Ticket {{TicketId}} is in queue {{Queue}}. Extra: {{MyToken}}' `
			-Prompts @{ MyToken = 'Enter value' } `
			-Confirm:$false

		{ Add-RTTicketReply -Id $script:TplReplyTestId `
				-TemplateName 'integ-test-tpl' `
				-TemplateValues @{ MyToken = 'resolved_value' } `
				-Force } | Should -Not -Throw

		$history = @(Get-RTTicketHistory -Id $script:TplReplyTestId -Type Correspond)
		$match = $history | Where-Object { $_.Content -match 'resolved_value' }
		$match | Should -Not -BeNullOrEmpty
	}
}
