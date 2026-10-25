param([string]$FlutterRoot = '', [string]$BuildDirectory = 'build/release-ready')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Find-Flutter.ps1')
$FlutterRoot = Find-FlutterRoot $FlutterRoot
$mikkyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$mikkyApp = Join-Path $mikkyRoot 'app'
$mikkyBuildPath = [IO.Path]::GetFullPath((Join-Path $mikkyApp $BuildDirectory))
$mikkyBuildRoot = [IO.Path]::GetFullPath((Join-Path $mikkyApp 'build'))
if (!$mikkyBuildPath.StartsWith($mikkyBuildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'BuildDirectory must stay inside app/build'
}
$mikkyDart = Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
$mikkyFlutter = Join-Path $FlutterRoot 'bin\cache\flutter_tools.snapshot'
if (!(Test-Path -LiteralPath $mikkyDart)) { throw "Flutter SDK absent: $FlutterRoot" }
$mikkyOriginalAppData = $env:APPDATA
Push-Location $mikkyApp
try {
    # Private CLI configuration: do not modify the developer's Flutter settings.
    $env:APPDATA = Join-Path $mikkyApp 'build\release-tool-state'
    [IO.Directory]::CreateDirectory($env:APPDATA) | Out-Null
    $mikkyFlutterSettings = @{ 'build-dir' = $BuildDirectory.Replace('\', '/'); 'enable-windows-desktop' = $true } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $env:APPDATA '.flutter_settings'), $mikkyFlutterSettings)
    & $mikkyDart $mikkyFlutter --suppress-analytics pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed' }
    & $mikkyDart $mikkyFlutter --suppress-analytics build windows --release --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    $mikkyBundle = Join-Path $mikkyBuildPath 'windows\x64\runner\Release'
    foreach ($name in @('mikky.exe','mikkyd.exe','mikky-hook.exe','mikkyd-linux','flutter_windows.dll','data')) {
        if (!(Test-Path -LiteralPath (Join-Path $mikkyBundle $name))) { throw "Incomplete bundle: $name" }
    }
    # Versioned directories preserve binaries used by already-running windows.
    $mikkyVersion = 'Mikky-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    $mikkyDist = Join-Path $mikkyRoot 'dist'
    $mikkyDestination = Join-Path $mikkyDist $mikkyVersion
    [IO.Directory]::CreateDirectory($mikkyDestination) | Out-Null
    Get-ChildItem -LiteralPath $mikkyBundle | Copy-Item -Destination $mikkyDestination -Recurse
    [IO.File]::WriteAllText((Join-Path $mikkyDist 'current.txt'), $mikkyVersion)
    Write-Output "Bundle ready: $mikkyDestination"
} finally {
    $env:APPDATA = $mikkyOriginalAppData
    Pop-Location
}
