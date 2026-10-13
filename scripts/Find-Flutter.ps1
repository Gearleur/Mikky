# Where the Flutter SDK is: -FlutterRoot, then FLUTTER_ROOT, then the
# `flutter` on the PATH, then C:\dev\flutter. Dot-sourced by the scripts.
function Find-FlutterRoot([string]$given = '') {
    foreach ($candidate in @($given, $env:FLUTTER_ROOT)) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'bin'))) { return $candidate }
    }
    $onPath = Get-Command flutter -ErrorAction SilentlyContinue
    if ($onPath) { return Split-Path (Split-Path $onPath.Source) }
    if (Test-Path -LiteralPath 'C:\dev\flutter\bin') { return 'C:\dev\flutter' }
    throw 'Flutter not found: pass -FlutterRoot, set FLUTTER_ROOT or put flutter on the PATH.'
}
