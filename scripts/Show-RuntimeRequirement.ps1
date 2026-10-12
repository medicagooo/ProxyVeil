# The CMD launcher uses Windows PowerShell only when PowerShell 7 is missing.
# This read-only message uses the same resources as the application.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../src/Localization.ps1"
Write-Host (Get-PvText 'Error.PowerShellRequired')
