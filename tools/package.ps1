# Builds dist\FS25_Casino.zip (files at the zip root, as the game and ModHub expect).
#   powershell -ExecutionPolicy Bypass -File tools\package.ps1
# Writes the archive by hand because Compress-Archive in Windows PowerShell 5.1 stores paths with backslashes.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$src = Join-Path $root 'FS25_Casino'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist 'FS25_Casino.zip'
if (Test-Path $zip) { Remove-Item $zip }

$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem $src -Recurse -File | ForEach-Object {
        $entry = $_.FullName.Substring($src.Length + 1).Replace('\', '/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $archive.Dispose()
}
Write-Host "Wrote $zip"
