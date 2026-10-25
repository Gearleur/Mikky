<#
.SYNOPSIS
    Parcours visuel interactif de la vraie notch, sans appel a un modele.
.EXAMPLE
    .\scripts\Test-Notch.ps1
.EXAMPLE
    .\scripts\Test-Notch.ps1 -Verify
#>
param([string]$AppPath = '', [switch]$Verify, [string]$FlutterRoot = '')
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'Find-Flutter.ps1')
$taskSdk = Find-FlutterRoot $FlutterRoot
$taskDart = Join-Path $taskSdk 'bin\cache\dart-sdk\bin\dart.exe'
if (!(Test-Path -LiteralPath $taskDart)) { throw 'Le SDK Dart de Flutter est introuvable.' }

if (!$Verify) {
    $Host.UI.RawUI.WindowTitle = 'Mikky - Test interactif de la notch'
    if (!$AppPath) {
        $taskReviewPointer = Join-Path $taskRoot 'dist\notch-test-app.txt'
        if (Test-Path -LiteralPath $taskReviewPointer) {
            $taskReviewPath = [IO.File]::ReadAllText($taskReviewPointer).Trim()
            if (Test-Path -LiteralPath $taskReviewPath) { $AppPath = $taskReviewPath }
        }
    }
    $taskIslands = @(Get-CimInstance Win32_Process -Filter "Name='mikky.exe'" | Where-Object {
        $_.CommandLine -notmatch '--kit|--tuning|--bench|--perf' -and
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith($taskRoot + '\', [StringComparison]::OrdinalIgnoreCase)
    })
    if ($AppPath) {
        $taskApp = [IO.Path]::GetFullPath($AppPath)
        if (!(Test-Path -LiteralPath $taskApp)) { throw "Application introuvable : $taskApp" }
        if ($taskIslands.Count -gt 1) { throw 'Plusieurs iles Mikky sont ouvertes : garde une seule ile avant ce test.' }
        if ($taskIslands.Count -eq 1 -and $taskIslands[0].ExecutablePath -ne $taskApp) {
            # Only the local UI is replaced. No daemon, real agent or board is stopped.
            Stop-Process -Id $taskIslands[0].ProcessId
            $taskIslands = @()
        }
        if ($taskIslands.Count -eq 0) {
            Start-Process -FilePath $taskApp -WorkingDirectory (Split-Path $taskApp) -WindowStyle Normal
            Start-Sleep -Seconds 2
        }
    } elseif ($taskIslands.Count -eq 0) {
        & (Join-Path $taskRoot 'Start-Mikky.ps1')
        Start-Sleep -Seconds 2
    }
    Write-Host 'TEST NOTCH : tache simulee, vraies interactions avec le moteur local.' -ForegroundColor Cyan
    Write-Host 'Reponds dans la notch. Entre les etapes, reviens ici et appuie sur Entree.'
    Write-Host 'q aux pauses ou Ctrl+C pendant le test : arret et nettoyage.'
    Write-Host 'Ne ferme pas brutalement cette fenetre avant le nettoyage.'
}

Push-Location (Join-Path $taskRoot 'packages\mikky_agents')
try {
    $taskArguments = @('run', 'tool/notch_walkthrough.dart')
    if ($Verify) { $taskArguments += '--verify' }
    & $taskDart @taskArguments
    if ($LASTEXITCODE -ne 0) { throw "Le parcours de test a echoue (code $LASTEXITCODE)." }
} finally {
    Pop-Location
}
