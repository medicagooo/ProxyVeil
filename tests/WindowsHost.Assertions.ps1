function Assert-PvWindowsHostReport([Collections.IDictionary]$Report) {
    # Test-WindowsHost saves the sanitized report before this gate. HTTPS failures
    # remain a separate baseline result; incomplete inspection or drift must fail.
    if ($Report.inspectionResult -ne 'passed' -or -not $Report.flclash -or $Report.liveInspect.result -ne 'Inspected') {
        throw 'Live configuration inspection incomplete; see sanitized windows-host.json.'
    }
    foreach ($field in @('flclashFilesUnchangedDuringProbe', 'edgePoliciesUnchangedDuringProbe')) {
        if ($Report[$field] -isnot [bool] -or -not $Report[$field]) {
            throw "Read-only host check failed: $field."
        }
    }
    foreach ($mode in @('TUN', 'Proxy')) {
        $plans = @($Report.inMemoryPlans | Where-Object mode -eq $mode)
        if ($plans.Count -ne 1 -or $plans[0].result -ne 'passed') { throw "Read-only plan check failed: $mode." }
    }
    $cases = @('different_user_sid')
    if (-not $Report.administrator) { $cases += 'administrator_without_elevated_token' }
    foreach ($case in $cases) {
        $guards = @($Report.permissionGuards | Where-Object case -eq $case)
        if ($guards.Count -ne 1 -or $guards[0].result -ne 'passed') { throw "Permission guard check failed: $case." }
    }
}
