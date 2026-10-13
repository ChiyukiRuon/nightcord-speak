param([switch]$Installer, [ValidateSet('None', 'Accept', 'Cancel', 'Fail')][string]$SimulateElevation = 'None')
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
$diagnostics = Join-Path $root 'diagnostics'
New-Item -ItemType Directory -Path $diagnostics | Out-Null
$helperLog = Join-Path $diagnostics 'update.log'
$settings = @{
    parent_pid = $parent.Id; target = $target; package = $package;
    sha256 = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant();
    version = '0.3.0'; nonce = [Guid]::NewGuid().ToString('N'); installer = $Installer.IsPresent; language = 'en';
    log_file = $helperLog;
}
$settings | ConvertTo-Json | Set-Content -LiteralPath $configuration -Encoding utf8
$script = Join-Path $workspace 'apps/client/assets/updates/windows.ps1'
if ($SimulateElevation -ne 'None') {
    # Inject a denied write and consent result into a private helper copy; no UAC UI or real ACL changes.
    $fixtureScript = Join-Path $root 'elevation-fixture.ps1'
    $helper = [IO.File]::ReadAllText($script)
    $helper = $helper.Replace('New-Item -ItemType Directory -Path $backup | Out-Null',
        "if (-not `$Elevated) { throw [UnauthorizedAccessException]::new('Simulated protected application directory') }`n    New-Item -ItemType Directory -Path `$backup | Out-Null")
    if ($SimulateElevation -eq 'Fail') {
        $helper = $helper.Replace("if (-not `$Elevated) { throw [UnauthorizedAccessException]::new('Simulated protected application directory') }",
            "throw [UnauthorizedAccessException]::new('Simulated access denied even after elevation')")
    }
    if ($SimulateElevation -in @('Accept', 'Fail')) {
        $helper = $helper.Replace('-Verb RunAs -WindowStyle Hidden -PassThru', '-WindowStyle Hidden -PassThru')
    } else {
        $helper = $helper.Replace("return Start-Process -FilePath (Join-Path `$PSHOME 'powershell.exe') -ArgumentList `$arguments -Verb RunAs -WindowStyle Hidden -PassThru",
            "throw [ComponentModel.Win32Exception]::new(1223)")
    }
    [IO.File]::WriteAllText($fixtureScript, $helper, [Text.UTF8Encoding]::new($true))
    $script = $fixtureScript
}
$worker = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $script + '"'), '-Configuration', ('"' + $configuration + '"')) -WindowStyle Hidden -PassThru
try {
    if ($SimulateElevation -in @('Cancel', 'Fail')) {
        if (-not $worker.WaitForExit(30000)) { throw 'Cancelled helper did not return' }
        if ($SimulateElevation -eq 'Cancel') {
            if ((Get-Content -LiteralPath (Join-Path $root ($settings.nonce + '-cancelled')) -Raw) -ne $settings.nonce) { throw 'Elevation cancellation was not acknowledged' }
            if (Test-Path -LiteralPath (Join-Path $root ($settings.nonce + '-error'))) { throw 'Cancellation was reported as a failure' }
        } else {
            if (-not (Test-Path -LiteralPath (Join-Path $root ($settings.nonce + '-error'))) -or
                (Get-Content -LiteralPath (Join-Path $root ($settings.nonce + '-updater.log')) -Raw) -notmatch 'Simulated access denied even after elevation') { throw 'Elevated preparation failure lost its diagnostics' }
        }
        if ($parent.HasExited -or -not (Test-Path -LiteralPath $package) -or
            (Test-Path -LiteralPath (Join-Path $root ($settings.nonce + '-ready')))) { throw 'Cancelled or failed elevation did not preserve the running client and download' }
        if ((Get-Content -LiteralPath (Join-Path $target 'data/flutter_assets/AssetManifest.bin') -Raw) -ne 'old') { throw 'Cancellation changed installed files' }
        Write-Output 'Cancelled or failed elevation retained the client and verified package.'
        # Retry the same package with a fresh attempt, without another download.
        $settings.nonce = [Guid]::NewGuid().ToString('N')
        $settings | ConvertTo-Json | Set-Content -LiteralPath $configuration -Encoding utf8
        $script = Join-Path $workspace 'apps/client/assets/updates/windows.ps1'
        $worker = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $script + '"'), '-Configuration', ('"' + $configuration + '"')) -WindowStyle Hidden -PassThru
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path -LiteralPath (Join-Path $root ($settings.nonce + '-ready')))) {
        if (Test-Path -LiteralPath (Join-Path $root ($settings.nonce + '-error'))) { throw (Get-Content -LiteralPath (Join-Path $root ($settings.nonce + '-updater.log')) -Raw) }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Updater did not prepare' }
        Start-Sleep -Milliseconds 100
    }
    if ((Get-Content -LiteralPath (Join-Path $target 'data/flutter_assets/AssetManifest.bin') -Raw) -ne 'old') { throw 'Update overwrote a running client' }
    $requestedElevation = Test-Path -LiteralPath (Join-Path $root ($settings.nonce + '-elevating'))
    if ($requestedElevation -ne ($SimulateElevation -eq 'Accept')) { throw 'Unexpected elevation request' }
    [IO.File]::WriteAllText((Join-Path $root ($settings.nonce + '-commit')), $settings.nonce)
    [IO.File]::WriteAllText($marker, 'exit')
    if (-not $worker.WaitForExit(30000)) { throw 'Updater did not finish' }
    if (-not (Test-Path -LiteralPath (Join-Path $root ($settings.nonce + '-complete')))) { throw (Get-Content -LiteralPath (Join-Path $root ($settings.nonce + '-updater.log')) -Raw) }
    Start-Sleep -Milliseconds 500
    if ((Get-Content -LiteralPath (Join-Path $target 'launched') -Raw) -ne 'new') { throw 'Updated executable did not restart' }
    foreach ($name in @('nightcord_ffi.dll', 'flutter_windows.dll', 'data/flutter_assets/AssetManifest.bin')) {
        if ((Get-Content -LiteralPath (Join-Path $target $name) -Raw) -ne 'new') { throw 'Installed content mismatch' }
    }
    if ((Get-Content -LiteralPath (Join-Path $target 'sounds/custom/config.json') -Raw) -ne 'user-sound-pack' -or
        (Get-Content -LiteralPath (Join-Path $target 'unrelated.txt') -Raw) -ne 'keep') { throw 'User files changed' }
    Write-Output 'Update, readiness handshake, restart and user-file retention passed.'
    $trace = Get-Content -LiteralPath $helperLog -Raw -Encoding UTF8
    foreach ($stageName in @('started', 'validated', 'ready', 'committed', 'parent-exited', 'installed', 'complete', 'cleanup')) {
        if ($trace -notmatch ('stage=' + $stageName + ' ')) { throw ('Missing update diagnostic stage: ' + $stageName) }
    }
    if ($SimulateElevation -eq 'Accept' -and ($trace -notmatch 'stage=uac-accepted ' -or $trace -notmatch 'role=elevated' -or $trace -notmatch 'stage=relaunched ')) { throw 'Elevation diagnostic stages missing' }
    if ($SimulateElevation -eq 'Cancel' -and $trace -notmatch 'stage=uac-cancelled ') { throw 'Cancellation diagnostic stage missing' }
    if ($SimulateElevation -eq 'Fail' -and $trace -notmatch 'Simulated access denied even after elevation') { throw 'Elevation failure diagnostics missing' }
    if ($Installer -and $trace -notmatch 'stage=installer-result exit_code=0') { throw 'Installer result diagnostic missing' }
    if ($Installer -and -not (Test-Path -LiteralPath ($helperLog + '-installer.log'))) { throw 'Installer log was not preserved with the helper diagnostics' }
    Write-Output 'Persistent helper diagnostics contain all transaction stages.'
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

# Verify that only access-denied failures request elevation, and cancellation is distinct.
if (-not (Test-UpdateAccessDenied ([UnauthorizedAccessException]::new())) -or
    -not (Test-UpdateAccessDenied ([Exception]::new('wrapped', [ComponentModel.Win32Exception]::new(5)))) -or
    (Test-UpdateAccessDenied ([IO.IOException]::new('locked file'))) -or
    (Test-UpdateAccessDenied ([ComponentModel.Win32Exception]::new(1223)))) { throw 'Access-denied classification failed' }
if (-not (Test-UpdateElevationCancelled ([Exception]::new('wrapped', [ComponentModel.Win32Exception]::new(1223)))) -or
    (Test-UpdateElevationCancelled ([UnauthorizedAccessException]::new()))) { throw 'UAC cancellation classification failed' }
[IO.File]::WriteAllText((Get-UpdateSignal $root $settings.nonce 'abort'), $settings.nonce)
$aborted = $false
try { Assert-UpdateNotAborted $root $settings.nonce } catch { $aborted = $true }
if (-not $aborted) { throw 'Delayed helper ignored the client abort token' }
Assert-UpdateNotAborted $root ([Guid]::NewGuid().ToString('N'))

# Mock only ShellExecute: verify the real launch arguments without displaying UAC.
. (Join-Path $workspace 'apps/client/assets/updates/windows.ps1') -Configuration $configuration
function Start-Process($FilePath, $ArgumentList, $Verb, $WindowStyle, [switch]$PassThru) {
    return [pscustomobject]@{ FilePath = $FilePath; Arguments = $ArgumentList; Verb = $Verb; WindowStyle = $WindowStyle; PassThru = $PassThru.IsPresent }
}
$launch = Start-ElevatedUpdateWorker 'C:\更新目录\update.ps1' 'C:\更新目录\update.json'
if ($launch.Verb -ne 'RunAs' -or $launch.WindowStyle -ne 'Hidden' -or -not $launch.PassThru -or
    $launch.FilePath -ne (Join-Path $PSHOME 'powershell.exe') -or
    $launch.Arguments[-1] -ne '-Elevated' -or
    $launch.Arguments[-4] -ne '"C:\更新目录\update.ps1"' -or
    $launch.Arguments[-2] -ne '"C:\更新目录\update.json"') { throw 'Incorrect UAC worker launch arguments' }
Write-Output 'Permission detection, UAC launch, cancellation and delayed-worker abort passed.'
$script:updateTrace = Join-Path $root 'missing-log-directory/trace.log'
Write-UpdateTrace 'info' 'sink-failure-test' 'Log failures must not interrupt an update'
Write-Output 'An unavailable diagnostic sink did not interrupt the helper.'
