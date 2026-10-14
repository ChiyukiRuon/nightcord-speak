param([Parameter(Mandatory=$true)][string]$Configuration, [switch]$Elevated)
$ErrorActionPreference = 'Stop'
$script:updateTrace = $null
$script:updateClock = [Diagnostics.Stopwatch]::StartNew()
function Write-UpdateTrace($level, $stage, $message) {
    if (-not $script:updateTrace) { return }
    $role = if ($Elevated) { 'elevated' } else { 'broker' }
    $safeMessage = ([string]$message).Replace("`r", ' ').Replace("`n", ' ')
    if ($safeMessage.Length -gt 4096) { $safeMessage = $safeMessage.Substring(0, 4096) + ' [truncated]' }
    $line = '{0} [{1}] pid={2} role={3} elapsed_ms={4} stage={5} {6}' -f [DateTime]::UtcNow.ToString('o'), $level, $PID, $role, $script:updateClock.ElapsedMilliseconds, $stage, $safeMessage
    # Logging is best effort; it must never interrupt installation or rollback.
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        try { [IO.File]::AppendAllText($script:updateTrace, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false)); return }
        catch { if ($attempt -lt 2) { Start-Sleep -Milliseconds 10 } }
    }
}
function Test-UpdateAccessDenied($exception) {
    while ($exception) {
        if ($exception -is [UnauthorizedAccessException] -or
            ($exception -is [ComponentModel.Win32Exception] -and $exception.NativeErrorCode -eq 5) -or
            $exception.HResult -eq -2147024891) { return $true }
        $exception = $exception.InnerException
    }
    return $false
}
function Test-UpdateElevationCancelled($exception) {
    while ($exception) {
        if (($exception -is [ComponentModel.Win32Exception] -and $exception.NativeErrorCode -eq 1223) -or
            $exception.HResult -eq -2147023673) { return $true }
        $exception = $exception.InnerException
    }
    return $false
}
function Start-ElevatedUpdateWorker([string]$script, [string]$configuration) {
    # Use the system PowerShell, not a PATH entry selected by another application.
    $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', ('"' + $script + '"'), '-Configuration', ('"' + $configuration + '"'), '-Elevated')
    return Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
}
function Get-UpdateSignal($root, $nonce, $name) {
    return Join-Path $root ($nonce + '-' + $name)
}
function Assert-UpdateNotAborted($root, $nonce) {
    $abort = Get-UpdateSignal $root $nonce 'abort'
    if ((Test-Path -LiteralPath $abort) -and (Get-Content -LiteralPath $abort -Raw) -eq $nonce) {
        throw 'Client stopped waiting for the update'
    }
}
function Assert-UpdateTargetIdle($target, $excludedPid) {
    $executable = Join-Path $target 'Nightcord Speak.exe'
    foreach ($client in Get-Process -Name 'Nightcord Speak' -ErrorAction SilentlyContinue) {
        if ($client.Id -ne $excludedPid -and [string]::Equals($client.Path, $executable, [StringComparison]::OrdinalIgnoreCase)) {
            Write-UpdateTrace 'error' 'other-instance' ('pid={0} still uses the installation directory' -f $client.Id)
            throw ('Another Nightcord Speak instance is running from this installation (pid={0}); close it before updating' -f $client.Id)
        }
    }
}
function Invoke-PortableReplacement($stage, $target, $backup, $changes) {
    foreach ($source in Get-ChildItem -LiteralPath $stage) {
        $destination = Join-Path $target $source.Name
        $saved = Join-Path $backup $source.Name
        Write-UpdateTrace 'debug' 'replace-component' $source.Name
        if (-not [System.IO.Path]::GetFullPath($destination).StartsWith($target + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid replacement target' }
        if ((Test-Path -LiteralPath $destination) -and ((Get-Item -LiteralPath $destination -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { throw 'Application component is a reparse point' }
        $change = [pscustomobject]@{ Destination = $destination; Saved = $saved; OldMoved = $false; NewMoved = $false }
        $changes.Add($change)
        if (Test-Path -LiteralPath $destination) {
            Move-Item -LiteralPath $destination -Destination $saved
            $change.OldMoved = $true
        }
        Move-Item -LiteralPath $source.FullName -Destination $destination
        $change.NewMoved = $true
    }
}
function Undo-Replacements($changes, $target, $backup) {
    for ($index = $changes.Count - 1; $index -ge 0; $index--) {
        $change = $changes[$index]
        if (-not [System.IO.Path]::GetFullPath($change.Destination).StartsWith($target + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not [System.IO.Path]::GetFullPath($change.Saved).StartsWith($backup + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid rollback target' }
        if ($change.NewMoved -and (Test-Path -LiteralPath $change.Destination)) { Remove-Item -LiteralPath $change.Destination -Recurse -Force }
        if ($change.OldMoved) { Move-Item -LiteralPath $change.Saved -Destination $change.Destination }
        Write-UpdateTrace 'debug' 'rollback-component' ([IO.Path]::GetFileName($change.Destination))
    }
}
# Dot-sourcing exposes only transaction functions to native regression tests.
if ($MyInvocation.InvocationName -eq '.') { return }
$updateRoot = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Configuration))
$script:updateTrace = Join-Path $updateRoot 'updater-trace.log'
$backup = $null
$changes = [System.Collections.Generic.List[object]]::new()
$exited = $false
$settings = $null
$validated = $false
$readyPublished = $false
$delegated = $false
try {
    $settings = Get-Content -LiteralPath $Configuration -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($settings.log_file) { $script:updateTrace = [IO.Path]::GetFullPath($settings.log_file) }
    Write-UpdateTrace 'info' 'started' ('version={0} installer={1} parent_pid={2} attempt={3}' -f $settings.version, $settings.installer, $settings.parent_pid, $settings.nonce)
    $target = [System.IO.Path]::GetFullPath($settings.target).TrimEnd('\')
    $package = [System.IO.Path]::GetFullPath($settings.package)
    Write-UpdateTrace 'info' 'validate-package' ('target={0} package={1}' -f $target, $package)
    if (-not $package.StartsWith($updateRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath (Join-Path $target 'Nightcord Speak.exe')) -or
        (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant() -ne $settings.sha256) {
        throw 'Update package validation failed'
    }
    $parent = Get-Process -Id $settings.parent_pid -ErrorAction SilentlyContinue
    if (-not $parent -or -not [string]::Equals($parent.Path, (Join-Path $target 'Nightcord Speak.exe'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Update parent does not match the application'
    }
    if ($settings.nonce -notmatch '^[a-f0-9]{32}$') { throw 'Invalid update nonce' }
    if ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Application directory is a reparse point' }
    $validated = $true
    Write-UpdateTrace 'info' 'validated' 'Package checksum, parent process and target validated'
    Assert-UpdateNotAborted $updateRoot $settings.nonce
    Assert-UpdateTargetIdle $target $settings.parent_pid
    # Each retry owns fresh staging and backup paths, including elevation retries.
    $attempt = $settings.nonce + $(if ($Elevated) { '-elevated' } else { '' })
    $stage = Join-Path $updateRoot ('stage-' + $attempt)
    if (-not $settings.installer) {
        Write-UpdateTrace 'info' 'extract' ('stage={0}' -f $stage)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($package)
        try {
            $prefix = 'Nightcord-Speak-' + $settings.version + '-windows-x64/'
            foreach ($entry in $archive.Entries) {
                $entryName = $entry.FullName.Replace('\', '/')
                if (-not $entryName.StartsWith($prefix, [StringComparison]::Ordinal) -or
                    ($entry.ExternalAttributes -band 0xF0000000) -eq 0xA0000000) {
                    throw 'Invalid update archive entry'
                }
                $relative = $entryName.Substring($prefix.Length)
                if (-not $relative -and -not $entry.Name) { continue }
                $resolved = [System.IO.Path]::GetFullPath((Join-Path $stage $relative))
                if (-not $resolved.StartsWith($stage + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Update archive path escapes staging directory' }
                $top = $relative.Split('/')[0]
                if ($top -notmatch '^(Nightcord Speak\.exe|[a-zA-Z0-9_]+\.dll|native_assets\.json|data)$') { throw 'Unexpected update component' }
                if ($entry.Name) {
                    New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($resolved)) -Force | Out-Null
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $resolved)
                }
            }
        } finally { $archive.Dispose() }
        foreach ($name in @('Nightcord Speak.exe', 'nightcord_ffi.dll', 'flutter_windows.dll', 'data/flutter_assets/AssetManifest.bin')) {
            if (-not (Test-Path -LiteralPath (Join-Path $stage $name))) { throw 'Incomplete update bundle' }
        }
        Write-UpdateTrace 'info' 'extract-complete' 'Portable bundle validated'
    }
    # Keep backup on the same volume; never back up or replace user sound packs.
    $backup = Join-Path $target ('.nightcord-update-backup-' + $attempt)
    Write-UpdateTrace 'info' 'prepare-backup' ('backup={0}' -f $backup)
    if (Test-Path -LiteralPath $backup) { throw 'Update backup already exists' }
    New-Item -ItemType Directory -Path $backup | Out-Null
    if ($settings.installer) {
        foreach ($component in Get-ChildItem -LiteralPath $target | Where-Object { $_.Name -match '^(Nightcord Speak\.exe|[a-zA-Z0-9_]+\.dll|native_assets\.json|data)$' }) {
            if ($component.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw 'Application component is a reparse point' }
            $saved = Join-Path $backup $component.Name
            Copy-Item -LiteralPath $component.FullName -Destination $saved -Recurse
            $changes.Add([pscustomobject]@{ Destination = $component.FullName; Saved = $saved; OldMoved = $true; NewMoved = $false })
        }
    }
    Write-UpdateTrace 'info' 'backup-ready' ('snapshotted_components={0}' -f $changes.Count)
    Assert-UpdateNotAborted $updateRoot $settings.nonce
    [System.IO.File]::WriteAllText((Get-UpdateSignal $updateRoot $settings.nonce 'ready'), $settings.nonce)
    $readyPublished = $true
    Write-UpdateTrace 'info' 'ready' 'Waiting for client commit'
    $commitDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path -LiteralPath (Get-UpdateSignal $updateRoot $settings.nonce 'commit')) -or
        (Get-Content -LiteralPath (Get-UpdateSignal $updateRoot $settings.nonce 'commit') -Raw) -ne $settings.nonce) {
        if ([DateTime]::UtcNow -gt $commitDeadline) { throw 'Client did not commit the update' }
        Assert-UpdateNotAborted $updateRoot $settings.nonce
        Start-Sleep -Milliseconds 100
    }
    Write-UpdateTrace 'info' 'committed' 'Waiting for client process to exit'
    if (-not $parent.WaitForExit(60000)) { throw 'Application did not exit for the update' }
    # Recheck after exit in case another instance started during preparation.
    Assert-UpdateTargetIdle $target 0
    $exited = $true
    Write-UpdateTrace 'info' 'parent-exited' 'Beginning installation'
    if ($settings.installer) {
        foreach ($change in $changes) { $change.NewMoved = $true }
        Write-UpdateTrace 'info' 'installer-started' 'Starting silent installer'
        $language = switch -Regex ($settings.language) {
            '^zh.*(Hant|TW|HK|MO)' { 'chinesetraditional'; break }
            '^zh' { 'chinesesimplified'; break }
            '^ja' { 'japanese'; break }
            '^ko' { 'korean'; break }
            default { 'english' }
        }
        $process = Start-Process -FilePath $package -ArgumentList @('/SILENT', '/SP-', '/NORESTART', '/NOCLOSEAPPLICATIONS', '/NORESTARTAPPLICATIONS', "/LANG=$language", ('/DIR="' + $target + '"'), ('/LOG="' + (Get-UpdateSignal $updateRoot $settings.nonce 'installer.log') + '"')) -WindowStyle Hidden -PassThru -Wait
        Write-UpdateTrace 'info' 'installer-result' ('exit_code={0} installer_log={1}' -f $process.ExitCode, (Get-UpdateSignal $updateRoot $settings.nonce 'installer.log'))
        try {
            $installerLog = Get-UpdateSignal $updateRoot $settings.nonce 'installer.log'
            if (Test-Path -LiteralPath $installerLog) {
                Copy-Item -LiteralPath $installerLog -Destination ($script:updateTrace + '-installer.log') -Force
                Write-UpdateTrace 'info' 'installer-log-preserved' ($script:updateTrace + '-installer.log')
            }
        } catch { Write-UpdateTrace 'warn' 'installer-log-copy-failed' $_.Exception.Message }
        if ($process.ExitCode -ne 0) { throw 'Update installer failed' }
    } else {
        Invoke-PortableReplacement $stage $target $backup $changes
    }
    # The original helper relaunches the client with the user's original token.
    Write-UpdateTrace 'info' 'installed' ('changed_components={0}' -f $changes.Count)
    if (-not $Elevated) { Start-Process -FilePath (Join-Path $target 'Nightcord Speak.exe') -WorkingDirectory $target -WindowStyle Normal }
    [System.IO.File]::WriteAllText((Get-UpdateSignal $updateRoot $settings.nonce 'complete'), 'ok')
    Write-UpdateTrace 'info' 'complete' ('relaunch_by={0}' -f $(if ($Elevated) { 'broker' } else { 'self' }))
} catch {
    $failure = $_
    Write-UpdateTrace 'error' 'failed' ('type={0} hresult={1} message={2} stack={3}' -f $_.Exception.GetType().FullName, $_.Exception.HResult, $_.Exception.Message, $_.ScriptStackTrace)
    if ($validated -and -not $readyPublished -and -not $exited -and -not $Elevated -and (Test-UpdateAccessDenied $_.Exception)) {
        try {
            Assert-UpdateNotAborted $updateRoot $settings.nonce
            [IO.File]::WriteAllText((Get-UpdateSignal $updateRoot $settings.nonce 'elevating'), $settings.nonce)
            Write-UpdateTrace 'info' 'uac-requested' 'Access denied during preparation; requesting elevation'
            $worker = Start-ElevatedUpdateWorker $PSCommandPath $Configuration
            Write-UpdateTrace 'info' 'uac-accepted' ('worker_pid={0}' -f $worker.Id)
            $delegated = $true
            $worker.WaitForExit()
            Write-UpdateTrace 'info' 'elevated-worker-exited' 'Checking worker completion markers'
            $exited = $parent.HasExited
            if (Test-Path -LiteralPath (Get-UpdateSignal $updateRoot $settings.nonce 'error')) { throw 'Elevated update failed. See updater.log.' }
            if (-not (Test-Path -LiteralPath (Get-UpdateSignal $updateRoot $settings.nonce 'complete'))) { throw 'Elevated updater did not finish' }
            Start-Process -FilePath (Join-Path $target 'Nightcord Speak.exe') -WorkingDirectory $target -WindowStyle Normal
            Write-UpdateTrace 'info' 'relaunched' 'Client launched with original user token'
            return
        } catch {
            $failure = $_
            Write-UpdateTrace 'warn' 'elevation-result' ('type={0} hresult={1} message={2}' -f $_.Exception.GetType().FullName, $_.Exception.HResult, $_.Exception.Message)
            if (Test-UpdateElevationCancelled $_.Exception) {
                Write-UpdateTrace 'info' 'uac-cancelled' 'Client and package retained'
                [IO.File]::WriteAllText((Get-UpdateSignal $updateRoot $settings.nonce 'cancelled'), $settings.nonce)
                return
            }
        }
    }
    # Roll back only paths recorded by this transaction, never a whole user directory.
    if ($exited -and -not $delegated) {
        Write-UpdateTrace 'warn' 'rollback-started' ('components={0}' -f $changes.Count)
        try {
            Undo-Replacements $changes $target $backup
            Write-UpdateTrace 'info' 'rollback-complete' 'Recorded replacements restored'
        } catch {
            $_ | Out-File -LiteralPath (Get-UpdateSignal $updateRoot $settings.nonce 'rollback.log') -Encoding utf8
            Write-UpdateTrace 'error' 'rollback-failed' $_.Exception.Message
        }
    }
    [System.IO.File]::WriteAllText((Get-UpdateSignal $updateRoot $settings.nonce 'error'), 'Update failed. See updater.log.')
    if (-not $delegated -or -not (Test-Path -LiteralPath (Get-UpdateSignal $updateRoot $settings.nonce 'updater.log'))) {
        $failure | Out-File -LiteralPath (Get-UpdateSignal $updateRoot $settings.nonce 'updater.log') -Encoding utf8
    }
    if ($exited -and -not $Elevated) {
        Write-UpdateTrace 'info' 'relaunch-recovery' 'Attempting to launch the recovered client'
        Start-Process -FilePath (Join-Path $target 'Nightcord Speak.exe') -WorkingDirectory $target -WindowStyle Normal
        Add-Type -AssemblyName System.Windows.Forms
        $message = switch -Regex ($settings.language) {
            '^zh.*(Hant|TW|HK|MO)' { '更新失敗，已嘗試恢復原版本。請重新下載後重試。'; break }
            '^zh' { '更新失败，已尝试恢复原版本。请重新下载后重试。'; break }
            '^ja' { '更新に失敗しました。元のバージョンの復元を試みました。再ダウンロードしてお試しください。'; break }
            '^ko' { '업데이트에 실패하여 이전 버전 복원을 시도했습니다. 다시 다운로드하여 시도하세요.'; break }
            default { 'Update failed. Recovery of the previous version was attempted. Download again and retry.' }
        }
        [System.Windows.Forms.MessageBox]::Show($message, 'Nightcord Speak') | Out-Null
    }
} finally {
    # Retain failed transactions and their backups for recovery and diagnostics.
    if (Test-Path -LiteralPath (Get-UpdateSignal $updateRoot $settings.nonce 'complete')) {
        Write-UpdateTrace 'info' 'cleanup' 'Removing successful transaction backup and temporary files'
        if ($backup -and $backup.StartsWith($target + '\.nightcord-update-backup-', [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup -Recurse -Force }
        if (-not $Elevated -and $updateRoot.StartsWith([System.IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $updateRoot).StartsWith('nightcord-update-')) { Remove-Item -LiteralPath $updateRoot -Recurse -Force }
    }
}
