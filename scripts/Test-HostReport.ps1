#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. "$root/tests/WindowsHost.Assertions.ps1"
Import-Module "$root/src/ProxyVeil.Core.psm1" -Force
function New-PvHostReportFixture {
    @{
        inspectionResult='passed'; flclash=@{mode='TUN'}; liveInspect=@{result='Inspected'}
        administrator=$false; flclashFilesUnchangedDuringProbe=$true; edgePoliciesUnchangedDuringProbe=$true
        inMemoryPlans=@(@{mode='TUN';result='passed'},@{mode='Proxy';result='passed'})
        permissionGuards=@(@{case='different_user_sid';result='passed'},@{case='administrator_without_elevated_token';result='passed'})
        networkBaseline=@(@{result='failed';errorType='TimeoutException'})
    }
}
$cases = @(
    @{name='complete inspection with separate HTTPS failure'; reject=$false; mutate={param($r)}}
    @{name='late IOException after successful Inspect'; reject=$true; mutate={param($r) $r.inspectionResult='failed'; $r.inspectionErrorType='IOException'}}
    @{name='missing completion marker'; reject=$true; mutate={param($r) $r.Remove('inspectionResult')}}
    @{name='FlClash file drift'; reject=$true; mutate={param($r) $r.flclashFilesUnchangedDuringProbe=$false}}
    @{name='missing file hash result'; reject=$true; mutate={param($r) $r.Remove('flclashFilesUnchangedDuringProbe')}}
    @{name='Edge policy drift'; reject=$true; mutate={param($r) $r.edgePoliciesUnchangedDuringProbe=$false}}
    @{name='missing policy comparison'; reject=$true; mutate={param($r) $r.Remove('edgePoliciesUnchangedDuringProbe')}}
    @{name='failed Proxy plan'; reject=$true; mutate={param($r) $r.inMemoryPlans[1].result='failed'}}
    @{name='missing TUN plan'; reject=$true; mutate={param($r) $r.inMemoryPlans=@($r.inMemoryPlans[1])}}
    @{name='failed SID guard'; reject=$true; mutate={param($r) $r.permissionGuards[0].result='failed'}}
    @{name='missing unelevated guard'; reject=$true; mutate={param($r) $r.permissionGuards=@($r.permissionGuards[0])}}
    @{name='elevated host needs only SID guard'; reject=$false; mutate={param($r) $r.administrator=$true; $r.permissionGuards=@($r.permissionGuards[0])}}
)
$results = @(foreach ($case in $cases) {
    $report = New-PvHostReportFixture
    $null = & $case.mutate $report
    $rejected = $false
    try { Assert-PvWindowsHostReport $report } catch { $rejected = $true }
    if ($rejected -ne $case.reject) { throw "Host report regression: $($case.name)" }
    @{case=$case.name;result='passed';expectedRejection=$case.reject}
})
Save-PvJson "$root/docs/validation/host-report.json" @{at=[DateTimeOffset]::Now.ToString('o');powerShell=$PSVersionTable.PSVersion.ToString();scope='Synthetic reports; no host configuration or network access';results=$results}
"PASS: $($results.Count) host report cases"
