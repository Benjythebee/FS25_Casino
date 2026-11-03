# Builds dist\FS25_Casino.zip (files at the zip root, as the game and ModHub expect).
#   powershell -ExecutionPolicy Bypass -File tools\package.ps1
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$src = Join-Path $root 'FS25_Casino'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist 'FS25_Casino.zip'
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $src '*') -DestinationPath $zip
Write-Host "Wrote $zip"
