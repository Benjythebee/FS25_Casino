# Links FS25_Casino into the game's mods folder (a junction, so edits are live), or copies it with -Copy.
#   powershell -ExecutionPolicy Bypass -File tools\install.ps1 [-Copy]
param([switch]$Copy)

$src = (Resolve-Path (Join-Path $PSScriptRoot '..\FS25_Casino')).Path
$mods = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\FarmingSimulator2025\mods'
$dst = Join-Path $mods 'FS25_Casino'

if (Test-Path $dst) {
    $item = Get-Item $dst -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        # remove only the link, never the files it points to
        [IO.Directory]::Delete($dst)
    } elseif ($Copy) {
        Remove-Item $dst -Recurse -Force
    } else {
        Write-Error "$dst exists and is a real folder; rerun with -Copy to replace it"
        exit 1
    }
}

if ($Copy) {
    Copy-Item $src $dst -Recurse
    Write-Host "Copied to $dst"
} else {
    New-Item -ItemType Junction -Path $dst -Target $src | Out-Null
    Write-Host "Linked $dst -> $src"
}
