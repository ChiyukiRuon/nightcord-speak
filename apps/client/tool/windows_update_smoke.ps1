param([switch]$Installer)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$root = Join-Path $workspace ('run/windows-update-smoke-' + [Guid]::NewGuid().ToString('N'))
if (-not $root.StartsWith($workspace + '\run\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid smoke directory' }
New-Item -ItemType Directory -Path $root | Out-Null
$target = Join-Path $root 'portable client'
$packageRoot = Join-Path $root 'package'
$bundle = Join-Path $packageRoot 'Nightcord-Speak-0.3.0-windows-x64'
New-Item -ItemType Directory -Path $target,$bundle -Force | Out-Null
function Build-Stub([string]$path, [string]$label) {
    $source = @'
using System;
using System.IO;
using System.Threading;
public class UpdateStub {
  public static void Main() {
    File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "launched"), "LABEL");
    string marker = Environment.GetEnvironmentVariable("NIGHTCORD_UPDATE_SMOKE_WAIT");
    if (marker != null) while (!File.Exists(marker)) Thread.Sleep(50);
  }
}
'@
    Add-Type -TypeDefinition ($source.Replace('LABEL', $label)) -OutputAssembly $path -OutputType ConsoleApplication
}
Build-Stub (Join-Path $target 'Nightcord Speak.exe') 'old'
Build-Stub (Join-Path $bundle 'Nightcord Speak.exe') 'new'
foreach ($location in @($target, $bundle)) {
    New-Item -ItemType Directory -Path (Join-Path $location 'data/flutter_assets') -Force | Out-Null
    foreach ($name in @('nightcord_ffi.dll', 'flutter_windows.dll', 'data/flutter_assets/AssetManifest.bin')) {
        [IO.File]::WriteAllText((Join-Path $location $name), $(if ($location -eq $target) { 'old' } else { 'new' }))
    }
}
New-Item -ItemType Directory -Path (Join-Path $target 'sounds/custom') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $target 'sounds/custom/config.json'), 'user-sound-pack')
[IO.File]::WriteAllText((Join-Path $target 'unrelated.txt'), 'keep')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$package = Join-Path $root 'update.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($packageRoot, $package)
if ($Installer) {
    # A unique AppId and no shortcuts isolate the real Inno handoff from the user's installation.
    $fixture = Join-Path $root 'fixture.iss'
    @"
[Setup]
AppId=NightcordUpdateSmoke$([IO.Path]::GetFileName($root))
AppName=Nightcord Update Smoke
AppVersion=0.3.0
DefaultDirName=$target
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=$root
OutputBaseFilename=fixture-setup
DisableDirPage=yes
DisableProgramGroupPage=yes
[Files]
Source: "$bundle\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
"@ | Set-Content -LiteralPath $fixture -Encoding utf8
    $compiler = Join-Path $workspace 'run/inno-setup/ISCC.exe'
    & $compiler $fixture > (Join-Path $root 'compile.log')
    if ($LASTEXITCODE -ne 0) { throw 'Fixture installer compilation failed' }
    $package = Join-Path $root 'fixture-setup.exe'
}
$marker = Join-Path $root 'exit-parent'
$env:NIGHTCORD_UPDATE_SMOKE_WAIT = $marker
$parent = Start-Process -FilePath (Join-Path $target 'Nightcord Speak.exe') -WindowStyle Hidden -PassThru
$configuration = Join-Path $root 'update.json'
$settings = @{
    parent_pid = $parent.Id; target = $target; package = $package;
    sha256 = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant();
    version = '0.3.0'; nonce = [Guid]::NewGuid().ToString('N'); installer = $Installer.IsPresent; language = 'en';
}
$settings | ConvertTo-Json | Set-Content -LiteralPath $configuration -Encoding utf8
$script = Join-Path $workspace 'apps/client/assets/updates/windows.ps1'
$worker = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $script + '"'), '-Configuration', ('"' + $configuration + '"')) -WindowStyle Hidden -PassThru
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path -LiteralPath (Join-Path $root 'ready'))) {
        if (Test-Path -LiteralPath (Join-Path $root 'error')) { throw (Get-Content -LiteralPath (Join-Path $root 'updater.log') -Raw) }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Updater did not prepare' }
        Start-Sleep -Milliseconds 100
    }
    if ((Get-Content -LiteralPath (Join-Path $target 'data/flutter_assets/AssetManifest.bin') -Raw) -ne 'old') { throw 'Update overwrote a running client' }
    [IO.File]::WriteAllText((Join-Path $root 'commit'), $settings.nonce)
    [IO.File]::WriteAllText($marker, 'exit')
    if (-not $worker.WaitForExit(30000)) { throw 'Updater did not finish' }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'complete'))) { throw (Get-Content -LiteralPath (Join-Path $root 'updater.log') -Raw) }
    Start-Sleep -Milliseconds 500
    if ((Get-Content -LiteralPath (Join-Path $target 'launched') -Raw) -ne 'new') { throw 'Updated executable did not restart' }
    foreach ($name in @('nightcord_ffi.dll', 'flutter_windows.dll', 'data/flutter_assets/AssetManifest.bin')) {
        if ((Get-Content -LiteralPath (Join-Path $target $name) -Raw) -ne 'new') { throw 'Installed content mismatch' }
    }
    if ((Get-Content -LiteralPath (Join-Path $target 'sounds/custom/config.json') -Raw) -ne 'user-sound-pack' -or
        (Get-Content -LiteralPath (Join-Path $target 'unrelated.txt') -Raw) -ne 'keep') { throw 'User files changed' }
    Write-Output 'Update, readiness handshake, restart and user-file retention passed.'
} finally {
    [IO.File]::WriteAllText($marker, 'exit')
    Remove-Item Env:NIGHTCORD_UPDATE_SMOKE_WAIT
    if ($Installer -and (Test-Path -LiteralPath (Join-Path $target 'unins000.exe'))) {
        $uninstaller = Start-Process -FilePath (Join-Path $target 'unins000.exe') -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -WindowStyle Hidden -PassThru -Wait
        if ($uninstaller.ExitCode -ne 0) { throw 'Fixture uninstall failed' }
    }
}

# A locked DLL previously left partially installed files. Exercise rollback with
# the same transaction functions without launching a UI or any real client.
. $script -Configuration $configuration
$rollbackTarget = Join-Path $root 'rollback-target'
$rollbackStage = Join-Path $root 'rollback-stage'
$rollbackBackup = Join-Path $root 'rollback-backup'
New-Item -ItemType Directory -Path $rollbackTarget,$rollbackStage,$rollbackBackup | Out-Null
foreach ($name in @('a.dll', 'z.dll')) {
    [IO.File]::WriteAllText((Join-Path $rollbackTarget $name), 'original')
    [IO.File]::WriteAllText((Join-Path $rollbackStage $name), 'replacement')
}
$locked = [IO.File]::Open((Join-Path $rollbackTarget 'z.dll'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
$changes = [Collections.Generic.List[object]]::new()
$failed = $false
try { Invoke-PortableReplacement $rollbackStage $rollbackTarget $rollbackBackup $changes }
catch { $failed = $true }
finally { $locked.Dispose() }
if (-not $failed) { throw 'Expected locked-file update failure' }
Undo-Replacements $changes $rollbackTarget $rollbackBackup
foreach ($name in @('a.dll', 'z.dll')) {
    if ((Get-Content -LiteralPath (Join-Path $rollbackTarget $name) -Raw) -ne 'original') { throw 'Rollback did not restore original files' }
}
Write-Output 'Partial replacement failure rolled back successfully.'
