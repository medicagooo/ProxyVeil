# UI, core and worker share these resources. Language changes affect presentation
# only: status IDs, requests, profile values and snapshot schemas stay invariant.
$script:PvEnglish = Import-PowerShellDataFile -LiteralPath "$PSScriptRoot/Locales/en.psd1"
$script:PvChinese = Import-PowerShellDataFile -LiteralPath "$PSScriptRoot/Locales/zh-CN.psd1"
function Get-PvDisplayCulture {
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        if (-not ('PvDisplayLanguage' -as [type])) {
            Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class PvDisplayLanguage {
    [DllImport("kernel32.dll")] public static extern ushort GetUserDefaultUILanguage();
}
'@
        }
        try { return [Globalization.CultureInfo]::GetCultureInfo([int][PvDisplayLanguage]::GetUserDefaultUILanguage()).Name }
        catch [Globalization.CultureNotFoundException] {}
    }
    return [Globalization.CultureInfo]::CurrentUICulture.Name
}
function Resolve-PvLanguage {
    param([ValidateSet('Auto','en','zh-CN')][string]$Language='Auto',[string]$CultureName)
    if ($Language -ne 'Auto') { return $Language }
    if (-not $PSBoundParameters.ContainsKey('CultureName')) { $CultureName=Get-PvDisplayCulture }
    if ($CultureName -match '^zh(?:-|$)') { return 'zh-CN' }
    return 'en'
}
function Set-PvLanguage([ValidateSet('Auto','en','zh-CN')][string]$Language='Auto') {
    $script:PvLanguage=Resolve-PvLanguage -Language $Language
}
function Get-PvLanguage { return $script:PvLanguage }
function Get-PvStrings {
    if ($script:PvLanguage -eq 'zh-CN') { return @{} + $script:PvChinese }
    return @{} + $script:PvEnglish
}
function Get-PvText {
    param([Parameter(Mandatory)][string]$Key,[object[]]$Arguments=@())
    if (-not $script:PvEnglish.ContainsKey($Key)) { throw "Unknown localization key: $Key" }
    $text=$script:PvEnglish[$Key]
    if ($script:PvLanguage -eq 'zh-CN' -and $script:PvChinese.ContainsKey($Key)) { $text=$script:PvChinese[$Key] }
    return [string]::Format([Globalization.CultureInfo]::InvariantCulture,$text,$Arguments)
}
Set-PvLanguage
