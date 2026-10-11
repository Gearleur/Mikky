<#
.SYNOPSIS
    Every check of the repo, the same ones CI runs: formatting, analysis, tests.

.DESCRIPTION
    Run it before pushing. CI (.github/workflows/ci.yml) calls this script one
    section at a time, so a green run here means a green run there.

.EXAMPLE
    scripts\Check.ps1                  # everything
    scripts\Check.ps1 -Only app        # one section: rust, engine, agents, app
    scripts\Check.ps1 -Fix             # format the code instead of only checking it
#>
param(
    # Sections: all, quality, rust, engine, agents, app (several: rust,agents).
    [string[]]$Only = @('all'),
    [string]$FlutterRoot = '',
    [switch]$Fix
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$onWindows = [IO.Path]::DirectorySeparatorChar -eq '\'

# --------------------------------------------------------------- tools

function Find-Flutter {
    foreach ($candidate in @($FlutterRoot, $env:FLUTTER_ROOT, 'C:\dev\flutter')) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'bin'))) {
            return Join-Path $candidate 'bin'
        }
    }
    $onPath = Get-Command flutter -ErrorAction SilentlyContinue
    if ($onPath) { return Split-Path $onPath.Source }
    throw 'Flutter not found: pass -FlutterRoot or set FLUTTER_ROOT.'
}

function Find-Cargo {
    $onPath = Get-Command cargo -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
    $local = Join-Path $home_ '.cargo/bin/cargo'
    if ($onWindows) { $local += '.exe' }
    if (Test-Path -LiteralPath $local) { return $local }
    throw 'cargo not found: install Rust (https://rustup.rs).'
}

$script:failed = @()

# Runs one command in a folder; a failure is recorded, the other steps still run.
function Invoke-Step([string]$name, [string]$dir, [string]$exe, [string[]]$arguments) {
    Write-Host ''
    Write-Host "==> $name" -ForegroundColor Cyan
    Push-Location (Join-Path $root $dir)
    try {
        & $exe @arguments
        if ($LASTEXITCODE -ne 0) { $script:failed += $name }
    } finally {
        Pop-Location
    }
}

# --------------------------------------------------------------- sections

function Test-Rust {
    $cargo = Find-Cargo
    if ($Fix) {
        Invoke-Step 'rust: format' 'daemon' $cargo @('fmt', '--all')
    } else {
        Invoke-Step 'rust: format' 'daemon' $cargo @('fmt', '--all', '--', '--check')
    }
    Invoke-Step 'rust: clippy' 'daemon' $cargo @('clippy', '--workspace', '--all-targets', '--locked', '--', '-D', 'warnings')
    # The relay test and the Dart daemon tests start these binaries: build them first.
    Invoke-Step 'rust: build' 'daemon' $cargo @('build', '--workspace', '--all-targets', '--locked')
    Invoke-Step 'rust: test' 'daemon' $cargo @('test', '--workspace', '--locked')
}

# No code repeated (8 lines or more, see .jscpd.json): what is shared goes
# in one place.
function Test-Quality {
    # npx.cmd on Windows: PowerShell may refuse to run npx.ps1.
    $npx = Get-Command $(if ($onWindows) { 'npx.cmd' } else { 'npx' }) -ErrorAction SilentlyContinue
    if (!$npx) { throw 'npx not found: install Node.js (https://nodejs.org).' }
    Invoke-Step 'quality: no repeated code' '.' $npx.Source @('--yes', 'jscpd@4.0.5', '--config', '.jscpd.json',
        'app/lib', 'app/windows/runner', 'packages/mikky_engine/lib', 'packages/mikky_agents/lib', 'daemon')
}

# A Dart package: format, analysis (infos fail too), tests.
function Test-DartPackage([string]$dir, [string]$tool) {
    $dart = Join-Path $bin "dart$ext"
    $name = Split-Path $dir -Leaf
    $folders = @('lib', 'test', 'tool', 'bin') | Where-Object { Test-Path -LiteralPath (Join-Path $root "$dir/$_") }
    Invoke-Step "${name}: dependencies" $dir $tool @('pub', 'get')
    if ($Fix) {
        Invoke-Step "${name}: format" $dir $dart (@('format') + $folders)
    } else {
        Invoke-Step "${name}: format" $dir $dart (@('format', '--output=none', '--set-exit-if-changed') + $folders)
    }
    Invoke-Step "${name}: analyze" $dir $tool @('analyze', '--fatal-infos')
    Invoke-Step "${name}: test" $dir $tool @('test')
}

$all = @('quality', 'rust', 'engine', 'agents', 'app')
# `-File` passes « rust,agents » as one string: split it.
$asked = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$unknown = @($asked | Where-Object { $_ -ne 'all' -and $all -notcontains $_ })
if ($unknown.Count -gt 0) { throw "Unknown section: $($unknown -join ', ') (all, $($all -join ', '))" }
$sections = if ($asked -contains 'all') { $all } else { $asked }
$bin = $null
if ($sections | Where-Object { $_ -notin @('rust', 'quality') }) { $bin = Find-Flutter }
$ext = if ($onWindows) { '.bat' } else { '' }

foreach ($section in $sections) {
    switch ($section) {
        'quality' { Test-Quality }
        'rust' { Test-Rust }
        'engine' { Test-DartPackage 'packages/mikky_engine' (Join-Path $bin "dart$ext") }
        'agents' {
            # Its tests start the daemon built by the rust section.
            if ($sections -notcontains 'rust') {
                Invoke-Step 'rust: build' 'daemon' (Find-Cargo) @('build', '--workspace', '--all-targets', '--locked')
            }
            Test-DartPackage 'packages/mikky_agents' (Join-Path $bin "dart$ext")
        }
        'app' { Test-DartPackage 'app' (Join-Path $bin "flutter$ext") }
    }
}

Write-Host ''
if ($script:failed.Count -gt 0) {
    Write-Host "FAILED: $($script:failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host 'All checks passed.' -ForegroundColor Green
