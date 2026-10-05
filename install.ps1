# BetterHotkeys setup for a fresh Windows 11 PC. Runs in Windows PowerShell 5.1 (what ships with Windows).
#  - Installs AutoHotkey v2, fzf, PowerShell 7, Windows Terminal, JetBrainsMono Nerd Font, Git (via winget)
#  - Copies the hotkey scripts to Documents\AutoHotkey and starts them at sign-in:
#      Win+K  hotkey cheatsheet   Win+Shift+Space  web app manager   Win+Shift+T  theme picker
#      Win+W  close window
#  - Registers an uninstaller in Settings > Apps (uninstall.ps1 removes what setup installed)
#  - Applies an Omarchy theme (Hackerman by default) to Windows Terminal; Win+Shift+T switches themes
# Safe to run again: existing scripts are backed up before being replaced.

$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'BetterHotkeys setup'
$failed = @()
$installedNow = @()

function Step($text) { Write-Host "`n> $text" -ForegroundColor Green }
function Info($text) { Write-Host "  $text" -ForegroundColor DarkGray }
function Warn($text) { Write-Host "  $text" -ForegroundColor Yellow }

Write-Host ''
Write-Host '  B E T T E R   H O T K E Y S' -ForegroundColor Green
Write-Host '  hotkey cheatsheet, web apps, terminal theme' -ForegroundColor DarkGray

# ---------------------------------------------------------------- winget packages

Step 'Checking winget'
$winget = (Get-Command winget -ErrorAction SilentlyContinue).Source
if (-not $winget) {
    # On a brand-new PC, App Installer may not be registered for this user yet
    Info 'Registering App Installer...'
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe } catch {}
    $winget = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
}
if (-not (Test-Path $winget)) {
    Warn 'winget not found. Update "App Installer" from the Microsoft Store, then run this again.'
    Read-Host "`n  Press Enter to close"
    exit 1
}
Info 'ok'

# --no-upgrade stops winget from upgrading a package that is already installed (older winget lacks it)
$noUpgrade = if ((& $winget install --help 2>$null) -match '--no-upgrade') { '--no-upgrade' } else { $null }

# Skips the package if $isInstalled finds it, or if winget already knows about it (any install source).
# winget gets 10 minutes; if it's stuck, it's stopped and setup moves on.
function Install-Package($id, $name, [scriptblock]$isInstalled) {
    Step "Installing $name"
    if (& $isInstalled) { Info 'already installed, skipping'; return }
    & $winget list --id $id -e --accept-source-agreements --disable-interactivity *> $null
    if ($LASTEXITCODE -eq 0) { Info 'already installed, skipping'; return }

    $log = Join-Path $env:TEMP "betterhotkeys-winget-$id.log"
    $wingetArgs = @('install', '--id', $id, '-e', '--source', 'winget', '--silent', '--accept-source-agreements',
        '--accept-package-agreements', '--disable-interactivity', $noUpgrade) | Where-Object { $_ }
    $proc = Start-Process $winget -ArgumentList $wingetArgs -NoNewWindow -PassThru -RedirectStandardOutput $log
    $handle = $proc.Handle  # needed for ExitCode to be readable later
    if (-not $proc.WaitForExit(600000)) {
        $proc.Kill()
        Warn "$name took longer than 10 minutes and was stopped. Run setup again later to retry."
        $script:failed += $name
        return
    }
    Get-Content $log -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*(Found|Successfully|Starting|The installer)' } |
        ForEach-Object { Info $_.Trim() }
    # Remember what setup installed, so uninstall.ps1 removes only that (0x8A150109: done after a restart)
    if ($proc.ExitCode -in 0, -1978334967) { $script:installedNow += $id }
    # 0x8A15002B / 0x8A150061: already installed, nothing to do
    if ($proc.ExitCode -notin 0, -1978335189, -1978335135, -1978334967) {
        Warn "winget failed for $name (exit $($proc.ExitCode)), see $log"
        $script:failed += $name
    }
}

function Find-Ahk {
    "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe", "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe" |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}
function Test-Font {
    $keys = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts', 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    foreach ($key in $keys) {
        $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if ($props -and ($props.PSObject.Properties.Name -match 'JetBrainsMono')) { return $true }
    }
    $false
}
function Test-Any([string[]]$commands, [string[]]$paths) {
    foreach ($c in $commands) { if (Get-Command $c -ErrorAction SilentlyContinue) { return $true } }
    foreach ($p in $paths) { if (Test-Path $p) { return $true } }
    $false
}

Install-Package 'AutoHotkey.AutoHotkey' 'AutoHotkey v2' { [bool](Find-Ahk) }
Install-Package 'junegunn.fzf' 'fzf' {
    Test-Any 'fzf' "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\junegunn.fzf*\fzf.exe", "$env:USERPROFILE\scoop\shims\fzf.exe"
}
Install-Package 'Microsoft.PowerShell' 'PowerShell 7' {
    Test-Any 'pwsh' "$env:ProgramFiles\PowerShell\7\pwsh.exe", "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
}
Install-Package 'Microsoft.WindowsTerminal' 'Windows Terminal' {
    [bool](Get-AppxPackage Microsoft.WindowsTerminal*) -or (Test-Any 'wt')
}
Install-Package 'DEVCOM.JetBrainsMonoNerdFont' 'JetBrainsMono Nerd Font' { Test-Font }
Install-Package 'Git.Git' 'Git' {
    Test-Any 'git' "$env:ProgramFiles\Git\cmd\git.exe", "${env:ProgramFiles(x86)}\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
}

# Add to the record kept for uninstall.ps1 (re-runs keep what earlier runs installed)
$appDir = Join-Path $env:LOCALAPPDATA 'BetterHotkeys'
New-Item -ItemType Directory -Force $appDir | Out-Null
$manifest = Join-Path $appDir 'installed.txt'
$record = @(Get-Content $manifest -ErrorAction SilentlyContinue) + $installedNow | Where-Object { $_ } | Sort-Object -Unique
Set-Content $manifest $record

# ---------------------------------------------------------------- scripts

Step 'Copying hotkey scripts'
$dest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AutoHotkey'
$files = 'hotkeys.ahk', 'cheatsheet.ps1', 'send-hotkey.ahk', 'webapps.ps1', 'webapp-lib.ahk', 'open-webapp.ahk',
    'themes.ps1', 'theme-lib.ps1', 'themes.json'
New-Item -ItemType Directory -Force $dest | Out-Null
$existing = $files | Where-Object { Test-Path (Join-Path $dest $_) }
if ($existing) {
    $backup = Join-Path $dest ('backups\' + (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    New-Item -ItemType Directory -Force $backup | Out-Null
    $existing | ForEach-Object { Copy-Item (Join-Path $dest $_) $backup }
    Info "previous versions backed up to $backup"
}
$files | ForEach-Object { Copy-Item (Join-Path $PSScriptRoot $_) $dest -Force }
Info $dest

# ---------------------------------------------------------------- Windows Terminal theme

# themes.ps1 (the Win+Shift+T picker) does the work; it reapplies the current theme if one was
# picked before, else Hackerman. -Init also sets the font, cursor, opacity and padding.
Step 'Applying theme to Windows Terminal'
$pwsh = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
if (-not (Test-Path $pwsh)) { $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
$wtFile = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (-not $pwsh) {
    Warn 'PowerShell 7 not found, theme not applied'
    $failed += 'Windows Terminal theme'
} else {
    if (Test-Path $wtFile) { Copy-Item $wtFile "$wtFile.before-betterhotkeys" -Force }
    $out = & $pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'themes.ps1') -Init 2>&1
    if ($LASTEXITCODE -eq 0) { Info "$out" } else {
        Warn "Theme failed: $out"
        $failed += 'Windows Terminal theme'
    }
}

# ---------------------------------------------------------------- start at sign-in

Step 'Starting hotkeys (and at every sign-in)'
$ahk = Find-Ahk
if ($ahk) {
    $script = Join-Path $dest 'hotkeys.ahk'
    $startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'hotkeys.lnk'
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($startup)
    $lnk.TargetPath = $ahk
    $lnk.Arguments = "`"$script`""
    $lnk.WorkingDirectory = $dest
    $lnk.Save()
    Start-Process $ahk -ArgumentList "`"$script`""
    Info 'running'
} else {
    Warn 'AutoHotkey not found, hotkeys not started'
    $failed += 'start hotkeys'
}

# ---------------------------------------------------------------- uninstaller

# Lists BetterHotkeys in Settings > Apps > Installed apps, with an Uninstall button
Step 'Registering uninstaller'
try {
    Copy-Item (Join-Path $PSScriptRoot 'uninstall.ps1') $appDir -Force
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\BetterHotkeys'
    New-Item $key -Force | Out-Null
    $uninstall = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$appDir\uninstall.ps1`""
    $values = @{
        DisplayName = 'BetterHotkeys'; DisplayVersion = '1.1.0'; Publisher = 'Wyatt852456'
        UninstallString = $uninstall; DisplayIcon = "$(Find-Ahk),0"
        InstallLocation = $dest; URLInfoAbout = 'https://github.com/Wyatt852456/BetterHotkeys'
    }
    foreach ($name in $values.Keys) { Set-ItemProperty $key $name $values[$name] }
    Set-ItemProperty $key 'NoModify' 1 -Type DWord
    Set-ItemProperty $key 'NoRepair' 1 -Type DWord
    Info 'Settings > Apps > Installed apps > BetterHotkeys'
} catch {
    Warn "Could not register uninstaller: $($_.Exception.Message)"
    $failed += 'uninstaller'
}

# ---------------------------------------------------------------- done

Write-Host ''
if ($failed) {
    Warn "Finished with problems: $($failed -join ', '). Run this again to retry."
} else {
    Write-Host '  All set!' -ForegroundColor Green
}
Write-Host ''
Write-Host '  Win + K               hotkey cheatsheet' -ForegroundColor Gray
Write-Host '  Win + Shift + Space   web apps (Ctrl+N to make one, e.g. Gmail)' -ForegroundColor Gray
Write-Host '  Win + Shift + T       theme picker (Omarchy themes)' -ForegroundColor Gray
Write-Host '  Win + W               close window' -ForegroundColor Gray
Write-Host ''
Info "Add your own hotkeys in $dest\hotkeys.ahk"
Info 'Already-open terminals pick up the new font after reopening.'
Read-Host "`n  Press Enter to close"
