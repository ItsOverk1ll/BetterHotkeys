# BetterHotkeys setup for a fresh Windows 11 PC. Runs in Windows PowerShell 5.1 (what ships with Windows).
#  - Installs winget if it's missing, then AutoHotkey v2, fzf, PowerShell 7, Windows Terminal,
#    JetBrainsMono Nerd Font and Git with it
#  - Copies the hotkey scripts to Documents\AutoHotkey and starts them at sign-in:
#      Win+K  hotkey cheatsheet   Win+Shift+Space  web app manager   Win+Shift+T  theme picker
#      Win+W  close window
#  - Registers an uninstaller in Settings > Apps (uninstall.ps1 removes what setup installed)
#  - Applies an Omarchy theme (Hackerman by default) to Windows Terminal; Win+Shift+T switches themes
# Safe to run again: existing scripts are backed up before being replaced.

$ErrorActionPreference = 'Stop'
$log = Join-Path $env:TEMP 'betterhotkeys-setup.log'
try { Start-Transcript $log -Force | Out-Null } catch {}

# Anything unexpected: show the error and keep the window open, instead of closing right away
trap {
    Write-Host "`n  Setup stopped with an error:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
    Write-Host "  Log: $log" -ForegroundColor DarkGray
    try { Stop-Transcript | Out-Null } catch {}
    Read-Host "`n  Press Enter to close"
    exit 1
}

# Runs a program and returns its output (including error output) as text. Windows PowerShell 5.1
# turns any error output from a program into a script-stopping error while $ErrorActionPreference
# is 'Stop', even when it's redirected, so this relaxes it for the call.
function Invoke-Program([scriptblock]$programCall) {
    $ErrorActionPreference = 'Continue'
    & $programCall 2>&1 | ForEach-Object { "$_" }
}

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

# Path to a working winget, or $null
function Find-Winget {
    $candidates = @((Get-Command winget -ErrorAction SilentlyContinue).Source, "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe")
    foreach ($path in $candidates) {
        if ($path -and (Test-Path $path)) {
            try { if ((Invoke-Program { & $path --version }) -match '^v\d') { return $path } } catch {}
        }
    }
    $null
}

# Downloads url to file, printing progress. Fails if the connection stalls for a minute.
function Get-File($url, $file, $label) {
    $request = [Net.HttpWebRequest]::Create($url)
    $request.Timeout = 60000; $request.ReadWriteTimeout = 60000
    $response = $request.GetResponse()
    $total = $response.ContentLength
    $in = $response.GetResponseStream()
    $out = [IO.File]::Create($file)
    try {
        $buffer = New-Object byte[] 1MB
        $done = 0; $shown = -10
        while (($n = $in.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $out.Write($buffer, 0, $n); $done += $n
            $pct = if ($total -gt 0) { [int](100 * $done / $total) } else { 0 }
            if ($pct -ge $shown + 10) {
                $shown = $pct - ($pct % 10)
                Info ("{0}: {1}% of {2:N0} MB" -f $label, $pct, ($total / 1MB))
            }
        }
    } finally { $out.Close(); $in.Close(); $response.Close() }
}

# winget comes with "App Installer". If it's missing or broken, first try registering the copy
# Windows already has (common on a brand-new account), then install App Installer and its
# dependencies straight from winget's GitHub releases.
Step 'Checking winget'
$winget = Find-Winget
if (-not $winget) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Info 'Registering App Installer...'
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe } catch {}
    $winget = Find-Winget

    if (-not $winget) {
        Info 'Downloading winget from GitHub (about 300 MB)...'
        $tmp = Join-Path $env:TEMP 'betterhotkeys-winget'
        try {
            New-Item -ItemType Directory -Force $tmp | Out-Null
            $base = 'https://github.com/microsoft/winget-cli/releases/latest/download'
            Get-File "$base/DesktopAppInstaller_Dependencies.zip" "$tmp\deps.zip" 'dependencies'
            Get-File "$base/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" "$tmp\winget.msixbundle" 'winget'
            Info 'Installing winget (this can take a minute)...'
            Expand-Archive "$tmp\deps.zip" "$tmp\deps" -Force
            # The zip has a folder per architecture (x64, arm64, ...)
            $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
            $deps = @(Get-ChildItem "$tmp\deps" -Recurse -Include *.appx, *.msix |
                Where-Object { $_.FullName -match "\\$arch\\" } | Select-Object -ExpandProperty FullName)
            $ProgressPreference = 'SilentlyContinue'
            if ($deps) { Add-AppxPackage -Path "$tmp\winget.msixbundle" -DependencyPath $deps -ForceApplicationShutdown }
            else { Add-AppxPackage -Path "$tmp\winget.msixbundle" -ForceApplicationShutdown }
            $ProgressPreference = 'Continue'
        } catch { Info "that didn't work: $($_.Exception.Message)" }
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        $winget = Find-Winget
    }
}
if (-not $winget) {
    Warn 'Could not install winget. Install "App Installer" from the Microsoft Store'
    Warn '(https://apps.microsoft.com/detail/9NBLGGH4NNS1), then run this again.'
    try { Stop-Transcript | Out-Null } catch {}
Read-Host "`n  Press Enter to close"
    exit 1
}
Info "ok ($(Invoke-Program { & $winget --version }))"

# --no-upgrade stops winget from upgrading a package that is already installed (older winget lacks it)
$noUpgrade = if ((Invoke-Program { & $winget install --help }) -match '--no-upgrade') { '--no-upgrade' } else { $null }

# Skips the package if $isInstalled finds it, or if winget already knows about it (any install source;
# -SkipListCheck trusts only $isInstalled). winget gets 10 minutes; if it's stuck, it's stopped and
# setup moves on.
function Install-Package($id, $name, [scriptblock]$isInstalled, [switch]$SkipListCheck, [scriptblock]$BeforeInstall) {
    Step "Installing $name"
    if (& $isInstalled) { Info 'already installed, skipping'; return }
    if (-not $SkipListCheck) {
        Invoke-Program { & $winget list --id $id -e --accept-source-agreements --disable-interactivity } | Out-Null
        if ($LASTEXITCODE -eq 0) { Info 'already installed, skipping'; return }
    }
    if ($BeforeInstall) { & $BeforeInstall }

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

# Path to a PowerShell 7 that actually runs, or $null. A pwsh.exe can exist and still fail: a
# Microsoft Store copy without a license (common on VMs) fails with "No applicable app licenses found".
function Find-Pwsh {
    $candidates = @("$env:ProgramFiles\PowerShell\7\pwsh.exe") + @(Get-Command pwsh -All -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Source })
    foreach ($path in $candidates) {
        if (-not $path -or -not (Test-Path $path)) { continue }
        try {
            $major = Invoke-Program { & $path -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.Major' }
            if (($major | Select-Object -Last 1) -match '^\d+$' -and [int]($major | Select-Object -Last 1) -ge 7) { return $path }
        } catch {}
    }
    $null
}

# True if Windows Terminal starts. Like PowerShell above, a Microsoft Store copy without a license is
# installed but fails with "No applicable app licenses found". The check flashes a window briefly.
function Test-Terminal {
    if (-not (Get-AppxPackage Microsoft.WindowsTerminal)) { return $false }
    try {
        Start-Process "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe" -ArgumentList '-w new cmd /c exit'
        $script:terminalStarted = $true
    } catch { $script:terminalStarted = $false }
    $script:terminalStarted
}

# Last resort when the installed Windows Terminal won't start: Microsoft's portable build, a plain
# folder that needs no package, Store license or admin rights. The hotkeys use it when wt.exe fails.
$portableTerminal = Join-Path $env:LOCALAPPDATA 'BetterHotkeys\terminal'
function Install-PortableTerminal {
    $release = Invoke-RestMethod 'https://api.github.com/repos/microsoft/terminal/releases/latest' -Headers @{ 'User-Agent' = 'BetterHotkeys' }
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $asset = $release.assets | Where-Object { $_.name -match "_$arch\.zip$" } | Select-Object -First 1
    if (-not $asset) { throw "no $arch build in Windows Terminal $($release.tag_name)" }
    $zip = Join-Path $env:TEMP $asset.name
    $unzipped = Join-Path $env:TEMP 'betterhotkeys-terminal'
    Get-File $asset.browser_download_url $zip 'Windows Terminal'
    Expand-Archive $zip $unzipped -Force
    # The zip holds one folder, terminal-<version>
    $folder = (Get-ChildItem $unzipped -Recurse -Filter wt.exe | Select-Object -First 1).DirectoryName
    New-Item -ItemType Directory -Force $portableTerminal | Out-Null
    Copy-Item "$folder\*" $portableTerminal -Recurse -Force
    Remove-Item $zip, $unzipped -Recurse -Force -ErrorAction SilentlyContinue
}
function Test-PortableTerminal {
    $wt = Join-Path $portableTerminal 'wt.exe'
    if (-not (Test-Path $wt)) { return $false }
    try { Start-Process $wt -ArgumentList '-w new cmd /c exit'; $true } catch { $false }
}

# Installs PowerShell 7 from the official MSI on GitHub (asks for admin rights)
function Install-PwshMsi {
    $release = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -Headers @{ 'User-Agent' = 'BetterHotkeys' }
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $asset = $release.assets | Where-Object { $_.name -match "-win-$arch\.msi$" } | Select-Object -First 1
    if (-not $asset) { throw "no $arch MSI in PowerShell $($release.tag_name)" }
    $msi = Join-Path $env:TEMP $asset.name
    Get-File $asset.browser_download_url $msi 'PowerShell 7'
    Info 'Installing PowerShell 7 (Windows may ask for permission)...'
    $proc = Start-Process msiexec.exe -ArgumentList '/i', "`"$msi`"", '/quiet', '/norestart', 'ADD_PATH=1' -Verb RunAs -Wait -PassThru
    Remove-Item $msi -ErrorAction SilentlyContinue
    if ($proc.ExitCode -notin 0, 3010) { throw "the installer failed (exit $($proc.ExitCode))" }
}

Install-Package 'AutoHotkey.AutoHotkey' 'AutoHotkey v2' { [bool](Find-Ahk) }
Install-Package 'junegunn.fzf' 'fzf' {
    Test-Any 'fzf' "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\junegunn.fzf*\fzf.exe", "$env:USERPROFILE\scoop\shims\fzf.exe"
}
# Checked by running it, and winget's list is skipped: winget may count an unlicensed Store copy
Install-Package 'Microsoft.PowerShell' 'PowerShell 7' { [bool](Find-Pwsh) } -SkipListCheck
if (-not (Find-Pwsh)) {
    Info "PowerShell 7 still doesn't run, downloading it from GitHub..."
    try {
        Install-PwshMsi
        if (Find-Pwsh) { $failed = @($failed | Where-Object { $_ -ne 'PowerShell 7' }); Info 'ok' }
        else { throw 'it still does not run after installing' }
    } catch {
        Warn "Could not install PowerShell 7: $($_.Exception.Message)"
        if ($failed -notcontains 'PowerShell 7') { $failed += 'PowerShell 7' }
    }
}
# Checked by starting it. A copy that doesn't start (no Store license) is removed first, then
# winget installs Microsoft's GitHub release, which doesn't need a Store license.
Install-Package 'Microsoft.WindowsTerminal' 'Windows Terminal' { Test-Terminal } -SkipListCheck -BeforeInstall {
    $broken = Get-AppxPackage Microsoft.WindowsTerminal
    if ($broken) {
        Info "the installed copy doesn't start (missing Microsoft Store license), replacing it..."
        try { $broken | Remove-AppxPackage } catch { Warn "could not remove it: $($_.Exception.Message)" }
    }
}
if (-not $terminalStarted -and -not (Test-Terminal)) {
    $portableWorks = Test-PortableTerminal
    if ($portableWorks) {
        Info 'using the portable Windows Terminal installed earlier'
    } else {
        Info "Windows Terminal still doesn't start, downloading the portable version..."
        try { Install-PortableTerminal } catch { Info "that didn't work: $($_.Exception.Message)" }
        $portableWorks = Test-PortableTerminal
        if ($portableWorks) { Info "ok, the hotkey menus will use it ($portableTerminal)" }
    }
    if ($portableWorks) {
        $failed = @($failed | Where-Object { $_ -ne 'Windows Terminal' })
    } else {
        Warn "Windows Terminal doesn't start, so the hotkey menus won't open."
        Warn 'Try installing "Windows Terminal" from the Microsoft Store, then run this again.'
        if ($failed -notcontains 'Windows Terminal') { $failed += 'Windows Terminal' }
    }
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
$pwsh = Find-Pwsh
$wtFile = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (-not $pwsh) {
    Warn 'PowerShell 7 not found, theme not applied'
    $failed += 'Windows Terminal theme'
} else {
    if (Test-Path $wtFile) { Copy-Item $wtFile "$wtFile.before-betterhotkeys" -Force }
    try {
        $out = (Invoke-Program { & $pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'themes.ps1') -Init }) -join ' '
        if ($LASTEXITCODE -ne 0) { throw $out }
        Info $out
    } catch {
        Warn "Theme failed: $($_.Exception.Message)"
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
        DisplayName = 'BetterHotkeys'; DisplayVersion = '1.2.5'; Publisher = 'Wyatt852456'
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
try { Stop-Transcript | Out-Null } catch {}
Read-Host "`n  Press Enter to close"
