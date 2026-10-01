param([switch]$Island, [switch]$Boards, [switch]$InstallStartup)
$ErrorActionPreference = 'Stop'
$mikkyDist = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'dist'))
$mikkyManifest = Join-Path $mikkyDist 'current.txt'
if (!(Test-Path -LiteralPath $mikkyManifest)) { throw 'Compile d’abord : .\scripts\Build-Windows.ps1' }
$mikkyVersion = [IO.File]::ReadAllText($mikkyManifest).Trim()
$mikkyBundle = [IO.Path]::GetFullPath((Join-Path $mikkyDist $mikkyVersion))
if (!$mikkyBundle.StartsWith($mikkyDist + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid bundle path' }
$mikkyExe = Join-Path $mikkyBundle 'mikky.exe'
if ($InstallStartup) {
    $mikkySetup = Start-Process -FilePath (Join-Path $mikkyBundle 'mikkyd.exe') -ArgumentList '--autostart','enable' -WindowStyle Hidden -Wait -PassThru
    if ($mikkySetup.ExitCode -ne 0) { throw 'Windows n’a pas pu enregistrer le démarrage automatique.' }
}
if ($Boards) { Start-Process -FilePath $mikkyExe -WorkingDirectory $mikkyBundle -ArgumentList '--kit' }
elseif ($Island) { Start-Process -FilePath $mikkyExe -WorkingDirectory $mikkyBundle }
else { Start-Process -FilePath $mikkyExe -WorkingDirectory $mikkyBundle -ArgumentList '--home' }
