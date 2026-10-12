@echo off
setlocal
set "PV_PWSH=pwsh.exe"
where pwsh.exe >nul 2>nul
if not errorlevel 1 goto launch
set "PV_PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if exist "%PV_PWSH%" goto launch
set "PV_PWSH=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe"
if exist "%PV_PWSH%" goto launch
powershell.exe -NoProfile -NonInteractive -File "%~dp0scripts\Show-RuntimeRequirement.ps1"
if errorlevel 1 echo PowerShell 7 is required. Install it and add pwsh.exe to PATH.
pause
exit /b 1
:launch
start "" "%PV_PWSH%" -NoProfile -WindowStyle Hidden -STA -File "%~dp0scripts\Launch.ps1" -Edition Administrator
