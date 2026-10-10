#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$RequestPath,[Parameter(Mandatory)][string]$ProgressPath,[Parameter(Mandatory)][string]$ResultPath,[string]$FixtureRoot)
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot\ProxyVeil.Core.psm1" -Force
try {
    $request=Read-PvJson $RequestPath
    $result=Invoke-PvOperation -Request $request -ProgressPath $ProgressPath -FixtureRoot $FixtureRoot
    Save-PvJson $ResultPath $result
    exit 0
} catch {
    $active=$false
    try {
        $state=if ($request.StateDirectory) { $request.StateDirectory } else { Get-PvDefaultStateDirectory }
        $active=Test-Path -LiteralPath (Join-Path $state 'active.json')
    } catch {}
    Save-PvJson $ResultPath @{status='Failed';active=$active;message=$_.Exception.Message;items=@()}
    exit 1
}
