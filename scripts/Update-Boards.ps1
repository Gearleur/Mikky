param([switch]$NoBuild, [string]$FlutterRoot = '')
# The boards after a change of the app (2026-10-05): takes the test
# pictures again (every test tagged golden), builds a bundle and opens
# the boards from it. -NoBuild: the pictures only.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Find-Flutter.ps1')
$FlutterRoot = Find-FlutterRoot $FlutterRoot
$mikkyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$mikkyApp = Join-Path $mikkyRoot 'app'
$flutter = Join-Path $FlutterRoot 'bin\flutter.bat'
Push-Location $mikkyApp
try {
    & $flutter test --update-goldens --tags golden
    if ($LASTEXITCODE -ne 0) { throw 'Les images de test n''ont pas pu être refaites' }
    # Left by failed runs: not ours to keep.
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $mikkyApp 'test\failures')
} finally {
    Pop-Location
}
if ($NoBuild) { return }
& (Join-Path $PSScriptRoot 'Build-Windows.ps1') -FlutterRoot $FlutterRoot
# Only the boards' windows close; the island goes on.
Get-CimInstance Win32_Process -Filter "Name='mikky.exe'" | Where-Object { $_.CommandLine -like '*--kit*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Confirm:$false }
& (Join-Path $mikkyRoot 'Start-Mikky.ps1') -Boards
