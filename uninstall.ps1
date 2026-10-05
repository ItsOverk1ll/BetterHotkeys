# Uninstalls BetterHotkeys and puts the Windows defaults back. Runs in Windows PowerShell 5.1 or 7.
# Started from Settings > Apps > Installed apps > BetterHotkeys > Uninstall, or run directly:
#   powershell -ExecutionPolicy Bypass -File uninstall.ps1
#  - Stops the hotkeys and removes them from startup
#  - Removes the BetterHotkeys scripts from Documents\AutoHotkey (and, if you choose, your web apps)
#  - Removes the theme, font, cursor, opacity and padding settings from Windows Terminal,
#    so it goes back to the default look (your profiles and other settings are kept)
#  - Uninstalls the programs setup installed (listed in installed.txt). PowerShell 7 and
#    Windows Terminal stay, since Windows 11 ships with Terminal. Without installed.txt
#    (installed by an older version), it asks about each program.

$ErrorActionPreference = 'Stop'
# Anything unexpected: show the error and keep the window open, instead of closing right away
trap {
    Write-Host "`n  Uninstall stopped with an error:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
    Read-Host "`n  Press Enter to close"
    exit 1
}
$Host.UI.RawUI.WindowTitle = 'BetterHotkeys uninstall'
$failed = @()

function Step($text) { Write-Host "`n> $text" -ForegroundColor Green }
function Info($text) { Write-Host "  $text" -ForegroundColor DarkGray }
function Warn($text) { Write-Host "  $text" -ForegroundColor Yellow }
function Confirm-Choice($question) { (Read-Host "  $question (y/N)") -match '^\s*y' }

$dest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AutoHotkey'
$appDir = Join-Path $env:LOCALAPPDATA 'BetterHotkeys'
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'hotkeys.lnk'
$webAppsDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Web Apps'
$wtFile = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\BetterHotkeys'
$files = 'hotkeys.ahk', 'cheatsheet.ps1', 'send-hotkey.ahk', 'webapps.ps1', 'webapp-lib.ahk', 'open-webapp.ahk',
    'themes.ps1', 'theme-lib.ps1', 'themes.json', 'theme.txt'

# Programs setup can install, minus PowerShell 7 and Windows Terminal
$packages = [ordered]@{
    'AutoHotkey.AutoHotkey'        = 'AutoHotkey v2'
    'junegunn.fzf'                 = 'fzf'
    'DEVCOM.JetBrainsMonoNerdFont' = 'JetBrainsMono Nerd Font'
    'Git.Git'                      = 'Git'
}
$manifest = Join-Path $appDir 'installed.txt'
$toRemove = @()
$askEach = -not (Test-Path $manifest)
if (-not $askEach) {
    $installed = @(Get-Content $manifest | ForEach-Object { $_.Trim() })
    $toRemove = @($packages.Keys | Where-Object { $_ -in $installed })
}

Write-Host ''
Write-Host '  B E T T E R   H O T K E Y S   uninstall' -ForegroundColor Green
Write-Host ''
Write-Host '  This will:' -ForegroundColor Gray
Write-Host '   - stop the hotkeys and remove them from startup' -ForegroundColor Gray
Write-Host "   - delete the BetterHotkeys scripts in $dest" -ForegroundColor Gray
Write-Host '     (including hotkeys.ahk: copy it first if you added hotkeys you want to keep)' -ForegroundColor DarkGray
Write-Host '   - reset Windows Terminal to its default theme, font and cursor' -ForegroundColor Gray
if ($askEach) {
    Write-Host '   - ask which programs to uninstall' -ForegroundColor Gray
} elseif ($toRemove) {
    Write-Host "   - uninstall: $(($toRemove | ForEach-Object { $packages[$_] }) -join ', ')" -ForegroundColor Gray
}
Write-Host '  PowerShell 7 and Windows Terminal are kept.' -ForegroundColor DarkGray
Write-Host ''
if (-not (Confirm-Choice 'Continue?')) { exit 0 }

$webApps = @(Get-ChildItem $webAppsDir -Filter *.lnk -ErrorAction SilentlyContinue)
$removeWebApps = $webApps.Count -gt 0 -and (Confirm-Choice "Also remove your $($webApps.Count) web app(s) from the Start Menu?")
if ($askEach) {
    Write-Host ''
    Info 'No record of what setup installed (older version). Choose what to uninstall:'
    foreach ($id in $packages.Keys) {
        if (Confirm-Choice "Uninstall $($packages[$id])?") { $toRemove += $id }
    }
}

# ---------------------------------------------------------------- hotkeys

Step 'Stopping hotkeys'
Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($dest) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
# The popup menus, if any are open
Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($dest) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Remove-Item $startup -ErrorAction SilentlyContinue
Info 'stopped and removed from startup'

# ---------------------------------------------------------------- Windows Terminal

Step 'Resetting Windows Terminal to defaults'
# Read the theme names before the scripts are deleted
$themeNames = @('Hackerman')
$themesJson = Join-Path $dest 'themes.json'
if (Test-Path $themesJson) {
    $all = Get-Content $themesJson -Raw | ConvertFrom-Json
    $themeNames = @($all.PSObject.Properties | ForEach-Object { $_.Value.name })
}
try {
    if (Test-Path $wtFile) {
        Remove-TypeData System.Array -ErrorAction SilentlyContinue  # 5.1: keep arrays as arrays in JSON
        Copy-Item $wtFile "$wtFile.before-uninstall" -Force
        $settings = Get-Content $wtFile -Raw | ConvertFrom-Json
        function Remove-Prop($obj, $name) { if ($obj -and $obj.PSObject.Properties[$name]) { $obj.PSObject.Properties.Remove($name) } }

        if ($settings.theme -in 'Omarchy', 'Hackerman') { Remove-Prop $settings 'theme' }
        if ($settings.PSObject.Properties['themes']) {
            $settings.themes = @($settings.themes | Where-Object { $_.name -notin 'Omarchy', 'Hackerman' })
        }
        if ($settings.PSObject.Properties['schemes']) {
            $settings.schemes = @($settings.schemes | Where-Object { $_.name -notin $themeNames })
        }
        # Only undo values setup set, in case you changed them yourself
        $defaults = $settings.profiles.defaults
        if ($defaults) {
            if ($defaults.colorScheme -in $themeNames) { Remove-Prop $defaults 'colorScheme' }
            if ($defaults.cursorShape -eq 'filledBox') { Remove-Prop $defaults 'cursorShape' }
            if ($defaults.font -and $defaults.font.face -like 'JetBrainsMono*') { Remove-Prop $defaults 'font' }
            if ($defaults.opacity -eq 95) { Remove-Prop $defaults 'opacity' }
            if ("$($defaults.padding)" -eq '10') { Remove-Prop $defaults 'padding' }
        }
        [IO.File]::WriteAllText($wtFile, ($settings | ConvertTo-Json -Depth 32), (New-Object Text.UTF8Encoding $false))
        Info 'default theme, font and cursor restored (previous file kept as settings.json.before-uninstall)'
    } else {
        Info 'no settings file, nothing to reset'
    }
} catch {
    Warn "Could not reset Windows Terminal: $($_.Exception.Message)"
    $failed += 'Windows Terminal reset'
}

# ---------------------------------------------------------------- files

Step 'Removing BetterHotkeys files'
foreach ($f in $files) { Remove-Item (Join-Path $dest $f) -Force -ErrorAction SilentlyContinue }
Remove-Item (Join-Path $env:TEMP 'betterhotkeys-themes') -Recurse -Force -ErrorAction SilentlyContinue
if ($removeWebApps) {
    Remove-Item $webAppsDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $dest 'webapps') -Recurse -Force -ErrorAction SilentlyContinue
    Info 'web apps removed'
}
if ((Test-Path $dest) -and -not (Get-ChildItem $dest -Force)) { Remove-Item $dest -Force }
if (Test-Path $dest) { Info "kept $dest (it still has backups or other files of yours)" } else { Info 'done' }

# ---------------------------------------------------------------- programs

foreach ($id in $toRemove) {
    Step "Uninstalling $($packages[$id])"
    $winget = (Get-Command winget -ErrorAction SilentlyContinue).Source
    if (-not $winget) { $winget = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" }
    $proc = Start-Process $winget -ArgumentList 'uninstall', '--id', $id, '-e', '--silent', '--disable-interactivity',
        '--accept-source-agreements' -NoNewWindow -PassThru
    $handle = $proc.Handle  # needed for ExitCode to be readable later
    if (-not $proc.WaitForExit(600000)) {
        $proc.Kill()
        Warn 'took longer than 10 minutes and was stopped'
        $failed += $packages[$id]
    } elseif ($proc.ExitCode -eq -1978335212) {
        Info 'not installed, skipping'  # 0x8A150014: no installed package found
    } elseif ($proc.ExitCode -ne 0) {
        Warn "winget failed (exit $($proc.ExitCode)). You can uninstall it from Settings > Apps."
        $failed += $packages[$id]
    } else {
        Info 'uninstalled'
    }
}

# ---------------------------------------------------------------- done

Remove-Item $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($failed) {
    Warn "Finished with problems: $($failed -join ', ')"
} else {
    Write-Host '  BetterHotkeys is uninstalled.' -ForegroundColor Green
}
Info 'Already-open terminals pick up the default look after reopening.'
Read-Host "`n  Press Enter to close"

# This script may live in %LOCALAPPDATA%\BetterHotkeys; remove that folder once it has exited
if ((Test-Path $appDir) -and $PSScriptRoot -eq $appDir) {
    Start-Process cmd.exe -ArgumentList '/c', "timeout /t 2 /nobreak >nul & rmdir /s /q `"$appDir`"" -WindowStyle Hidden
} else {
    Remove-Item $appDir -Recurse -Force -ErrorAction SilentlyContinue
}
