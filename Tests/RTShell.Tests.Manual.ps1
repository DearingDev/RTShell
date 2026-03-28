<#
.SYNOPSIS
    RTShell manual test script — run top-to-bottom in an interactive session.

.DESCRIPTION
    This script walks through all public cmdlets in a controlled sequence.
    It is intended for human-driven exploratory testing, smoke tests after
    deployment, or testing in environments where Pester cannot be installed.

    Each section is clearly demarcated. You can run the whole file, or
    paste individual sections into a PowerShell session.

    Set the four variables at the top of the file before running.

    IMPORTANT: This script creates real tickets. The final section resolves
    them, but do not skip it.
#>

# ── Configuration ─────────────────────────────────────────────────────────────
$RT_BASE_URI   = $env:RT_BASE_URI       ?? ''
$RT_API_TOKEN  = $env:RT_API_TOKEN      ?? ''
$RT_QUEUE      = $env:RT_TEST_QUEUE     ?? ''
$RT_REQUESTOR  = $env:RT_TEST_REQUESTOR ?? ''

if (-not $RT_BASE_URI) {
    $RT_BASE_URI = Read-Host 'RT Base URI (e.g. https://rt.example.com)'
}

if (-not $RT_API_TOKEN) {
    $RT_API_TOKEN = Read-Host 'RT API Token'
}

if (-not $RT_QUEUE) {
    $RT_QUEUE = Read-Host 'RT Queue for testing (e.g. General)'
}

if (-not $RT_REQUESTOR) {
    $RT_REQUESTOR = Read-Host 'Requestor email for test tickets (e.g. testuser@example.com)'
}

# Track IDs so we can clean up
$createdIds = [System.Collections.Generic.List[int]]::new()

# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════" -ForegroundColor Cyan
Write-Host ' RTShell Manual Test Script'          -ForegroundColor Cyan
Write-Host "═══════════════════════════════════`n" -ForegroundColor Cyan

# ── 0. Import module ──────────────────────────────────────────────────────────
Write-Host '[0] Import-Module' -ForegroundColor Yellow
Import-Module .\RTShell.psd1 -Force
Get-Command -Module RTShell | Measure-Object | ForEach-Object {
    Write-Host "    Loaded $($_.Count) exported commands." -ForegroundColor Gray
}

# ── 1. Connect ────────────────────────────────────────────────────────────────
Write-Host "`n[1] Connect-RT" -ForegroundColor Yellow
Connect-RT -BaseUri $RT_BASE_URI -TokenPlainText $RT_API_TOKEN
# Expected: "Connected to RT at https://..." green message

# ── 2. Queue operations ───────────────────────────────────────────────────────
Write-Host "`n[2] Get-RTQueue — list all" -ForegroundColor Yellow
$queues = @(Get-RTQueue)
$queues | Format-Table Id, Name, Description, Disabled -AutoSize
Write-Host "    Total queues: $($queues.Count)" -ForegroundColor Gray

Write-Host "`n[2b] Get-RTQueue — by name filter" -ForegroundColor Yellow
Get-RTQueue -Name $RT_QUEUE | Format-List

# ── 3. Search (read-only) ─────────────────────────────────────────────────────
Write-Host "`n[3] Search-RTTicket — open tickets in queue" -ForegroundColor Yellow
$openTickets = @(Search-RTTicket -Queue $RT_QUEUE -Status open -PageSize 5)
Write-Host "    Found $($openTickets.Count) open ticket(s) (showing up to 5)" -ForegroundColor Gray
$openTickets | Format-Table Id, Subject, Status, Owner -AutoSize

Write-Host "`n[3b] Search-RTTicket — raw TicketSQL" -ForegroundColor Yellow
$rawResults = @(Search-RTTicket -Query "Queue='$RT_QUEUE' AND Status='open'" -PageSize 3)
Write-Host "    Raw query returned $($rawResults.Count) result(s)" -ForegroundColor Gray

Write-Host "`n[3c] Search-RTTicket — Status=any, all pages" -ForegroundColor Yellow
$allTickets = @(Search-RTTicket -Queue $RT_QUEUE -Status any -All -PageSize 100)
Write-Host "    Total tickets in queue: $($allTickets.Count)" -ForegroundColor Gray

# ── 4. New-RTTicket ───────────────────────────────────────────────────────────
Write-Host "`n[4] New-RTTicket" -ForegroundColor Yellow
$t1 = New-RTTicket -Queue $RT_QUEUE `
    -Subject    '[RTShell Manual Test] Basic ticket' `
    -Requestor  $RT_REQUESTOR `
    -Body       'This ticket was created by the RTShell manual test script.' `
    -Priority 30 `
    -Force -PassThru

$createdIds.Add($t1.Id)
Write-Host "    Created ticket #$($t1.Id): $($t1.Subject)" -ForegroundColor Gray
$t1 | Format-List Id, Subject, Status, Queue, Owner, Priority

# ── 5. Get-RTTicket ───────────────────────────────────────────────────────────
Write-Host "`n[5] Get-RTTicket" -ForegroundColor Yellow
$fetched = Get-RTTicket -Id $t1.Id
$fetched | Format-List

Write-Host "`n[5b] Get-RTTicket -Detailed" -ForegroundColor Yellow
$detailed = Get-RTTicket -Id $t1.Id -Detailed
$detailed | Format-List Id, Subject, Status, Priority, TimeEstimated, CustomFields

# ── 6. Set-RTTicketStatus ─────────────────────────────────────────────────────
Write-Host "`n[6] Set-RTTicketStatus" -ForegroundColor Yellow
Set-RTTicketStatus -Id $t1.Id -Status stalled -Force
$check = Get-RTTicket -Id $t1.Id
Write-Host "    Status is now: $($check.Status)" -ForegroundColor Gray
# Expected: stalled

Set-RTTicketStatus -Id $t1.Id -Status open -Force
$check = Get-RTTicket -Id $t1.Id
Write-Host "    Status restored to: $($check.Status)" -ForegroundColor Gray

# ── 7. Set-RTTicketPriority ───────────────────────────────────────────────────
Write-Host "`n[7] Set-RTTicketPriority" -ForegroundColor Yellow
Set-RTTicketPriority -Id $t1.Id -Priority 85 -Force
$check = Get-RTTicket -Id $t1.Id -Detailed
Write-Host "    Priority is now: $($check.Priority)" -ForegroundColor Gray
# Expected: 85

# ── 8. Set-RTTicketField ──────────────────────────────────────────────────────
Write-Host "`n[8] Set-RTTicketField — update Subject" -ForegroundColor Yellow
Set-RTTicketField -Id $t1.Id -Fields @{ Subject = '[RTShell Manual Test] Updated subject' } -Force
$check = Get-RTTicket -Id $t1.Id
Write-Host "    New subject: $($check.Subject)" -ForegroundColor Gray
# Expected: [RTShell Manual Test] Updated subject

# ── 9. Set-RTTicketOwner ──────────────────────────────────────────────────────
Write-Host "`n[9] Set-RTTicketOwner — unassign" -ForegroundColor Yellow
Set-RTTicketOwner -Id $t1.Id -Owner Nobody -Force
$check = Get-RTTicket -Id $t1.Id
Write-Host "    Owner is now: $($check.Owner)" -ForegroundColor Gray

# ── 10. Add-RTTicketComment ───────────────────────────────────────────────────
Write-Host "`n[10] Add-RTTicketComment" -ForegroundColor Yellow
Add-RTTicketComment -Id $t1.Id -Body "Manual test internal comment — $(Get-Date -Format 'o')" -Force

# ── 11. Add-RTTicketReply ─────────────────────────────────────────────────────
Write-Host "`n[11] Add-RTTicketReply" -ForegroundColor Yellow
Add-RTTicketReply -Id $t1.Id -Body "Manual test outbound reply — $(Get-Date -Format 'o')" -Force

# ── 12. Get-RTTicketHistory ───────────────────────────────────────────────────
Write-Host "`n[12] Get-RTTicketHistory" -ForegroundColor Yellow
$history = @(Get-RTTicketHistory -Id $t1.Id)
Write-Host "    $($history.Count) history item(s)" -ForegroundColor Gray
$history | Sort-Object Created | Format-List Created, CreatorName, Content

Write-Host "`n[12b] Get-RTTicketHistory — Correspond only" -ForegroundColor Yellow
$replies = @(Get-RTTicketHistory -Id $t1.Id -Type Correspond)
Write-Host "    $($replies.Count) outbound reply/replies" -ForegroundColor Gray

Write-Host "`n[12c] Get-RTTicketHistory -Detailed" -ForegroundColor Yellow
$detailedHistory = @(Get-RTTicketHistory -Id $t1.Id -Detailed)
$detailedHistory | Format-Table TransactionId, Type, Created, CreatorName -AutoSize

# ── 13. Response templates ────────────────────────────────────────────────────
Write-Host "`n[13] Response templates — New / Get / Set / Remove" -ForegroundColor Yellow

$tplName = 'manual-test-tpl'

Write-Host "    New-RTTemplate" -ForegroundColor Gray
New-RTTemplate -Name $tplName `
    -Description 'RTShell manual test template' `
    -Body        "Hi {{RequestorName}},`n`nTicket #{{TicketId}} is in queue {{Queue}}.`nCustom: {{MyValue}}" `
    -Prompts     @{ MyValue = 'Enter a custom value' } `
    -Confirm:$false

Write-Host "    Get-RTTemplate (list)" -ForegroundColor Gray
Get-RTTemplate | Format-Table Name, Description, PromptCount -AutoSize

Write-Host "    Get-RTTemplate -Detailed" -ForegroundColor Gray
Get-RTTemplate -Name $tplName -Detailed | Format-List

Write-Host "    Set-RTTemplate — update description" -ForegroundColor Gray
Set-RTTemplate -Name $tplName -Description 'Updated description' -Confirm:$false
Get-RTTemplate -Name $tplName | Format-Table Name, Description

Write-Host "    Add-RTTicketReply with template (scripted -TemplateValues)" -ForegroundColor Gray
Add-RTTicketReply -Id $t1.Id -TemplateName $tplName `
    -TemplateValues @{ MyValue = 'Hello from TemplateValues' } -Force

$history2 = @(Get-RTTicketHistory -Id $t1.Id -Type Correspond)
Write-Host "    History entry count after template reply: $($history2.Count)" -ForegroundColor Gray

Write-Host "    Remove-RTTemplate" -ForegroundColor Gray
Remove-RTTemplate -Name $tplName -Force
$remaining = @(Get-RTTemplate | Where-Object { $_.Name -eq $tplName })
Write-Host "    Template '$tplName' exists after removal: $($remaining.Count -gt 0)" -ForegroundColor Gray
# Expected: False

# ── 14. Add-RTTicketAttachment ────────────────────────────────────────────────
Write-Host "`n[14] Add-RTTicketAttachment" -ForegroundColor Yellow

$tempDir  = [System.IO.Path]::GetTempPath()
$tempFile = Join-Path $tempDir 'rtshell_manual_test.txt'
Set-Content -Path $tempFile -Value "RTShell manual test attachment`nCreated: $(Get-Date)"
Add-RTTicketAttachment -Id $t1.Id -Path $tempFile -Comment 'Uploaded by manual test script' -Force

# ── 15. Get-RTTicketAttachments / Save-RTTicketAttachment ─────────────────────
Write-Host "`n[15] Get-RTTicketAttachments" -ForegroundColor Yellow
$attachments = @(Get-RTTicketAttachments -Id $t1.Id)
Write-Host "    $($attachments.Count) named attachment(s)" -ForegroundColor Gray
$attachments | Format-Table AttachmentId, Filename, ContentType, Created -AutoSize

Write-Host "`n[15b] Save-RTTicketAttachment" -ForegroundColor Yellow
$downloadDir = Join-Path ([System.IO.Path]::GetTempPath()) 'rtshell_downloads'
$attachments | Save-RTTicketAttachment -DestinationPath $downloadDir -Force
Write-Host "    Downloaded to: $downloadDir" -ForegroundColor Gray
Get-ChildItem $downloadDir | Format-Table Name, Length, LastWriteTime -AutoSize

# ── 16. Set-RTTicketQueue (if a second queue exists) ─────────────────────────
Write-Host "`n[16] Set-RTTicketQueue" -ForegroundColor Yellow
$secondQueue = $queues | Where-Object { $_.Name -ine $RT_QUEUE -and -not $_.Disabled } |
               Select-Object -First 1
if ($secondQueue) {
    Write-Host "    Moving ticket to '$($secondQueue.Name)' then back..." -ForegroundColor Gray
    Set-RTTicketQueue -Id $t1.Id -Queue $secondQueue.Name -Force
    Set-RTTicketQueue -Id $t1.Id -Queue $RT_QUEUE        -Force
    Write-Host "    Queue round-trip complete." -ForegroundColor Gray
} else {
    Write-Host "    Only one queue available — skipping queue move test." -ForegroundColor Gray
}

# ── 17. Get-RTUser ────────────────────────────────────────────────────────────
Write-Host "`n[17] Get-RTUser" -ForegroundColor Yellow
# Fetch the owner of the first open ticket if one exists
$ownerName = if ($openTickets -and $openTickets[0].Owner -and $openTickets[0].Owner -ne 'Nobody') {
    $openTickets[0].Owner
} else { $null }

if ($ownerName) {
    Get-RTUser -Name $ownerName | Format-List
    Get-RTUser -Name $ownerName -Detailed | Format-List
} else {
    Write-Host "    No owned tickets found for user lookup test — skipping." -ForegroundColor Gray
}

# ── 18. Pipelining ────────────────────────────────────────────────────────────
Write-Host "`n[18] Pipeline: Search | Get-RTTicket" -ForegroundColor Yellow
$pipeResult = Search-RTTicket -Queue $RT_QUEUE -Status open -PageSize 3 | Get-RTTicket
Write-Host "    Pipeline returned $($pipeResult.Count) full ticket object(s)" -ForegroundColor Gray

Write-Host "`n[18b] Pipeline: Search | Set-RTTicketPriority (on our test ticket only)" -ForegroundColor Yellow
Search-RTTicket -Query "id=$($t1.Id)" |
    Set-RTTicketPriority -Priority 55 -Force
$check = Get-RTTicket -Id $t1.Id -Detailed
Write-Host "    Priority via pipeline: $($check.Priority)" -ForegroundColor Gray

# ── 19. Update-RTQueueCache ───────────────────────────────────────────────────
Write-Host "`n[19] Update-RTQueueCache" -ForegroundColor Yellow
Update-RTQueueCache
Write-Host "    Cache updated." -ForegroundColor Gray

# ── 20. Cleanup ───────────────────────────────────────────────────────────────
Write-Host "`n[20] Cleanup — resolving test tickets" -ForegroundColor Yellow
foreach ($id in $createdIds) {
    Set-RTTicketStatus -Id $id -Status resolved -Force
    Write-Host "    Resolved ticket #$id" -ForegroundColor Gray
}

# ── 21. Disconnect ────────────────────────────────────────────────────────────
Write-Host "`n[21] Disconnect-RT" -ForegroundColor Yellow
Disconnect-RT
# Expected: "Disconnected from RT." yellow message

Write-Host "`n═══════════════════════════════════"  -ForegroundColor Green
Write-Host ' Manual test run complete.'             -ForegroundColor Green
Write-Host "═══════════════════════════════════`n" -ForegroundColor Green

# ── Manual checklist ──────────────────────────────────────────────────────────
Write-Host @'

MANUAL VERIFICATION CHECKLIST
──────────────────────────────
After running this script, verify the following in the RT web interface:

[ ] Ticket created with correct subject and body
[ ] Priority was updated to 85 in history
[ ] Subject was updated via Set-RTTicketField
[ ] An internal comment is visible (not sent to requestor)
[ ] An outbound reply is visible (sent to requestor)
[ ] A templated reply is visible with resolved token values
[ ] The attachment appears under the ticket attachments tab
[ ] The file downloaded locally matches the uploaded content
[ ] The ticket is now in Resolved status

NEGATIVE CASES TO TEST MANUALLY
─────────────────────────────────
[ ] Run Connect-RT without credentials — should throw a clear error
[ ] Run Get-RTTicket -Id 0 — should return a 404 error
[ ] Run New-RTTemplate with a duplicate name — should throw "already exists"
[ ] Run Set-RTTicketField with neither -Fields nor -CustomFields — should throw "NoFieldsSpecified"
[ ] Run Search-RTTicket -PageSize 200 — should fail parameter validation (max 100)
[ ] Run Set-RTTicketPriority -Priority 101 — should fail parameter validation (max 100)
[ ] Run Add-RTTicketAttachment with a nonexistent file — should emit a Write-Error
[ ] Disconnect-RT then run Get-RTTicket — should throw "Not connected"
[ ] Run Save-RTConfiguration with a bad URI, then Connect-RT — should throw a connectivity error
'@