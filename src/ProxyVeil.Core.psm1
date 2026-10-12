#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Localization.ps1"
. "$PSScriptRoot\Adapters\FlClash.Yaml.ps1"
. "$PSScriptRoot\Progress.ps1"
$script:PolicyNames = @('WebRtcLocalhostIpHandling','WebRtcRespectOsRoutingTableEnabled','WebRtcIPHandlingUrl','DnsOverHttpsMode','DnsOverHttpsTemplates')

function Get-PvIdentity {
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}
function Test-PvAdministrator {
    $p = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-PvDefaultStateDirectory { Join-Path $env:LOCALAPPDATA 'ProxyVeil' }
function Read-PvJson([string]$Path) {
    try { ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -AsHashtable }
    catch { throw (Get-PvText 'Error.JsonRead' -Arguments @(([IO.Path]::GetFileName($Path)))) }
}
function Save-PvJson([string]$Path, $Value) { Write-AtomicText $Path (ConvertTo-Json -InputObject $Value -Depth 100) }
function Get-PvHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-PvTextHash([string]$Text) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-PvOwnedField($Inner,[string]$Path) {
    $parts=$Path.Split('.'); $node=$Inner
    foreach ($part in $parts) {
        if ($node -isnot [Collections.IDictionary] -or -not $node.Contains($part)) { return @{exists=$false;value=$null} }
        $node=$node[$part]
    }
    @{exists=$true;value=$node}
}
function Test-PvFieldEqual($A,$B) {
    if ([bool]$A.exists -ne [bool]$B.exists) { return $false }
    if (-not $A.exists) { return $true }
    (ConvertTo-Json -InputObject $A.value -Depth 100 -Compress) -ceq (ConvertTo-Json -InputObject $B.value -Depth 100 -Compress)
}
function Get-PvPreferenceFields($Before,[string]$AfterJson) {
    $outer=ConvertFrom-Json -InputObject $AfterJson -AsHashtable
    $after=ConvertFrom-Json -InputObject $outer['flutter.config'] -AsHashtable
    $fields=@()
    foreach ($path in @('patchClashConfig.ipv6','patchClashConfig.tun.enable','patchClashConfig.tun.auto-route','patchClashConfig.tun.strict-route','patchClashConfig.tun.dns-hijack','networkProps.appendSystemDns','networkProps.systemProxy','overrideDns')) {
        $old=Get-PvOwnedField $Before $path; $new=Get-PvOwnedField $after $path
        if (-not (Test-PvFieldEqual $old $new)) { $fields+=@(@{path=$path;before=$old;after=$new}) }
    }
    return ,$fields
}
function Get-PvRestoreFilePlan($File,[string]$Directory) {
    if (-not (Test-Path -LiteralPath $File.path -PathType Leaf)) { throw (Get-PvText 'Error.RestoreFileMissing') }
    $hash=Get-PvHash $File.path
    if ($hash -in @($File.beforeHash,$File.afterHash)) { return @{hash=$hash;merge=$false;text=$null} }
    if (-not $File.Contains('fields')) { throw (Get-PvText 'Error.RestoreFileConflict' -Arguments @(([IO.Path]::GetFileName($File.path)))) }
    $outer=Read-PvJson $File.path
    try { $inner=ConvertFrom-Json -InputObject $outer['flutter.config'] -AsHashtable } catch { throw (Get-PvText 'Error.PreferenceFormatConflict') }
    foreach ($field in $File.fields) {
        $current=Get-PvOwnedField $inner $field.path
        if (-not (Test-PvFieldEqual $current $field.before) -and -not (Test-PvFieldEqual $current $field.after)) { throw (Get-PvText 'Error.ManagedPreferenceConflict' -Arguments @($field.path)) }
        $parts=$field.path.Split('.'); $node=$inner
        for ($i=0;$i -lt $parts.Length-1;$i++) {
            if (-not $node.Contains($parts[$i]) -or $node[$parts[$i]] -isnot [Collections.IDictionary]) { throw (Get-PvText 'Error.PreferenceHierarchyConflict') }
            $node=$node[$parts[$i]]
        }
        $key=$parts[-1]
        if ($field.before.exists) { $node[$key]=$field.before.value } else { $node.Remove($key) }
    }
    $outer['flutter.config']=ConvertTo-Json -InputObject $inner -Depth 100 -Compress
    @{hash=$hash;merge=$true;text=(ConvertTo-Json -InputObject $outer -Depth 100 -Compress)}
}

function Get-PvContext {
    param([string]$InstallPath, [string]$ConfigDirectory, [string]$ProxyGroup, [string]$FixtureRoot, [switch]$SkipDnsGroup)
    if ($FixtureRoot) { $exe = Join-Path $FixtureRoot 'FlClash.exe'; $dir = Join-Path $FixtureRoot 'config' }
    else { $exe = Resolve-FlClashExecutable -Hint $InstallPath -Quiet; $dir = Resolve-FlClashConfigDirectory -Hint $ConfigDirectory -Exe $exe -Quiet }
    $prefs = Join-Path $dir 'shared_preferences.json'
    $preferencesHash=Get-PvHash $prefs
    $outer = Read-PvJson $prefs
    if ((Get-PvHash $prefs) -ne $preferencesHash) { throw (Get-PvText 'Error.PreferenceReadDrift') }
    if (-not $outer.ContainsKey('flutter.config') -or $outer['flutter.config'] -isnot [string]) { throw (Get-PvText 'Error.PreferenceStructure') }
    try { $inner = ConvertFrom-Json -InputObject $outer['flutter.config'] -AsHashtable } catch { throw (Get-PvText 'Error.PreferenceParse') }
    if (-not $inner.ContainsKey('currentProfileId') -or [string]$inner.currentProfileId -notmatch '^\d+$') { throw (Get-PvText 'Error.NoProfile') }
    if (-not $inner.ContainsKey('patchClashConfig') -or $inner.patchClashConfig -isnot [Collections.IDictionary] -or -not $inner.patchClashConfig.ContainsKey('tun') -or $inner.patchClashConfig.tun -isnot [Collections.IDictionary] -or -not $inner.ContainsKey('networkProps') -or $inner.networkProps -isnot [Collections.IDictionary]) { throw (Get-PvText 'Error.PreferenceVersion') }
    $profile = Join-Path $dir "profiles\$($inner.currentProfileId).yaml"
    if (-not (Test-Path -LiteralPath $profile -PathType Leaf)) { throw (Get-PvText 'Error.ProfileMissing') }
    $profileHash=Get-PvHash $profile
    $text = [IO.File]::ReadAllText($profile)
    if ((Get-PvHash $profile) -ne $profileHash) { throw (Get-PvText 'Error.ProfileReadDrift') }
    $group = if ($SkipDnsGroup) { '' } elseif ($ProxyGroup) { Select-DnsProxyGroup $text $ProxyGroup } else { Select-DnsProxyGroup $text '' }
    if ($group -match '[#&\r\n]') { throw (Get-PvText 'Error.GroupUrl') }
    $mode = if ($inner.patchClashConfig.tun.ContainsKey('enable') -and $inner.patchClashConfig.tun.enable) { 'TUN' } else { 'Proxy' }
    $groups=@(if (-not $SkipDnsGroup) { Get-ProxyGroupNames $text })
    @{Exe=$exe;Directory=$dir;Preferences=$prefs;Profile=$profile;PreferencesHash=$preferencesHash;ProfileHash=$profileHash;Text=$text;Outer=$outer;Inner=$inner;Group=$group;Groups=$groups;Mode=$mode}
}

function Get-PvRegistryValue($Key,[string]$Name) {
    if ($Key -and $Name -in $Key.GetValueNames()) { return @{Exists=$true;Value=$Key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);Type=$Key.GetValueKind($Name).ToString()} }
    return @{Exists=$false;Value=$null;Type=$null}
}
function Set-PvRegistryValue($Key,[string]$Name,$Value) {
    if ($Value.Exists) {
        # JSON snapshots lose native array types; keep empty/single arrays intact through the pipeline.
        $raw=switch ($Value.Type) {
            DWord {[int]$Value.Value}
            QWord {[long]$Value.Value}
            MultiString {,[string[]]$Value.Value}
            Binary {,[byte[]]$Value.Value}
            None {,[byte[]]$Value.Value}
            default {$Value.Value}
        }
        $Key.SetValue($Name,$raw,[Microsoft.Win32.RegistryValueKind]::$($Value.Type))
    } else { $Key.DeleteValue($Name,$false) }
}
function Get-PvPolicy {
    param([string]$Name,[string]$FixtureRoot,[switch]$Machine)
    if ($Name -notin $script:PolicyNames) { throw (Get-PvText 'Error.UnknownPolicy') }
    if ($FixtureRoot) {
        $store=Read-PvJson (Join-Path $FixtureRoot 'registry.json'); $side=if ($Machine) { 'machine' } else { 'user' }
        if ($store[$side].ContainsKey($Name)) { return $store[$side][$Name] }
        return @{Exists=$false;Value=$null;Type=$null}
    }
    $base=if ($Machine) { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    $key=$base.OpenSubKey('Software\Policies\Microsoft\Edge',$false)
    try {
        Get-PvRegistryValue $key $Name
    } finally { if ($key) { $key.Dispose() } }
}
function Set-PvPolicy {
    param([string]$Name,$Value,[string]$FixtureRoot)
    if ($Name -notin $script:PolicyNames) { throw (Get-PvText 'Error.UnknownPolicy') }
    if ($FixtureRoot) {
        $path=Join-Path $FixtureRoot 'registry.json'; $store=Read-PvJson $path
        if ($store.ContainsKey('deny') -and $Name -in $store.deny) { throw [UnauthorizedAccessException]::new((Get-PvText 'Error.PolicyPermission')) }
        if ($Value.Exists) { $store.user[$Name]=$Value } else { $store.user.Remove($Name) }
        Save-PvJson $path $store; return
    }
    $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Policies\Microsoft\Edge',$true)
    try {
        Set-PvRegistryValue $key $Name $Value
    } finally { if ($key) { $key.Dispose() } }
}
function Test-PvPolicyEqual($A,$B) {
    if ([bool]$A.Exists -ne [bool]$B.Exists) { return $false }
    if (-not $A.Exists) { return $true }
    $A.Type -ceq $B.Type -and (ConvertTo-Json -InputObject $A.Value -Depth 100 -Compress) -ceq (ConvertTo-Json -InputObject $B.Value -Depth 100 -Compress)
}
function Send-PvProgress {
    param([string]$Path,[string]$Id,[string]$Label,[string]$Status,[string]$Detail)
    $entry=@{id=$Id;label=$Label;status=$Status;detail=$Detail;at=(Get-Date).ToString('o')}
    if ($Path) { [IO.File]::AppendAllText($Path,(ConvertTo-Json -InputObject $entry -Compress)+"`n",[Text.UTF8Encoding]::new($false)) }
}
function Initialize-PvState([string]$Directory,[string]$FixtureRoot) {
    $null=New-Item -ItemType Directory -Path $Directory -Force
    if (-not $FixtureRoot) {
        $acl=[Security.AccessControl.DirectorySecurity]::new()
        $acl.SetAccessRuleProtection($true,$false)
        foreach ($sid in @((Get-PvIdentity),'S-1-5-18','S-1-5-32-544')) {
            $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow')
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $Directory -AclObject $acl
    }
}
function Save-PvManifest($Manifest,[string]$Directory) { Save-PvJson (Join-Path $Directory 'active.json') $Manifest }
function Get-PvActiveSnapshot([string]$StateDirectory) {
    $path=Join-Path $StateDirectory 'active.json'
    if (Test-Path -LiteralPath $path) { return Read-PvJson $path }
    return $null
}
function Stop-PvFlClash($Context,[bool]$Restart,[string]$FixtureRoot) {
    if ($FixtureRoot) { return $false }
    $matches=@(Get-Process -Name FlClash -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -ieq $Context.Exe } catch { $false } })
    if ($matches.Count -and -not $Restart) { throw (Get-PvText 'Error.FlClashRunning') }
    foreach ($process in $matches) { Stop-Process -Id $process.Id -ErrorAction Stop; $process.WaitForExit(5000) | Out-Null }
    $matches.Count -gt 0
}
function Start-PvFlClash([string]$Exe,[string]$FixtureRoot) {
    if (-not $FixtureRoot) { Start-Process -FilePath $Exe -WindowStyle Hidden | Out-Null }
}

# Repair and Restore share a durable write-ahead manifest. After records are persisted
# before each mutation; recovery accepts either recorded Before or After after interruption.
function Invoke-PvOperationCore {
    [CmdletBinding()]
    param([Collections.IDictionary]$Request,[string]$ProgressPath,[string]$FixtureRoot)
    $stateDir=[string]$Request.StateDirectory
    if (-not $stateDir) { $stateDir=Get-PvDefaultStateDirectory }
    $sid=Get-PvIdentity
    if ($Request.Contains('TargetUserSid') -and $Request.TargetUserSid -and $Request.TargetUserSid -ne $sid) { throw (Get-PvText 'Error.WrongUser') }
    if ($Request.Edition -notin @('Standard','Administrator')) { throw (Get-PvText 'Error.UnknownEdition') }
    if ($Request.Edition -eq 'Administrator' -and -not $FixtureRoot -and -not (Test-PvAdministrator)) { throw (Get-PvText 'Error.NotElevated') }
    if ($Request.Action -notin @('Inspect','Repair','Restore')) { throw (Get-PvText 'Error.UnknownAction') }
    if ($Request.Action -eq 'Inspect') {
        $c=Get-PvContext -InstallPath $Request.InstallPath -ConfigDirectory $Request.ConfigDirectory -ProxyGroup $Request.ProxyGroup -FixtureRoot $FixtureRoot
        return @{status='Inspected';installPath=$c.Exe;configDirectory=$c.Directory;mode=$c.Mode;groups=$c.Groups;group=$c.Group;administrator=(Test-PvAdministrator);active=[bool](Get-PvActiveSnapshot $stateDir)}
    }
    Initialize-PvState $stateDir $FixtureRoot
    $lockPath=Join-Path $stateDir 'operation.lock'
    try { $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) } catch { throw (Get-PvText 'Error.OperationBusy') }
    $resume=$false; $exe=''; $manifest=$null
    try {
        if ($Request.Action -eq 'Restore') {
            $manifest=Get-PvActiveSnapshot $stateDir
            if (-not $manifest) { throw (Get-PvText 'Error.NoSnapshot') }
            if ($manifest.sid -ne $sid) { throw (Get-PvText 'Error.SnapshotUser') }
            Send-PvProgress $ProgressPath 'restore-check' (Get-PvText 'Progress.RestoreCheck') 'running' (Get-PvText 'Progress.CheckExternalChanges')
            foreach ($f in $manifest.files) {
                if ($f.path -notin @($manifest.profile,$manifest.preferences)) { throw (Get-PvText 'Error.SnapshotTarget') }
                if ($f.backup -notmatch ('^'+[regex]::Escape($manifest.id)+'-(?:profile|preferences)\.bak$')) { throw (Get-PvText 'Error.SnapshotBackupPath') }
                $null=Get-PvRestoreFilePlan $f $stateDir
                if ((Get-PvHash (Join-Path $stateDir $f.backup)) -ne $f.beforeHash) { throw (Get-PvText 'Error.SnapshotBackupHash') }
            }
            foreach ($p in $manifest.policies) {
                $current=Get-PvPolicy $p.name $FixtureRoot
                if (-not (Test-PvPolicyEqual $current $p.after) -and -not (Test-PvPolicyEqual $current $p.before)) { throw (Get-PvText 'Error.PolicyConflict' -Arguments @($p.name)) }
            }
            $exe=$manifest.exe
            if ($manifest.files.Count) { $resume=Stop-PvFlClash @{Exe=$exe} ([bool]$Request.Restart) $FixtureRoot }
            Send-PvProgress $ProgressPath 'restore-check' (Get-PvText 'Progress.RestoreCheck') 'applied' (Get-PvText 'Progress.OriginalVerified')
            foreach ($f in $manifest.files) {
                Send-PvProgress $ProgressPath 'restore-files' (Get-PvText 'Progress.RestoreFiles') 'running' (Get-PvText 'Progress.RestoreBytes')
                $filePlan=Get-PvRestoreFilePlan $f $stateDir
                if ((Get-PvHash $f.path) -ne $filePlan.hash) { throw (Get-PvText 'Error.RestoreDrift') }
                if ($filePlan.merge) {
                    Write-AtomicText $f.path $filePlan.text
                    if ((Get-PvHash $f.path) -ne (Get-PvTextHash $filePlan.text)) { throw (Get-PvText 'Error.PreferenceMergeReadback') }
                } else {
                    Write-AtomicBytes $f.path ([IO.File]::ReadAllBytes((Join-Path $stateDir $f.backup)))
                    if ((Get-PvHash $f.path) -ne $f.beforeHash) { throw (Get-PvText 'Error.FileRestoreReadback') }
                }
            }
            Send-PvProgress $ProgressPath 'restore-files' (Get-PvText 'Progress.RestoreFiles') 'applied' (Get-PvText 'Progress.ConfigurationRestored')
            foreach ($p in $manifest.policies) {
                $current=Get-PvPolicy $p.name $FixtureRoot
                if (-not (Test-PvPolicyEqual $current $p.after) -and -not (Test-PvPolicyEqual $current $p.before)) { throw (Get-PvText 'Error.PolicyRestoreDrift' -Arguments @($p.name)) }
                Set-PvPolicy $p.name $p.before $FixtureRoot
                if (-not (Test-PvPolicyEqual (Get-PvPolicy $p.name $FixtureRoot) $p.before)) { throw (Get-PvText 'Error.PolicyRestoreReadback') }
            }
            Send-PvProgress $ProgressPath 'restore-policies' (Get-PvText 'Progress.RestorePolicies') 'applied' (Get-PvText 'Progress.EdgeRestartRequired')
            $manifest.status='restored'; $manifest.restoredAt=(Get-Date).ToString('o')
            Save-PvJson (Join-Path $stateDir "history-$($manifest.id).json") $manifest
            Remove-Item -LiteralPath (Join-Path $stateDir 'active.json')
            return @{status='Restored';active=$false;message=(Get-PvText 'Result.Restored');items=@()}
        }
        if (Get-PvActiveSnapshot $stateDir) { throw (Get-PvText 'Error.SnapshotExists') }
        $items=@($Request.Items | Select-Object -Unique)
        if (-not $items.Count -or @($items | Where-Object { $_ -notin @('DNS','WebRTC','IPv6') }).Count) { throw (Get-PvText 'Error.InvalidItems') }
        if ($Request.Mode -notin @('TUN','Proxy')) { throw (Get-PvText 'Error.InvalidMode') }
        Send-PvProgress $ProgressPath 'detect' (Get-PvText 'Progress.Detect') 'running' (Get-PvText 'Progress.ReadContext')
        $c=Get-PvContext -InstallPath $Request.InstallPath -ConfigDirectory $Request.ConfigDirectory -ProxyGroup $Request.ProxyGroup -FixtureRoot $FixtureRoot -SkipDnsGroup:('DNS' -notin $items)
        $exe=$c.Exe
        if ('DNS' -in $items -and $Request.Mode -eq 'TUN' -and $Request.Edition -eq 'Standard' -and -not $FixtureRoot) {
            $svc=Get-Service -Name FlClashHelperService -ErrorAction SilentlyContinue
            if (-not $svc -or $svc.Status -ne 'Running') { throw (Get-PvText 'Error.TunService') }
        }
        $changedFiles=('DNS' -in $items -or 'IPv6' -in $items)
        if ($changedFiles) {
            $resume=Stop-PvFlClash $c ([bool]$Request.Restart) $FixtureRoot
            $c=Get-PvContext -InstallPath $c.Exe -ConfigDirectory $c.Directory -ProxyGroup $c.Group -FixtureRoot $FixtureRoot -SkipDnsGroup:('DNS' -notin $items)
        }
        $plan=New-PvConfiguration $c $Request.Mode $items
        Send-PvProgress $ProgressPath 'detect' (Get-PvText 'Progress.Detect') 'applied' (Get-PvText 'Progress.RoutingPreserved' -Arguments @($Request.Mode))
        $id=[guid]::NewGuid().ToString('N')
        $manifest=@{schema=1;id=$id;sid=$sid;createdAt=(Get-Date).ToString('o');status='applying';mode=$Request.Mode;edition=$Request.Edition;exe=$exe;profile=$c.Profile;preferences=$c.Preferences;files=@();policies=@();items=$items}
        Save-PvManifest $manifest $stateDir
        $results=[Collections.Generic.List[object]]::new()
        try {
            if ($changedFiles) {
                Send-PvProgress $ProgressPath 'config' (Get-PvText 'Progress.BackupConfigure') 'running' (Get-PvText 'Progress.ConfigureItems')
                foreach ($f in @(@{path=$c.Profile;text=$plan.Profile;name='profile'},@{path=$c.Preferences;text=$plan.Preferences;name='preferences'})) {
                    $baseline=if ($f.name -eq 'profile') { $c.ProfileHash } else { $c.PreferencesHash }
                    if ($FixtureRoot -and $Request.Contains('Fault') -and $Request.Fault -eq 'drift-before-backup') { [IO.File]::AppendAllText($f.path,"`n# external drift") }
                    if ((Get-PvHash $f.path) -ne $baseline) { throw (Get-PvText 'Error.ConfigurationCheckDrift') }
                    $record=@{path=$f.path;backup="$id-$($f.name).bak";beforeHash=$baseline;afterHash=(Get-PvTextHash $f.text)}
                    if ($f.name -eq 'preferences') { $record.fields=Get-PvPreferenceFields $c.Inner $f.text }
                    [IO.File]::Copy($f.path,(Join-Path $stateDir $record.backup),$false)
                    if ((Get-PvHash (Join-Path $stateDir $record.backup)) -ne $baseline) { throw (Get-PvText 'Error.BackupDrift') }
                    $manifest.files+=@($record); Save-PvManifest $manifest $stateDir
                    if ($FixtureRoot -and $Request.Contains('Fault') -and $Request.Fault -eq $f.name) { throw (Get-PvText 'Test.ConfigurationWriteFault') }
                    if ((Get-PvHash $f.path) -ne $record.beforeHash) { throw (Get-PvText 'Error.ConfigurationBackupDrift') }
                    Write-AtomicText $f.path $f.text
                    if ((Get-PvHash $f.path) -ne $record.afterHash) { throw (Get-PvText 'Error.ConfigurationReadback') }
                }
                Send-PvProgress $ProgressPath 'config' (Get-PvText 'Progress.BackupConfigure') 'applied' (Get-PvText 'Progress.ConfigurationWritten')
            }
            foreach ($item in $items) {
                $label=switch ($item) { DNS {(Get-PvText 'Item.DNS')} WebRTC {(Get-PvText 'Item.WebRTC')} IPv6 {(Get-PvText 'Item.IPv6')} }
                Send-PvProgress $ProgressPath $item $label 'running' (Get-PvText 'Progress.CheckItem')
                $names=switch ($item) { DNS {@($plan.Policies.Keys | Where-Object { $_ -like 'Dns*' })} WebRTC {@($plan.Policies.Keys | Where-Object { $_ -like 'WebRtc*' })} IPv6 {@()} }
                $skipped=[Collections.Generic.List[string]]::new()
                foreach ($name in $names) {
                    $target=$plan.Policies[$name]; $machine=Get-PvPolicy $name $FixtureRoot -Machine
                    if ($machine.Exists -and -not (Test-PvPolicyEqual $machine $target)) { $skipped.Add((Get-PvText 'Error.OrganizationPolicy')); continue }
                    $before=Get-PvPolicy $name $FixtureRoot
                    $record=@{name=$name;before=$before;after=$target}
                    $manifest.policies+=@($record); Save-PvManifest $manifest $stateDir
                    try {
                        Set-PvPolicy $name $target $FixtureRoot
                        if (-not (Test-PvPolicyEqual (Get-PvPolicy $name $FixtureRoot) $target)) { throw (Get-PvText 'Error.PolicyReadback') }
                    } catch [UnauthorizedAccessException] {
                        $manifest.policies=@($manifest.policies | Where-Object { $_ -ne $record }); Save-PvManifest $manifest $stateDir
                        $skipped.Add((Get-PvText 'Error.PolicyPermission')); continue
                    } catch [Security.SecurityException] {
                        $manifest.policies=@($manifest.policies | Where-Object { $_ -ne $record }); Save-PvManifest $manifest $stateDir
                        $skipped.Add((Get-PvText 'Error.PolicyPermission')); continue
                    }
                }
                $status=if ($skipped.Count) { 'skipped' } else { 'applied' }
                $detail=if ($skipped.Count) { ($skipped | Select-Object -Unique) -join (Get-PvText 'Text.Separator') } else { switch ($item) { DNS { if ($Request.Mode -eq 'Proxy') {(Get-PvText 'Detail.DnsProxy')} else {(Get-PvText 'Detail.DnsTun')} } WebRTC {(Get-PvText 'Detail.WebRTC')} IPv6 {(Get-PvText 'Detail.IPv6')} } }
                Send-PvProgress $ProgressPath $item $label $status $detail
                $results.Add(@{id=$item;status=$status;detail=$detail})
            }
            $manifest.status='configured'; Save-PvManifest $manifest $stateDir
        } catch {
            $cause=$_.Exception.Message
            $rollback=$true
            foreach ($p in @($manifest.policies)) {
                try {
                    $current=Get-PvPolicy $p.name $FixtureRoot
                    if (Test-PvPolicyEqual $current $p.after) { Set-PvPolicy $p.name $p.before $FixtureRoot }
                    elseif (-not (Test-PvPolicyEqual $current $p.before)) { $rollback=$false }
                } catch { $rollback=$false }
            }
            foreach ($f in @($manifest.files)) {
                try {
                    $hash=Get-PvHash $f.path
                    if ($hash -eq $f.afterHash) { Write-AtomicBytes $f.path ([IO.File]::ReadAllBytes((Join-Path $stateDir $f.backup))) }
                    elseif ($hash -ne $f.beforeHash) { $rollback=$false }
                } catch { $rollback=$false }
            }
            if ($rollback) { Remove-Item -LiteralPath (Join-Path $stateDir 'active.json') }
            else { $manifest.status='recovery-required'; Save-PvManifest $manifest $stateDir }
            throw (Get-PvText 'Error.RollbackCause' -Arguments @($cause,$(if ($rollback) { Get-PvText 'Result.RolledBack' } else { Get-PvText 'Result.RollbackBlocked' })))
        }
        $active=$manifest.files.Count -gt 0 -or $manifest.policies.Count -gt 0
        if (-not $active) { Remove-Item -LiteralPath (Join-Path $stateDir 'active.json') }
        $partial=@($results | Where-Object { $_.status -eq 'skipped' }).Count -gt 0
        if ($changedFiles -and $Request.Restart -and -not $FixtureRoot) { $resume=$true }
        $restartMessage=if ($changedFiles -and -not $resume) { (Get-PvText 'Result.OpenFlClash') } else { '' }
        @{status=$(if ($partial) {'Partial'} else {'Configured'});active=$active;items=$results.ToArray();message=(Get-PvText 'Result.Configured' -Arguments @($restartMessage))}
    } finally {
        try { if ($resume -and $exe) { Start-PvFlClash $exe $FixtureRoot; Send-PvProgress $ProgressPath 'restart' (Get-PvText 'Progress.Restart') 'applied' (Get-PvText 'Progress.Restarted') } }
        finally { $lock.Dispose() }
    }
}
function Invoke-PvOperation {
    [CmdletBinding()]
    param([Collections.IDictionary]$Request,[string]$ProgressPath,[string]$FixtureRoot)
    $previousLanguage=Get-PvLanguage
    try {
        if ($Request.Contains('Language') -and $Request.Language) { Set-PvLanguage $Request.Language }
        Invoke-PvOperationCore $Request $ProgressPath $FixtureRoot
    } finally { Set-PvLanguage $previousLanguage }
}
Export-ModuleMember -Function Get-PvContext,Get-PvIdentity,Test-PvAdministrator,Get-PvDefaultStateDirectory,Get-PvActiveSnapshot,Invoke-PvOperation,New-PvConfiguration,Read-PvJson,Save-PvJson,Get-PvPolicy,Set-PvPolicy,Test-PvPolicyEqual,Read-PvProgressLines,Resolve-PvLanguage,Get-PvDisplayCulture,Set-PvLanguage,Get-PvLanguage,Get-PvStrings,Get-PvText
