# Web app manager, opened by Win+Shift+Space. Like Omarchy's webapp-install: each web app is a
# Start Menu shortcut (Start Menu\Programs\Web Apps) that opens a URL in the default browser's
# app mode (--app, no tabs or address bar), with the site's icon.
# Enter launches the selected app (focusing it if already open), Ctrl+N adds one, Ctrl+D removes one.

$ErrorActionPreference = 'Stop'
# UTF-8 without BOM, otherwise the first line piped to fzf starts with U+FEFF
[Console]::OutputEncoding = $OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'theme-lib.ps1')

$appsDir  = Join-Path ([Environment]::GetFolderPath('Programs')) 'Web Apps'
$iconsDir = Join-Path $PSScriptRoot 'webapps\icons'
New-Item -ItemType Directory -Force $appsDir, $iconsDir | Out-Null

# AutoHotkey installs per-user or machine-wide depending on how it was installed
$ahk = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe", "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe" |
    Where-Object { Test-Path $_ } | Select-Object -First 1
$shell = New-Object -ComObject WScript.Shell
$esc = [char]27
$theme = Get-CurrentTheme
$green = Get-Ansi $theme.accent; $dim = Get-Ansi $theme.dark_foreground; $red = Get-Ansi $theme.red; $reset = "$esc[0m"

$fzf = Get-Command fzf -ErrorAction SilentlyContinue
$fzf = if ($fzf) { $fzf.Source } else {
    Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\junegunn.fzf*\fzf.exe" | Select-Object -First 1 -ExpandProperty FullName
}
$fzfStyle = @('--ansi', '--layout=reverse', '--gutter= ', '--border=rounded', '--prompt=  ', '--pointer=>', '--info=inline-right',
    '--header-first', "--color=$(Get-FzfColors $theme)")

# Path of the browser that opens https links, e.g. brave.exe. App mode (--app) is a Chromium
# feature, so other browsers (Firefox) fall back to Edge, which every Windows 11 PC has.
function Get-DefaultBrowser {
    try {
        $progId = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice').ProgId
        $command = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$progId\shell\open\command").'(default)'
        if (($command -match '^"([^"]+)"' -or $command -match '^(\S+)') -and
            (Split-Path $Matches[1] -Leaf) -in 'brave.exe', 'chrome.exe', 'msedge.exe', 'vivaldi.exe', 'chromium.exe', 'thorium.exe') {
            return $Matches[1]
        }
    } catch {}
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
}

function Get-WebApps {
    Get-ChildItem $appsDir -Filter *.lnk | Sort-Object BaseName | ForEach-Object {
        $lnk = $shell.CreateShortcut($_.FullName)
        $url = if ($lnk.Arguments -match '--app=(\S+)') { $Matches[1] } else { '' }
        [pscustomobject]@{ Name = $_.BaseName; Url = $url; Path = $_.FullName }
    }
}

function Read-Value($label, $default = '') {
    $hint = if ($default) { " $dim[$default]$reset" } else { '' }
    Write-Host -NoNewline "  $green$label$reset$hint$green >$reset "
    $value = [Console]::ReadLine().Trim()
    if ($value) { $value } else { $default }
}

# Saves an .ico for the app, trying: iconUrl if given, the dashboard-icons set (high-res icons for
# popular apps, what Omarchy uses) by name, then the site's favicon.
# PNGs are scaled to at most 256px and wrapped in an ICO container (Windows reads PNG-compressed icons).
function Save-Icon($name, $url, $iconUrl, $file) {
    $slug = $name.ToLower() -replace '[^a-z0-9]+', '-'
    $sources = @()
    if ($iconUrl) { $sources += $iconUrl }
    $sources += "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/$slug.png"
    $sources += "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=$([Uri]::EscapeDataString($url))&size=256"
    $sources += "https://www.google.com/s2/favicons?domain=$(([Uri]$url).Host)&sz=256"
    foreach ($source in $sources) {
        try { $bytes = (Invoke-WebRequest $source -UseBasicParsing -TimeoutSec 10).Content } catch { continue }
        if ($bytes -is [string]) { continue }
        if ($bytes.Length -gt 4 -and $bytes[0] -eq 0 -and $bytes[1] -eq 0 -and $bytes[2] -eq 1) {
            [IO.File]::WriteAllBytes($file, $bytes); return $true      # already an .ico
        }
        if ($bytes.Length -gt 24 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) {
            $bytes = Limit-PngSize $bytes 256
            $w =[Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 16))
            $h = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 20))
            $ms = [IO.MemoryStream]::new(); $bw = [IO.BinaryWriter]::new($ms)
            $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)                 # ICONDIR
            $bw.Write([byte]($w -ge 256 ? 0 : $w)); $bw.Write([byte]($h -ge 256 ? 0 : $h))   # ICONDIRENTRY
            $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32)
            $bw.Write([uint32]$bytes.Length); $bw.Write([uint32]22)
            $bw.Write($bytes); $bw.Flush()
            [IO.File]::WriteAllBytes($file, $ms.ToArray()); return $true
        }
    }
    $false
}

function Limit-PngSize([byte[]]$bytes, $max) {
    Add-Type -AssemblyName System.Drawing
    $src = [Drawing.Bitmap]::new([IO.MemoryStream]::new($bytes))
    if ($src.Width -le $max -and $src.Height -le $max) { $src.Dispose(); return ,$bytes }
    $scale = $max / [Math]::Max($src.Width, $src.Height)
    $dst = [Drawing.Bitmap]::new([int]($src.Width * $scale), [int]($src.Height * $scale))
    $g = [Drawing.Graphics]::FromImage($dst)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.DrawImage($src, 0, 0, $dst.Width, $dst.Height)
    $ms = [IO.MemoryStream]::new()
    $dst.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $dst.Dispose(); $src.Dispose()
    ,$ms.ToArray()
}

function New-WebApp {
    Clear-Host
    Write-Host "`n  ${green}New web app$reset  $dim(leave URL empty to cancel)$reset`n"
    $clip = (Get-Clipboard -Raw -ErrorAction SilentlyContinue) -as [string]
    $clip = if ($clip -and $clip.Trim() -match '^https?://\S+$') { $clip.Trim() } else { '' }
    $url = Read-Value 'URL' $clip
    if (-not $url) { return }
    if ($url -notmatch '^[a-z]+://') { $url = "https://$url" }
    try { $uri = [Uri]$url } catch { Write-Host "  ${red}Not a valid URL$reset"; Start-Sleep 2; return }

    $guess = (Get-Culture).TextInfo.ToTitleCase(($uri.Host -replace '^(www|app|mail)\.', '' -split '\.')[0])
    $name = Read-Value 'Name' $guess
    $name = ($name -replace '[\\/:*?"<>|]', '').Trim()
    if (-not $name) { return }
    $lnkPath = Join-Path $appsDir "$name.lnk"
    if ((Test-Path $lnkPath) -and (Read-Value "$name exists. Replace? (y/N)") -notmatch '^y') { return }
    $iconUrl = Read-Value 'Icon URL' 'site favicon'
    if ($iconUrl -eq 'site favicon') { $iconUrl = '' }

    Write-Host "`n  ${dim}Fetching icon...$reset"
    $icon = Join-Path $iconsDir "$name.ico"
    $hasIcon = Save-Icon $name $url $iconUrl $icon

    $browser = Get-DefaultBrowser
    $lnk = $shell.CreateShortcut($lnkPath)
    $lnk.TargetPath = $browser
    $lnk.Arguments = "--app=$url"
    $lnk.Description = "$name web app"
    $lnk.IconLocation = if ($hasIcon) { "$icon,0" } else { "$browser,0" }
    $lnk.Save()
    Write-Host "  ${green}Created $name$reset $dim(also in Start Menu > Web Apps)$reset"
    if (-not $hasIcon) { Write-Host "  ${dim}Couldn't get an icon, using the browser's$reset" }
    Start-Sleep -Milliseconds 900
}

function Remove-WebApp($app) {
    if ((Read-Value "Remove $($app.Name)? (y/N)") -notmatch '^y') { return }
    Remove-Item -LiteralPath $app.Path
    Remove-Item -LiteralPath (Join-Path $iconsDir "$($app.Name).ico") -ErrorAction SilentlyContinue
}

while ($true) {
    $apps = @(Get-WebApps)
    $rows = @("$green+ New web app$reset`t") + @($apps | ForEach-Object {
        "{0,-28} $dim{1}$reset`t{2}" -f $_.Name, ($_.Url -replace '^https?://', ''), $_.Name
    })
    $out = $rows | & $fzf @fzfStyle --delimiter="`t" --with-nth=1 --expect='ctrl-n,ctrl-d' `
        --border-label=' Web Apps ' --header='Enter launch  ·  Ctrl+N new  ·  Ctrl+D remove  ·  Esc close'
    if (-not $out) { exit 0 }
    $key, $row = @($out)
    $app = if ($row) { $apps | Where-Object Name -eq ($row -split "`t", 2)[1] } else { $null }

    if ($key -eq 'ctrl-n' -or ($row -and -not $app)) { New-WebApp; Clear-Host; continue }
    if ($key -eq 'ctrl-d') { if ($app) { Remove-WebApp $app }; Clear-Host; continue }
    if ($app) {
        Start-Process $ahk -ArgumentList "`"$PSScriptRoot\open-webapp.ahk`"", "`"$($app.Url)`"", "`"$($app.Name)`""
        exit 0
    }
}
