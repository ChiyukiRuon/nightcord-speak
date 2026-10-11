param([Parameter(Mandatory=$true)][string]$Configuration)
$ErrorActionPreference = 'Stop'
function Invoke-PortableReplacement($stage, $target, $backup, $changes) {
    foreach ($source in Get-ChildItem -LiteralPath $stage) {
        $destination = Join-Path $target $source.Name
        $saved = Join-Path $backup $source.Name
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
    }
}
# Dot-sourcing exposes only transaction functions to native regression tests.
if ($MyInvocation.InvocationName -eq '.') { return }
$updateRoot = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Configuration))
$backup = $null
$changes = [System.Collections.Generic.List[object]]::new()
$exited = $false
$settings = $null
try {
    $settings = Get-Content -LiteralPath $Configuration -Raw -Encoding UTF8 | ConvertFrom-Json
    $target = [System.IO.Path]::GetFullPath($settings.target).TrimEnd('\')
    $package = [System.IO.Path]::GetFullPath($settings.package)
    if (-not $package.StartsWith($updateRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath (Join-Path $target 'Nightcord Speak.exe')) -or
        (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant() -ne $settings.sha256) {
        throw 'Update package validation failed'
    }
    $parent = Get-Process -Id $settings.parent_pid -ErrorAction SilentlyContinue
    if (-not $parent -or -not [string]::Equals($parent.Path, (Join-Path $target 'Nightcord Speak.exe'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Update parent does not match the application'
    }
    $stage = Join-Path $updateRoot 'stage'
    if (-not $settings.installer) {
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
    }
    # Keep backup on the same volume; never back up or replace user sound packs.
    $backup = Join-Path $target ('.nightcord-update-backup-' + $settings.nonce)
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
    [System.IO.File]::WriteAllText((Join-Path $updateRoot 'ready'), $settings.nonce)
    $commitDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path -LiteralPath (Join-Path $updateRoot 'commit')) -or
        (Get-Content -LiteralPath (Join-Path $updateRoot 'commit') -Raw) -ne $settings.nonce) {
        if ([DateTime]::UtcNow -gt $commitDeadline) { throw 'Client did not commit the update' }
        Start-Sleep -Milliseconds 100
    }
    if (-not $parent.WaitForExit(60000)) { throw 'Application did not exit for the update' }
    $exited = $true
    if ($settings.installer) {
        foreach ($change in $changes) { $change.NewMoved = $true }
        $language = switch -Regex ($settings.language) {
            '^zh.*(Hant|TW|HK|MO)' { 'chinesetraditional'; break }
            '^zh' { 'chinesesimplified'; break }
            '^ja' { 'japanese'; break }
            '^ko' { 'korean'; break }
            default { 'english' }
        }
        $process = Start-Process -FilePath $package -ArgumentList @('/SILENT', '/SP-', '/NORESTART', '/NOCLOSEAPPLICATIONS', '/NORESTARTAPPLICATIONS', "/LANG=$language", ('/DIR="' + $target + '"'), ('/LOG="' + (Join-Path $updateRoot 'installer.log') + '"')) -WindowStyle Hidden -PassThru -Wait
        if ($process.ExitCode -ne 0) { throw 'Update installer failed' }
    } else {
        Invoke-PortableReplacement $stage $target $backup $changes
    }
    Start-Process -FilePath (Join-Path $target 'Nightcord Speak.exe') -WorkingDirectory $target -WindowStyle Hidden
    [System.IO.File]::WriteAllText((Join-Path $updateRoot 'complete'), 'ok')
} catch {
    # Roll back only paths recorded by this transaction, never a whole user directory.
    if ($exited) {
        try { Undo-Replacements $changes $target $backup } catch {
            $_ | Out-File -LiteralPath (Join-Path $updateRoot 'rollback.log') -Encoding utf8
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $updateRoot 'error'), 'Update failed. See updater.log.')
    $_ | Out-File -LiteralPath (Join-Path $updateRoot 'updater.log') -Encoding utf8
    if ($exited) {
        Start-Process -FilePath (Join-Path $target 'Nightcord Speak.exe') -WorkingDirectory $target -WindowStyle Hidden
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
    if (Test-Path -LiteralPath (Join-Path $updateRoot 'complete')) {
        if ($backup -and $backup.StartsWith($target + '\.nightcord-update-backup-', [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $backup -Recurse -Force }
        if ($updateRoot.StartsWith([System.IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $updateRoot).StartsWith('nightcord-update-')) { Remove-Item -LiteralPath $updateRoot -Recurse -Force }
    }
}
