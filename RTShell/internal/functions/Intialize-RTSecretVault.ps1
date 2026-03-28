function Initialize-RTSecretVault {
	<#
    .SYNOPSIS
        Internal helper. Ensures at least one SecretManagement vault is registered.
        Prompts to install and register Microsoft.PowerShell.SecretStore if none exist.
    #>
	[CmdletBinding()]
	param()

	# 1. Check if any vault is currently registered
	$existingVaults = Get-SecretVault -ErrorAction SilentlyContinue
	if ($null -ne $existingVaults -and $existingVaults.Count -gt 0) {
		Write-Verbose "A SecretManagement vault is already registered ($($existingVaults[0].Name))."
		return
	}

	# 2. No vault found. Prompt the user for a guided setup.
	Write-Information "`n[RTShell Security] No SecretManagement vault is currently configured on this system." -InformationAction Continue
	Write-Information "To securely save your RT token, a vault is required." -InformationAction Continue
    
	$choice = Read-Host "Would you like RTShell to automatically install and configure the local Microsoft SecretStore? (Y/n)"
    
	if ($choice -match '^n') {
		throw "Cannot save credentials without a configured SecretManagement vault. Please register a vault manually and try again."
	}

	# 3. Check if the SecretStore module is installed locally
	$storeModule = Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretStore
	if (-not $storeModule) {
		Write-Information "Installing Microsoft.PowerShell.SecretStore from the PSGallery..." -InformationAction Continue
		Install-Module -Name Microsoft.PowerShell.SecretStore -Scope CurrentUser -Force -AllowClobber
	}

	# 4. Register the vault and set it as the default
	Write-Information "Registering SecretStore as your default vault..." -InformationAction Continue
	Register-SecretVault -Name 'LocalStore' -ModuleName 'Microsoft.PowerShell.SecretStore' -DefaultVault -WarningAction SilentlyContinue
    
	# Optional: You can configure the store to not require a password if you want, 
	# but prompting for a master password on first use is the most secure default.
	# Set-SecretStoreConfiguration -Scope CurrentUser -Authentication Password -Confirm:$false

	Write-Information "Vault successfully configured! `n*Note: The vault will prompt you to create a master password when saving this token.*`n" -InformationAction Continue
}