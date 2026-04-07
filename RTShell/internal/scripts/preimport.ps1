# Place all code that should be run before functions are imported here
# Load RTSession configuration
$rtSessionPath = "$script:ModuleRoot\internal\functions\RTSession.ps1"
if (Test-Path $rtSessionPath) {
    . $rtSessionPath
}

# Module-scope session state
$Script:RTSession = [RTSession]::new()
