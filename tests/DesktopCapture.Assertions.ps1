function Assert-PvDesktopContent([Drawing.Bitmap]$Bitmap) {
    # Test-Desktop calls this before publishing a screen capture. This window's
    # dark text and blue/green action button must survive desktop composition.
    $dark=0; $accent=0
    for ($y=30; $y -lt $Bitmap.Height-30; $y+=3) {
        for ($x=30; $x -lt $Bitmap.Width-30; $x+=3) {
            $color=$Bitmap.GetPixel($x,$y)
            if ($color.R -lt 110 -and $color.G -lt 110 -and $color.B -lt 130) { $dark++ }
            if (($color.B -ge 160 -or $color.G -ge 115) -and $color.B-$color.R -gt 45 -and $color.G-$color.R -gt 10) { $accent++ }
        }
    }
    if ($dark -lt 20 -or $accent -lt 20) {
        throw "Desktop content missing: dark text samples=$dark, action-button samples=$accent."
    }
}
