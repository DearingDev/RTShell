# Place all code that should be run before functions are imported here
# Load RTSession configuration
. "$PSScriptRoot\..\functions\RTSession.ps1"

# Module-scope session state
$Script:RTSession = [RTSession]::new()