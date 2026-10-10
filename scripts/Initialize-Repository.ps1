#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
if ((Test-Path -LiteralPath (Join-Path $root '.git')) -or (Test-Path -LiteralPath (Join-Path $root 'BRANCHES.md'))) {
    throw '项目已经初始化，拒绝重新生成或覆盖业务登记。'
}
$task = 'initial-v1'
$now = (Get-Date).ToString('o')
$state = @{purpose='ProxyVeil v1: FlClash privacy repair and restore'; requirements=@('docs/spec-v1.md'); constraints=@('PowerShell 7 / Windows','Local implementation only','No live machine repair during tests'); acceptance=@('isolated engine and UI tests','Standard/Admin and TUN/Proxy','restore with conflict protection'); status='active'; integration='unmerged'; evidence=@('docs/adr/0001-desktop-and-recovery.md'); next='Implement engine and UI'}
$state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath "$root\.branch-records\$task\state.json" -Encoding utf8
$events = @(
 @{id='request-v1';at=$now;type='user_request';source='current conversation / 2026-10-10';summary='Create local Windows FlClash privacy app under D:\proj using idea-to-ship-flow; PowerShell 7; glass UI; repair and restore; Standard/Admin; TUN/Proxy';authorization='local files, implementation, testing, local git; no push or live configuration apply';supersedes=@()},
 @{id='init-v1';at=$now;type='operation';source='request-v1';operation=@{name='git init';ref='1010-initial-v1';base=$null;path=$root;before='new directory, no repository';after='local repository on 1010-initial-v1'};reason='track local implementation and recovery evidence'}
)
$events | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress } | Set-Content -LiteralPath "$root\.branch-records\$task\events.jsonl" -Encoding utf8
@{schema=1;timezone='America/Halifax';records=@(@{id=$task;state=".branch-records/$task/state.json";events=".branch-records/$task/events.jsonl"});active=@($task);pending=@(@{task=$task;event='init-v1'});read=@('docs/spec-v1.md');changes=@(@{id='privacy-v1';date='2026-10-10';domain='desktop privacy';business='Standalone script becomes selectable FlClash TUN/Proxy repair with glass UI, privilege editions and persistent restore';before='CLI script';after='Planned desktop application';status='planned';request='request-v1';evidence=@('docs/spec-v1.md');implementedAt=$null;integratedAt=$null;deployedAt=$null})} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath "$root\BRANCHES.md" -Encoding utf8
& git -C $root init -b 1010-initial-v1
if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
& git -C $root status --short
if ($LASTEXITCODE -ne 0) { throw 'git status failed' }
