#requires -Version 7.0
[CmdletBinding()]
param([ValidateSet('Standard','Administrator')][string]$Edition='Standard')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Import-Module "$root\src\ProxyVeil.Core.psm1" -Force
$entry=Join-Path $root 'src\Start-ProxyVeil.ps1'
$sid=Get-PvIdentity
if ($Edition -eq 'Administrator' -and -not (Test-PvAdministrator)) {
    $quoted=$entry.Replace("'","''")
    $command="& '$quoted' -Edition Administrator -TargetUserSid '$sid'"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-STA','-EncodedCommand',$encoded) | Out-Null
} else { & $entry -Edition $Edition -TargetUserSid $sid }
