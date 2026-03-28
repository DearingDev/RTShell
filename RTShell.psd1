@{
	# Script module or binary module file associated with this manifest
	RootModule = 'RTShell.psm1'
	
	# Version number of this module.
	ModuleVersion = '0.1.0'
	
	# ID used to uniquely identify this module
	GUID = 'ec49fac6-1b1c-4776-bab1-f9466887fc28'
	
	# Author of this module
	Author = 'Josh Dearing'
	
	# Company or vendor of this module
	CompanyName = ''
	
	# Copyright statement for this module
	Copyright = 'Joshua Dearing Copyright (c) 2026 '
	
	# Description of the functionality provided by this module
	Description = 'PowerShell module for Request Tracker (RT) via REST API v2. Supports API token auth, config persistence, structured ticket search, write operations, and response templates.'
	
	# Minimum version of the Windows PowerShell engine required by this module
	PowerShellVersion = '5.1'
	
	# Modules that must be imported into the global environment prior to importing this module
	RequiredModules = @('Microsoft.PowerShell.SecretManagement')
	
	# Assemblies that must be loaded prior to importing this module
	# RequiredAssemblies = @('bin\RTShell.dll')
	
	# Type files (.ps1xml) to be loaded when importing this module
	# Expensive for import time, no more than one should be used.
	# TypesToProcess = @('xml\RTShell.Types.ps1xml')
	
	# Format files (.ps1xml) to be loaded when importing this module.
	# Expensive for import time, no more than one should be used.
	# FormatsToProcess = @('xml\RTShell.Format.ps1xml')
	
	# Functions to export from this module
    FunctionsToExport = @(
        # Session
        'Connect-RT'
        'Disconnect-RT'
        'Save-RTConfiguration'
        'Update-RTQueueCache'

        # Read
        'Get-RTTicket'
        'Search-RTTicket'
        'Get-RTTicketHistory'
        'Get-RTTicketAttachments'
        'Save-RTTicketAttachment'
        'Get-RTQueue'
        'Get-RTUser'

        # Write — tickets
        'New-RTTicket'
        'Set-RTTicketStatus'
        'Set-RTTicketOwner'
        'Set-RTTicketQueue'
        'Set-RTTicketPriority'
        'Set-RTTicketField'
        'Add-RTTicketReply'
        'Add-RTTicketComment'
        'Add-RTTicketAttachment'

        # Response templates
        'Get-RTTemplate'
        'New-RTTemplate'
        'Set-RTTemplate'
        'Remove-RTTemplate'
    )
	
	# Cmdlets to export from this module
	CmdletsToExport = ''
	
	# Variables to export from this module
	VariablesToExport = ''
	
	# Aliases to export from this module
	AliasesToExport = ''
	
	# List of all files packaged with this module
	FileList = @()
	
	# Private data to pass to the module specified in ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
	PrivateData = @{
		
		#Support for PowerShellGet galleries.
		PSData = @{
			
			# Tags applied to this module. These help with module discovery in online galleries.
			Tags = @('RT', 'Request Tracker', 'Ticketing', 'ITSM')
			
			# A URL to the license for this module.
			# LicenseUri = ''
			
			# A URL to the main website for this project.
			# ProjectUri = ''
			
			# A URL to an icon representing this module.
			# IconUri = ''
			
			# ReleaseNotes of this module
			ReleaseNotes = @'
0.1.0 - Initial release with core functionality for connecting to RT, managing tickets, and handling response templates.
'@
			
		} # End of PSData hashtable
		
	} # End of PrivateData hashtable
}