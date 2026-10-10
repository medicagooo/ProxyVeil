#requires -Version 7.0
param([switch]$ExpectFailure)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$module=Import-Module "$root\src\ProxyVeil.Core.psm1" -Force -PassThru
$path='Software\ProxyVeil.Test-'+[guid]::NewGuid().ToString('N')
$key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path,$true)
$failed=[Collections.Generic.List[string]]::new(); $passed=0
try {
    $cases=@(
        @{Type='MultiString';Value=[string[]]@('a b','c')},
        @{Type='MultiString';Value=[string[]]@('single')},
        @{Type='MultiString';Value=[string[]]@()},
        @{Type='Binary';Value=[byte[]]@(0,128,255)},
        @{Type='Binary';Value=[byte[]]@(1)},
        @{Type='Binary';Value=[byte[]]@()},
        @{Type='None';Value=[byte[]]@(1,2)},
        @{Type='ExpandString';Value='%TEMP%\ProxyVeil'},
        @{Type='DWord';Value=42},
        @{Type='QWord';Value=4294967296},
        @{Type='String';Value='ordinary'}
    )
    foreach ($case in $cases) {
        $name='roundtrip'; $case.Exists=$true
        try {
            $key.SetValue($name,$case.Value,[Microsoft.Win32.RegistryValueKind]::$($case.Type))
            $snapshot=& $module { param($k,$n) Get-PvRegistryValue $k $n } $key $name
            $expected=ConvertTo-Json -InputObject $case.Value -Compress
            if ((ConvertTo-Json -InputObject $snapshot.Value -Compress) -cne $expected) { throw 'Snapshot changed original bytes/text' }
            $persisted=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $snapshot) -AsHashtable
            $key.DeleteValue($name)
            & $module { param($k,$n,$v) Set-PvRegistryValue $k $n $v } $key $name $persisted
            $actual=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($key.GetValueKind($name).ToString() -cne $case.Type -or (ConvertTo-Json -InputObject $actual -Compress) -cne $expected) { throw 'Restore changed original registry data' }
            $passed++; "PASS: native $($case.Type) [$($case.Value.Count)]"
        } catch { $failed.Add("$($case.Type): $($_.Exception.Message)"); "FAIL: native $($case.Type)" }
    }
} finally {
    $key.Dispose()
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($path,$false)
}
if ($ExpectFailure) {
    if (-not $failed.Count) { throw 'Expected native registry regression' }
    $failed; return
}
if ($failed.Count) { throw ($failed -join "`n") }
Save-PvJson "$root\docs\validation\registry.json" @{at=(Get-Date).ToString('o');passed=$passed;result='passed';scope='native HKCU temporary key; persisted snapshot roundtrip';liveConfigurationModified=$false}
"PASS: $passed native registry roundtrips"
