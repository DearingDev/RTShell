# RTShell — PowerShell Module for Request Tracker (REST API v2)

A PowerShell module for interfacing with [Request Tracker (RT)](https://bestpractical.com/rt) using its REST API v2 and API token authentication. Supports read operations, write operations (tickets, replies, comments, attachments), and a response template system for standardized communications.

---

## Requirements

- PowerShell 5.1 or later (Windows PowerShell or PowerShell 7+)
- An RT instance running RT 4.4+ (REST v2 support)
- An RT API token
- `Microsoft.PowerShell.SecretManagement` module (for credential persistence)

> **PowerShell 7+ Note:** `Get-RTTicketHistory` fetches transaction details in parallel on PS 7+, significantly reducing wall-clock time on tickets with long histories.

---

## Installation

Copy the `RTShell` folder to a directory on your `$env:PSModulePath`, then import:

```powershell
Import-Module RTShell
```

---

## Generating an API Token

1. Log in to your RT instance
2. Click your username → **Settings** → **Auth Tokens**
3. Click **Generate New Token**, give it a description
4. Copy the token — RT only shows it once

---

## Quick Start

### First-time setup

```powershell
Import-Module RTShell

# Save your credentials so Connect-RT works without parameters in future sessions
$tok = Read-Host -AsSecureString -Prompt 'RT API Token'
Save-RTConfiguration -BaseUri 'https://rt.example.com' -Token $tok

# Connect
Connect-RT
```

### Subsequent sessions

```powershell
Connect-RT   # Loads saved credentials automatically
```

### Override saved config (useful for CI/CD)

```powershell
Connect-RT -BaseUri 'https://rt.example.com' -TokenPlainText $env:RT_TOKEN
```

---

## Cmdlet Reference

### Session Management

#### `Connect-RT`
Establishes an authenticated session. Must be called before any other cmdlet.

| Parameter | Type | Description |
|-----------|------|-------------|
| `-BaseUri` | String | RT base URL, e.g. `https://rt.example.com` |
| `-Token` | SecureString | API token (interactive use) |
| `-TokenPlainText` | String | API token as plain text (scripting/CI) |

When called with no parameters, loads `BaseUri` from `~/.rtshell/config.json` and the token from the registered SecretManagement vault.

#### `Disconnect-RT`
Clears the session from module memory. Does not affect saved config on disk.

#### `Save-RTConfiguration`
Persists the RT base URI and API token for use in future sessions.

| Parameter | Type | Description |
|-----------|------|-------------|
| `-BaseUri` | String | RT base URL |
| `-Token` | SecureString | API token (interactive use) |
| `-TokenPlainText` | String | API token as plain text (scripting/CI) |

The base URI is stored in `~/.rtshell/config.json`. The token is stored securely via `Microsoft.PowerShell.SecretManagement`. If no vault is registered, `Save-RTConfiguration` will offer to install and configure `Microsoft.PowerShell.SecretStore` automatically.

#### `Update-RTQueueCache`
Fetches all queues from the RT server and stores them in `~/.rtshell/config.json`. Run this after queues are added, renamed, or disabled in RT. The cache is loaded automatically on `Connect-RT`.

---

### Reading Tickets

#### `Search-RTTicket`
Search for tickets using structured parameters or a raw TicketSQL query string.

**Structured search parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Status` | `open` | One or more status values. Pass `any` to match all statuses. |
| `-Queue` | | One or more queue names. |
| `-Owner` | | Filter by owner username. Use `Nobody` for unassigned. |
| `-Requestor` | | Filter by requestor email or username. |
| `-Keyword` | | One or more phrases to match against the Subject. Multiple values default to AND logic. |
| `-IncludeContent` | | Also search message body content when used with `-Keyword`. |
| `-MatchAny` | | Use OR logic across multiple `-Keyword` values instead of AND. |

**Shared parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Query` | | Raw TicketSQL query string. Overrides all structured parameters. |
| `-OrderBy` | `id` | Field to sort by. |
| `-Order` | `DESC` | `ASC` or `DESC`. |
| `-Page` | `1` | Page number. |
| `-PageSize` | `50` | Results per page (max 100). |
| `-All` | | Fetch all pages automatically. |

```powershell
# Structured search examples
Search-RTTicket                                                     # All open tickets
Search-RTTicket -Queue 'HelpDesk'                                   # Open tickets in a queue
Search-RTTicket -Status new, open, stalled -Owner jsmith            # By status and owner
Search-RTTicket -Keyword 'VPN'                                      # Keyword in subject
Search-RTTicket -Keyword '"Power Automate Premium"'                   # Phrase search
Search-RTTicket -Keyword 'VPN', 'timeout'                           # AND across two terms
Search-RTTicket -Keyword 'VPN', 'timeout' -MatchAny                 # OR across two terms
Search-RTTicket -Keyword 'VPN' -IncludeContent                      # Search body too
Search-RTTicket -Requestor 'user@example.com' -Status any           # All statuses
Search-RTTicket -Keyword 'network' -Status any -All                 # All pages

# Raw TicketSQL if you're brave
Search-RTTicket -Query "Queue='Network' AND Priority >= 50 AND Created > '2026-01-01'"
```

**TicketSQL Quick Reference:**

| Operator | Example |
|----------|---------|
| Equals | `Status='open'` |
| Not equals | `Status!='resolved'` |
| Contains | `Subject LIKE 'error'` |
| Date comparison | `Created > '2026-01-01'` |
| AND / OR | `Queue='A' AND Status='open'` |
| Numeric comparison | `Priority >= 50` |

**Valid status values:** `new`, `open`, `stalled`, `resolved`, `rejected`, `deleted`

#### `Get-RTTicket`
Retrieve full ticket metadata by ID. Accepts pipeline input from `Search-RTTicket`.

| Parameter | Description |
|-----------|-------------|
| `-Id` | One or more ticket IDs. |
| `-Detailed` | Include priority, time tracking, Cc/AdminCc, custom fields, and the raw API response. |

```powershell
Get-RTTicket -Id 12345
Get-RTTicket -Id 100, 101, 102
Get-RTTicket -Id 12345 -Detailed
Search-RTTicket -Queue 'HelpDesk' | Get-RTTicket
```

#### `Get-RTTicketHistory`
Retrieve the transaction history for a ticket (replies, comments, status changes).

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Id` | _(required)_ | Ticket ID. |
| `-Type` | | Filter to one transaction type: `Correspond`, `Comment`, `Create`, etc. |
| `-Detailed` | | Include all transaction types and return full `RTShell.TicketTransaction` objects. |
| `-Raw` | | Skip HTML stripping and quoted-reply removal. |
| `-ThrottleLimit` | `5` | PS 7+ only. Max concurrent API requests. |
| `-Page` | `1` | Page number for the history list. |
| `-PageSize` | `50` | Results per page (max 100). |

```powershell
Get-RTTicketHistory -Id 12345
Get-RTTicketHistory -Id 12345 -Type Correspond
Get-RTTicketHistory -Id 12345 -Detailed
Get-RTTicketHistory -Id 12345 | Sort-Object Created | Format-List Created, CreatorName, Content
```

#### `Get-RTTicketAttachments`
List file attachments on a ticket (metadata only — no download).

| Parameter | Description |
|-----------|-------------|
| `-Id` | Ticket ID. |
| `-IncludeAll` | Include MIME structure parts, not just named file attachments. |

#### `Save-RTTicketAttachment`
Download an attachment to disk. Accepts pipeline input from `Get-RTTicketAttachments`.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-AttachmentId` | _(required)_ | RT attachment ID. |
| `-Filename` | RT filename | Output filename. |
| `-DestinationPath` | `.` | Folder to save into. Created if absent. |
| `-Force` | | Overwrite existing files. |

```powershell
# List and download all attachments from a ticket
Get-RTTicketAttachments -Id 12345 |
    Save-RTTicketAttachment -DestinationPath ~/Downloads/RT -Force
```

---

### Reading Queues and Users

#### `Get-RTQueue`
List all queues or retrieve a specific queue by ID or name.

```powershell
Get-RTQueue                  # All queues
Get-RTQueue -Id 3            # By ID
Get-RTQueue -Name 'HelpDesk' # Filter by name (substring match)
```

#### `Get-RTUser`
Look up an RT user by numeric ID, login name, or email address.

| Parameter | Description |
|-----------|-------------|
| `-Id` | Numeric RT user ID. |
| `-Name` | Login name or email address. |
| `-Detailed` | Return all fields including address, phone, organization, and account status. |

```powershell
Get-RTUser -Name jsmith
Get-RTUser -Name jsmith@example.com
Get-RTUser -Id 42 -Detailed

# Resolve the owner of a ticket
$ticket = Get-RTTicket -Id 12345
Get-RTUser -Name $ticket.Owner
```

---

### Writing Tickets

All write cmdlets support `-Force` to suppress the confirmation prompt and `-PassThru` to return the updated ticket object for further pipeline operations.

#### `New-RTTicket`
Create a new RT ticket.

| Parameter | Description |
|-----------|-------------|
| `-Queue` | _(required)_ Queue name. |
| `-Subject` | _(required)_ Ticket subject. |
| `-Requestor` | One or more requestor email addresses. |
| `-Body` | Initial message body. |
| `-Owner` | Username to assign on creation. |
| `-Cc` | One or more Cc email addresses. |
| `-AdminCc` | One or more AdminCc email addresses. |
| `-Priority` | Numeric priority (0–100). |
| `-Status` | Initial status: `new` (default), `open`, `stalled`. |
| `-CustomFields` | Hashtable of custom field name/value pairs. |

```powershell
# Basic ticket
New-RTTicket -Queue 'HelpDesk' -Subject 'VPN not connecting' -Requestor 'jsmith@example.com'

# With body and owner
New-RTTicket -Queue 'HelpDesk' `
             -Subject 'New starter setup' `
             -Requestor 'manager@example.com' `
             -Owner 'jtech' `
             -Priority 50 `
             -Body "Please set up accounts for new starter Jane Doe starting Monday."

# With custom fields
New-RTTicket -Queue 'Network' `
             -Subject 'Switch port flapping' `
             -Requestor 'noc@example.com' `
             -CustomFields @{ 'ServiceCategory' = 'Network'; 'Impact' = 'High' } `
             -PassThru

# Create then immediately reply using a template
New-RTTicket -Queue 'HelpDesk' -Subject 'Password reset' -Requestor 'user@example.com' -Force -PassThru |
    Add-RTTicketReply -TemplateName 'password-reset' -Force
```

#### `Set-RTTicketStatus`
Set the status on a ticket.

Valid values: `new`, `open`, `stalled`, `resolved`, `rejected`, `deleted`

```powershell
Set-RTTicketStatus -Id 12345 -Status resolved
Set-RTTicketStatus -Id 12345 -Status stalled -Force
```

#### `Set-RTTicketOwner`
Set or change the owner of a ticket. Pass `Nobody` to unassign.

```powershell
Set-RTTicketOwner -Id 12345 -Owner jsmith
Set-RTTicketOwner -Id 12345 -Owner $env:USERNAME -Force   # Take ownership
Set-RTTicketOwner -Id 12345 -Owner Nobody                 # Unassign

# Assign all unowned open tickets in a queue
Search-RTTicket -Queue 'HelpDesk' -Owner Nobody |
    Set-RTTicketOwner -Owner jsmith -Force
```

#### `Set-RTTicketQueue`
Move a ticket to a different queue.

```powershell
Set-RTTicketQueue -Id 12345 -Queue 'Network'

# Move all tickets matching a keyword
Search-RTTicket -Queue 'General' -Keyword 'firewall' |
    Set-RTTicketQueue -Queue 'Network' -Force
```

#### `Set-RTTicketPriority`
Set the numeric priority on a ticket (0–100).

```powershell
Set-RTTicketPriority -Id 12345 -Priority 80

# Elevate all stalled tickets in a queue
Search-RTTicket -Queue 'HelpDesk' -Status stalled |
    Set-RTTicketPriority -Priority 75 -Force
```

#### `Set-RTTicketField`
Update one or more standard or custom fields in a single call. Use for any field not covered by the dedicated `Set-RTTicket*` cmdlets, including all custom fields.

| Parameter | Description |
|-----------|-------------|
| `-Fields` | Hashtable of standard field name/value pairs. |
| `-CustomFields` | Hashtable of custom field name/value pairs. Keys must match RT field names exactly. |

```powershell
# Standard field
Set-RTTicketField -Id 12345 -Fields @{ Subject = 'Revised subject line' }

# Custom field
Set-RTTicketField -Id 12345 -CustomFields @{ 'ServiceCategory' = 'Network' }

# Both together
Set-RTTicketField -Id 12345 `
    -Fields       @{ TimeWorked = 60 } `
    -CustomFields @{ 'Impact' = 'High'; 'RootCause' = 'Hardware failure' } `
    -Force -PassThru
```

#### `Add-RTTicketReply`
Send a reply (outbound correspondence) on a ticket. Equivalent to clicking **Reply** in the RT web interface — sends email to requestor(s) and any Cc addresses.

| Parameter | Description |
|-----------|-------------|
| `-Id` | Ticket ID. |
| `-Body` | Reply body. Cannot be used with `-TemplateName`. |
| `-TemplateName` | Name of a response template. Cannot be used with `-Body`. |
| `-TemplateValues` | Hashtable of token values for scripted template use. |
| `-Cc` | Additional email addresses to copy on this reply. |

```powershell
Add-RTTicketReply -Id 12345 -Body "Hi, we have resolved your issue."

# Pipe body from a file
Get-Content .\reply.txt -Raw | Add-RTTicketReply -Id 12345

# Use a response template (interactive — prompts for token values)
Add-RTTicketReply -Id 12345 -TemplateName 'rdp-instructions'

# Use a template in a script
Add-RTTicketReply -Id 12345 -TemplateName 'rdp-instructions' `
    -TemplateValues @{ VpnGroup = 'CORP-VPN'; HostAddress = '10.0.1.50' } -Force
```

#### `Add-RTTicketComment`
Add an internal comment to a ticket. Equivalent to clicking **Comment** in the RT web interface — visible only to RT users; no email is sent.

```powershell
Add-RTTicketComment -Id 12345 -Body "Checked with vendor — part on order."

# Scripted with PassThru to verify the updated ticket
Add-RTTicketComment -Id 12345 -Body "Automated check passed." -Force -PassThru
```

#### `Add-RTTicketAttachment`
Upload one or more files to a ticket.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Id` | _(required)_ | Ticket ID. |
| `-Path` | _(required)_ | One or more file paths. Accepts wildcards. |
| `-Comment` | `'Attachment uploaded via RTShell.'` | Comment text accompanying the upload transaction. |

```powershell
Add-RTTicketAttachment -Id 12345 -Path C:\Logs\error.log

# Multiple files via wildcard
Add-RTTicketAttachment -Id 12345 -Path C:\Reports\*.csv -Force

# Pipeline from Get-ChildItem
Get-ChildItem C:\Captures\*.pcap |
    Add-RTTicketAttachment -Id 12345 -Comment 'Network captures for analysis.' -Force
```

---

### Response Templates

Templates are stored as individual `.json` files under `~/.rtshell/templates/`. They support `{{Token}}` placeholders for dynamic content.

**Automatic tokens** (resolved from the ticket object at send time):

| Token | Value |
|-------|-------|
| `{{TicketId}}` | Ticket ID |
| `{{Subject}}` | Ticket subject |
| `{{RequestorName}}` | First requestor's first name (from RT RealName, or email local part as fallback) |
| `{{RequestorEmail}}` | First requestor's email address |
| `{{Owner}}` | Ticket owner login |
| `{{Queue}}` | Queue name |
| `{{Status}}` | Ticket status |

**Prompt tokens** are declared via `-Prompts` and resolved interactively at send time, or non-interactively via `-TemplateValues`.

#### `New-RTTemplate`
Create a new response template.

| Parameter | Description |
|-----------|-------------|
| `-Name` | Unique template key. Becomes the filename. |
| `-Description` | Short description of when to use this template. |
| `-Body` | Template body with optional `{{Token}}` placeholders. |
| `-Subject` | Optional subject line override. |
| `-Prompts` | Hashtable of token names to prompt strings for tech-supplied values. |

```powershell
New-RTTemplate -Name 'phishing-report' `
    -Description 'Initial response to a reported phishing email' `
    -Body "Hi {{RequestorName}},`n`nThank you for reporting a suspicious email. Our security team has been notified and will investigate.`n`nPlease do not click any links in the email.`n`nRegards,`nIT Support"

New-RTTemplate -Name 'rdp-instructions' `
    -Description 'RDP setup instructions with VPN and host details' `
    -Body "Hi {{RequestorName}},`n`nTo connect via RDP:`n`n1. Connect to VPN group: {{VpnGroup}}`n2. Open Remote Desktop and connect to: {{HostAddress}}`n`nLet us know if you need further assistance." `
    -Prompts @{ VpnGroup = 'Enter the VPN group name'; HostAddress = 'Enter the RDP host address or IP' }
```

#### `Get-RTTemplate`
List all templates, or retrieve a specific template by name.

```powershell
Get-RTTemplate                                 # List all (with body preview)
Get-RTTemplate -Name 'rdp-instructions'        # Specific template
Get-RTTemplate -Name 'rdp-instructions' -Detailed  # Full body and prompts
```

#### `Set-RTTemplate`
Update one or more fields of an existing template. Only supplied parameters are changed.

```powershell
# Update only the body
Set-RTTemplate -Name 'phishing-report' -Body "Hi {{RequestorName}},`n`nUpdated response..."

# Update description and prompts
Set-RTTemplate -Name 'rdp-instructions' `
    -Description 'RDP setup — includes VPN group and host' `
    -Prompts @{ VpnGroup = 'Enter the VPN group'; HostAddress = 'Enter the host or IP' }

# Clear the subject override
Set-RTTemplate -Name 'password-reset' -Subject ''
```

#### `Remove-RTTemplate`
Permanently delete a template. Prompts for confirmation by default.

```powershell
Remove-RTTemplate -Name 'phishing-report'
Remove-RTTemplate -Name 'old-template' -Force
```

---

## Pipelining Examples

```powershell
# Get full details for all open tickets in a queue
Search-RTTicket -Queue 'HelpDesk' | Get-RTTicket

# Export to CSV
Search-RTTicket -Queue 'HelpDesk' -Status any -All |
    Get-RTTicket |
    Select-Object Id, Subject, Status, Owner, Created |
    Export-Csv -Path tickets.csv -NoTypeInformation

# Show the full correspondence thread for a ticket, in order
Get-RTTicketHistory -Id 12345 -Type Correspond |
    Sort-Object Created |
    Format-List Created, CreatorName, Content

# Download all attachments from a set of tickets
100, 101, 102 |
    ForEach-Object { Get-RTTicketAttachments -Id $_ } |
    Save-RTTicketAttachment -DestinationPath C:\Temp\Attachments -Force

# Bulk assign unowned tickets
Search-RTTicket -Queue 'HelpDesk' -Owner Nobody |
    Set-RTTicketOwner -Owner jsmith -Force

# Escalate stalled tickets
Search-RTTicket -Queue 'HelpDesk' -Status stalled |
    Set-RTTicketPriority -Priority 90 -Force

# Bulk move tickets by keyword
Search-RTTicket -Queue 'General' -Keyword 'firewall' -Status any -All |
    Set-RTTicketQueue -Queue 'Network' -Force

# Create a ticket and immediately send a templated reply
New-RTTicket -Queue 'HelpDesk' -Subject 'New VPN request' -Requestor 'user@example.com' -Force -PassThru |
    Add-RTTicketReply -TemplateName 'vpn-setup' `
        -TemplateValues @{ VpnGroup = 'CORP-REMOTE' } -Force

# Resolve a ticket with a closing comment, then set it resolved
Add-RTTicketComment -Id 12345 -Body 'Resolved — hardware replaced.' -Force
Set-RTTicketStatus  -Id 12345 -Status resolved -Force
```

---

## Outputs and Types

| Type | Produced by |
|------|-------------|
| `RTShell.Ticket` | `Get-RTTicket`, `New-RTTicket -PassThru`, `Set-RTTicket* -PassThru`, `Add-RTTicket* -PassThru` |
| `RTShell.TicketSummary` | `Search-RTTicket` |
| `RTShell.TicketHistory.Summary` | `Get-RTTicketHistory` (default) |
| `RTShell.TicketTransaction` | `Get-RTTicketHistory -Detailed` |
| `RTShell.Attachment` | `Get-RTTicketAttachments` |
| `RTShell.Queue` | `Get-RTQueue` |
| `RTShell.User` | `Get-RTUser` |
| `RTShell.ResponseTemplate` | `Get-RTTemplate` |

---

## Configuration Files

| Path | Contents |
|------|----------|
| `~/.rtshell/config.json` | Base URI, queue cache, cache timestamp |
| `~/.rtshell/templates/*.json` | Response template files (one per template) |
| SecretManagement vault | API token (stored as `RTShell_Token`) |

To reset all configuration, delete `~/.rtshell/` and remove the `RTShell_Token` secret from your vault.

---

## License

MIT
