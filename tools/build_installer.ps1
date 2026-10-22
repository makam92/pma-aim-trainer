# Builds build\installer\PMA-Aim-Trainer-Setup.exe: exports the game with Godot and packs it with
# Inno Setup, together with Source 2 Viewer's command line tool for importing the CS2 files.
# Needs Godot 4.7.2 with its export templates, Inno Setup 7 in %LOCALAPPDATA%\Programs\Inno Setup 7
# and Source 2 Viewer in %LOCALAPPDATA%\Programs\Source2Viewer.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$godot = Join-Path $env:LOCALAPPDATA 'Programs\Godot\Godot_v4.7.2-stable_win64_console.exe'
$iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'
$s2v = Join-Path $env:LOCALAPPDATA 'Programs\Source2Viewer'
foreach ($need in $godot, $iscc, (Join-Path $s2v 'Source2Viewer-CLI.exe')) {
	if (-not (Test-Path $need)) { throw "Saknas: $need" }
}

Write-Host 'Ikon och licensfil ...'
& $godot --headless --path $root --script res://tools/installer_files.gd
if ($LASTEXITCODE -ne 0) { throw 'Kunde inte göra ikonen och licensfilen.' }

Write-Host 'Exporterar spelet ...'
$exe = Join-Path $root 'build\export\PMA Aim Trainer.exe'
& $godot --headless --path $root --export-release Windows $exe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw 'Exporten misslyckades.' }

Write-Host 'Bygger installern ...'
& $iscc /Q "/DSource2Viewer=$s2v" (Join-Path $PSScriptRoot 'installer\installer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup misslyckades.' }
Get-Item (Join-Path $root 'build\installer\PMA-Aim-Trainer-Setup.exe') |
	ForEach-Object { '{0}  {1:N0} MB' -f $_.FullName, ($_.Length / 1MB) }
