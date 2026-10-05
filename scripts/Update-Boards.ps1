param([switch]$NoBuild, [string]$FlutterRoot = 'C:\dev\flutter')
# The boards after a change of the app (2026-10-05): takes the test
# pictures again (every golden test of app\test), builds a bundle and opens
# the boards from it. -NoBuild: the pictures only.
$ErrorActionPreference = 'Stop'
$mikkyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$mikkyApp = Join-Path $mikkyRoot 'app'
$flutter = Join-Path $FlutterRoot 'bin\flutter.bat'
Push-Location $mikkyApp
try {
    $tests = Get-ChildItem -Path test -Filter '*_test.dart' | Where-Object { Select-String -Path $_.FullName -Pattern 'matchesGoldenFile' -Quiet } | ForEach-Object { "test/$($_.Name)" }
    Write-Output "Images de test : $($tests -join ', ')"
    & $flutter test --update-goldens @tests
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
