#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
Import-Module "$root/src/ProxyVeil.Core.psm1" -Force
. "$root/tests/WindowsHost.Assertions.ps1"
$os = Get-CimInstance Win32_OperatingSystem
$report = [ordered]@{
    at = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(-4)).ToString('o')
    os = $os.Caption; build = $os.BuildNumber; powerShell = $PSVersionTable.PSVersion.ToString()
    scope = 'Read-only live FlClash/Edge inspection and existing-network baseline'
    administrator = Test-PvAdministrator; liveConfigurationModified = $false
    repairExecuted = $false; restoreExecuted = $false; realUacTest = $false
    postRepairLeakAcceptance = 'not_executed'; networkBaseline = @()
}
$policyNames = @('WebRtcLocalhostIpHandling','WebRtcRespectOsRoutingTableEnabled','WebRtcIPHandlingUrl','DnsOverHttpsMode','DnsOverHttpsTemplates')
function Get-PvHostPolicySnapshot {
    $result = @{}
    foreach ($name in $policyNames) {
        $result[$name] = @{user=(Get-PvPolicy $name);machine=(Get-PvPolicy $name -Machine)}
    }
    return $result
}
function Test-PvHostHttps([string]$Label, [string]$Url, [int]$ProxyPort = 0) {
    $handler = [Net.Http.HttpClientHandler]::new()
    if ($ProxyPort) {
        $handler.Proxy = [Net.WebProxy]::new("http://127.0.0.1:$ProxyPort")
        $handler.UseProxy = $true
    }
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(15)
    $result = @{target=$Label;transport=$(if ($ProxyPort) { 'explicit_loopback_proxy' } else { 'HttpClient_default_proxy' });result='failed';httpStatus=$null}
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, $Url)
        $response = $client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try {
            $result.httpStatus = [int]$response.StatusCode
            $result.result = if ($response.IsSuccessStatusCode) { 'passed' } else { 'http_response' }
        } finally { $response.Dispose(); $request.Dispose() }
    } catch { $result.errorType = $_.Exception.GetBaseException().GetType().Name }
    finally { $watch.Stop(); $result.elapsedMs = $watch.ElapsedMilliseconds; $client.Dispose() }
    return $result
}
$policiesBefore = Get-PvHostPolicySnapshot
try {
    $context = Get-PvContext -SkipDnsGroup
    $preferencesBefore = $context.PreferencesHash; $profileBefore = $context.ProfileHash
    $report.flclash = @{installPath=$context.Exe;configDirectory=$context.Directory;version=(Get-Item -LiteralPath $context.Exe).VersionInfo.ProductVersion;mode=$context.Mode;preferencesStructure='recognized';selectedProfileVerified=$true;running=(@(Get-Process -Name FlClash -ErrorAction SilentlyContinue).Count -gt 0)}
    $report.inMemoryPlans = @(foreach ($mode in @('TUN','Proxy')) {
        try {
            $planningContext = Get-PvContext
            $plan = New-PvConfiguration -Context $planningContext -Mode $mode -Items @('DNS','WebRTC','IPv6')
            @{mode=$mode;result='passed';policyNames=@($plan.Policies.Keys | Sort-Object);plannedFileTargets=@('Selected profile YAML','shared_preferences.json');valuesSaved=$false}
        } catch { @{mode=$mode;result='failed';errorType=$_.Exception.GetBaseException().GetType().Name;valuesSaved=$false} }
    })
    $request = @{Action='Inspect';Edition='Standard';InstallPath=$context.Exe;ConfigDirectory=$context.Directory;ProxyGroup='';StateDirectory=(Get-PvDefaultStateDirectory)}
    try {
        $inspection = Invoke-PvOperation -Request $request
        $report.liveInspect = @{result=$inspection.status;proxyGroupCount=@($inspection.groups).Count;activeSnapshot=$inspection.active}
    } catch { $report.liveInspect = @{result='failed';errorType=$_.Exception.GetBaseException().GetType().Name;message='Full Inspect failed; no changes made; exception values omitted'} }
    $report.permissionGuards = @()
    $wrongUserRequest = @{} + $request
    $wrongUserRequest.TargetUserSid = 'S-1-5-21-0-0-0-9999'
    try { $null = Invoke-PvOperation -Request $wrongUserRequest; $report.permissionGuards += @{case='different_user_sid';result='failed'} }
    catch { $report.permissionGuards += @{case='different_user_sid';result=$(if ($_.Exception.Message -eq '请使用原用户的管理员授权，其他用户的 UAC 不支持接管。') { 'passed' } else { 'failed' })} }
    if (-not $report.administrator) {
        $adminRequest = @{} + $request; $adminRequest.Edition = 'Administrator'
        try { $null = Invoke-PvOperation -Request $adminRequest; $report.permissionGuards += @{case='administrator_without_elevated_token';result='failed'} }
        catch { $report.permissionGuards += @{case='administrator_without_elevated_token';result=$(if ($_.Exception.Message -eq '管理员版未获得管理员权限，请通过管理员入口启动。') { 'passed' } else { 'failed' })} }
    }
    $service = Get-Service -Name FlClashHelperService -ErrorAction SilentlyContinue
    $report.helperService = if ($service) { $service.Status.ToString() } else { 'not_found' }
    $appliedConfig = Join-Path $context.Directory 'config.yaml'
    $port = 0
    if (Test-Path -LiteralPath $appliedConfig) {
        $text = [IO.File]::ReadAllText($appliedConfig)
        $match = [regex]::Match($text.TrimStart([char]0xFEFF), '(?m)^mixed-port:\s*(\d+)\s*(?:#.*)?$')
        if ($match.Success) { $candidate = [int]$match.Groups[1].Value; if ($candidate -ge 1 -and $candidate -le 65535) { $port = $candidate } }
    }
    $report.localProxy = @{port=$port;portSource='applied config.yaml mixed-port';tcpConnect='not_checked'}
    if ($port) {
        $tcp = [Net.Sockets.TcpClient]::new()
        try {
            $task = $tcp.ConnectAsync('127.0.0.1', $port)
            if ($task.Wait(3000) -and $tcp.Connected) { $report.localProxy.tcpConnect = 'passed' } else { $report.localProxy.tcpConnect = 'failed' }
        } catch { $report.localProxy.tcpConnect = 'failed' }
        finally { $tcp.Dispose() }
    }
    foreach ($site in @(@{label='domestic_https';url='https://www.baidu.com/'},@{label='proxy_site_https';url='https://www.google.com/'})) {
        $report.networkBaseline += Test-PvHostHttps $site.label $site.url
        if ($port -and $report.localProxy.tcpConnect -eq 'passed') { $report.networkBaseline += Test-PvHostHttps $site.label $site.url $port }
    }
    $report.flclashFilesUnchangedDuringProbe = ((Get-FileHash -LiteralPath $context.Preferences -Algorithm SHA256).Hash -eq $preferencesBefore -and (Get-FileHash -LiteralPath $context.Profile -Algorithm SHA256).Hash -eq $profileBefore)
    $report.inspectionResult = 'passed'
} catch {
    $report.inspectionErrorType = $_.Exception.GetBaseException().GetType().Name
    $report.inspectionResult = 'failed'
} finally {
    $policiesAfter = Get-PvHostPolicySnapshot
    $report.edgePolicies = @(foreach ($name in $policyNames) { @{name=$name;userExists=[bool]$policiesAfter[$name].user.Exists;userType=$policiesAfter[$name].user.Type;machineExists=[bool]$policiesAfter[$name].machine.Exists;machineType=$policiesAfter[$name].machine.Type} })
    $report.edgePoliciesUnchangedDuringProbe = ((ConvertTo-Json -InputObject $policiesBefore -Depth 20 -Compress) -ceq (ConvertTo-Json -InputObject $policiesAfter -Depth 20 -Compress))
    $report.activeSnapshotExists = Test-Path -LiteralPath (Join-Path (Get-PvDefaultStateDirectory) 'active.json')
    Save-PvJson "$root/docs/validation/windows-host.json" $report
}
Assert-PvWindowsHostReport $report
'PASS: read-only Windows host inspection; network baseline recorded separately'
