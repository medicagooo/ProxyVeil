#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$ledger=Get-Content -LiteralPath "$root\BRANCHES.md" -Raw | ConvertFrom-Json -AsHashtable
foreach ($field in @('records','active','pending','read','changes')) { if (-not $ledger.ContainsKey($field)) { throw "Missing ledger field: $field" } }
$ids=[Collections.Generic.HashSet[string]]::new()
$eventsByTask=@{}
foreach ($r in $ledger.records) {
    if (-not $ids.Add($r.id)) { throw 'Duplicate task id' }
    foreach ($p in @($r.state,$r.events)) { if (-not (Test-Path -LiteralPath (Join-Path $root $p))) { throw "Missing registry reference: $p" } }
    $state=Get-Content -LiteralPath (Join-Path $root $r.state) -Raw | ConvertFrom-Json -AsHashtable
    foreach ($field in @('purpose','requirements','constraints','acceptance','status','integration','evidence','next')) { if (-not $state.ContainsKey($field)) { throw "Missing task field: $field" } }
    if ($state.status -notin @('active','blocked','complete','unknown') -or $state.integration -notin @('unmerged','verified','unknown','not_applicable')) { throw 'Invalid task lifecycle' }
    foreach ($p in @($state.requirements)+@($state.evidence)) { if (-not (Test-Path -LiteralPath (Join-Path $root $p))) { throw "Missing evidence: $p" } }
    $eventIds=[Collections.Generic.HashSet[string]]::new(); $eventsByTask[$r.id]=@{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $root $r.events)) {
        $e=$line | ConvertFrom-Json -AsHashtable
        if (-not $eventIds.Add($e.id)) { throw 'Duplicate event id' }
        $eventsByTask[$r.id][$e.id]=$e
    }
}
foreach ($p in $ledger.pending) {
    if (-not $eventsByTask.ContainsKey($p.task) -or -not $eventsByTask[$p.task].ContainsKey($p.event)) { throw 'Invalid pending event' }
    if ($eventsByTask[$p.task][$p.event].type -ne 'operation') { throw 'Pending pointer is not an operation' }
}
foreach ($id in $ledger.active) { if (-not $ids.Contains($id)) { throw 'Unknown active task' } }
$changeIds=[Collections.Generic.HashSet[string]]::new()
foreach ($c in $ledger.changes) {
    if (-not $changeIds.Add($c.id)) { throw 'Duplicate change id' }
    $requestFound=$false
    foreach ($events in $eventsByTask.Values) { if ($events.ContainsKey($c.request) -and $events[$c.request].type -eq 'user_request') { $requestFound=$true } }
    if (-not $requestFound) { throw 'Business change missing user request' }
    foreach ($p in $c.evidence) { if (-not (Test-Path -LiteralPath (Join-Path $root $p))) { throw "Missing change evidence: $p" } }
}
'PASS: branch registry'
