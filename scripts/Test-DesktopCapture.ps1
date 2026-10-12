#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Add-Type -AssemblyName System.Drawing
. "$root/tests/DesktopCapture.Assertions.ps1"
$checks=0
foreach ($color in @([Drawing.Color]::FromArgb(0,64,128),[Drawing.Color]::Black,[Drawing.Color]::White,[Drawing.Color]::FromArgb(35,94,232),[Drawing.Color]::FromArgb(21,124,112))) {
    $bitmap=[Drawing.Bitmap]::new(200,200)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear($color)
        $rejected=$false
        try { Assert-PvDesktopContent $bitmap } catch { $rejected=$true }
        if (-not $rejected) { throw "Uniform background incorrectly accepted: $color" }
        $checks++
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
}
foreach ($language in @('en','zh-CN')) {
    foreach ($state in @('idle','settings','completed')) {
        $bitmap=[Drawing.Bitmap]::new("$root/docs/validation/i18n-$language-$state.png")
        try { Assert-PvDesktopContent $bitmap; $checks++ } finally { $bitmap.Dispose() }
    }
}
"PASS: $checks desktop capture content regressions"
