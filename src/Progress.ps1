function Read-PvProgressLines([string]$Path) {
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
    try { return ,@($reader.ReadToEnd() -split '\r?\n' | Where-Object { $_.Length }) }
    finally { $reader.Dispose() }
}
