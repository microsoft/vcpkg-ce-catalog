. "$PSScriptRoot\Common\GeneralUtilities.ps1"
. "$PSScriptRoot\Common\Telemetry.ps1"

Write-Telemetry "CoreXT Profile" (Get-CoreXTProfileNames -join ',')