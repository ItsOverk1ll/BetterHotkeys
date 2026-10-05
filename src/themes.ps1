# Omarchy theme picker, opened by Win+Shift+T. Applies the theme to Windows Terminal (colors and
# tab bar) and to the BetterHotkeys menus. The preview pane shows each theme's palette.
#   themes.ps1                    pick a theme in fzf
#   themes.ps1 -Apply <id>        apply without the picker (no id: reapply the current theme)
#   themes.ps1 -Apply <id> -Init  also set the terminal font, cursor, opacity and padding (used by setup)

param([string]$Apply, [switch]$Init)

$ErrorActionPreference = 'Stop'
# UTF-8 without BOM, otherwise the first line piped to fzf starts with U+FEFF
[Console]::OutputEncoding = $OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'theme-lib.ps1')

$themes = Get-Themes
$esc = [char]27

function Set-Theme($id, [switch]$Init) {
    $t = $themes[$id]
    $wtDir = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
    $wtFile = Join-Path $wtDir 'settings.json'
    New-Item -ItemType Directory -Force $wtDir | Out-Null
    $settings = if (Test-Path $wtFile) { Get-Content $wtFile -Raw | ConvertFrom-Json -AsHashtable }
    if (-not $settings) { $settings = [ordered]@{ '$schema' = 'https://aka.ms/terminal-profiles-schema' } }

    $scheme = [ordered]@{
        name = $t.name; background = $t.background; foreground = $t.foreground
        cursorColor = $t.accent; selectionBackground = $t.selection
        black = $t.lighter_background; red = $t.red; green = $t.green; yellow = $t.yellow
        blue = $t.blue; purple = $t.magenta; cyan = $t.cyan; white = $t.light_foreground
        brightBlack = $t.dark_foreground; brightRed = $t.bright_red; brightGreen = $t.bright_green
        brightYellow = $t.bright_yellow; brightBlue = $t.bright_blue; brightPurple = $t.bright_magenta
        brightCyan = $t.bright_cyan; brightWhite = $t.bright_foreground
    }
    # One "Omarchy" tab-bar theme, rewritten on every switch ("Hackerman" was its name before the picker)
    $wtTheme = [ordered]@{
        name = 'Omarchy'
        tab = [ordered]@{ background = "$($t.background)FF"; showCloseButton = 'hover'; unfocusedBackground = "$($t.dark_background)FF" }
        tabRow = [ordered]@{ background = "$($t.darker_background)FF"; unfocusedBackground = "$($t.darker_background)FF" }
        window = [ordered]@{ applicationTheme = $t.mode; useMica = $false }
    }
    $settings.schemes = @($settings.schemes | Where-Object { $_ -and $_.name -ne $t.name }) + $scheme
    $settings.themes = @($settings.themes | Where-Object { $_ -and $_.name -notin 'Omarchy', 'Hackerman' }) + $wtTheme
    $settings.theme = 'Omarchy'

    # Old format: "profiles" is a plain list
    if ($settings.profiles -is [array]) { $settings.profiles = [ordered]@{ list = $settings.profiles } }
    if (-not $settings.profiles) { $settings.profiles = [ordered]@{} }
    if (-not $settings.profiles.defaults) { $settings.profiles.defaults = [ordered]@{} }
    $defaults = $settings.profiles.defaults
    $defaults.colorScheme = $t.name
    if ($Init) {
        $defaults.cursorShape = 'filledBox'
        $defaults.font = [ordered]@{ face = 'JetBrainsMono NF'; size = 11 }
        $defaults.opacity = 95
        $defaults.padding = '10'
    }

    [IO.File]::WriteAllText($wtFile, ($settings | ConvertTo-Json -Depth 32), [Text.UTF8Encoding]::new($false))
    Set-Content (Join-Path $PSScriptRoot 'theme.txt') $id -NoNewline
}

if ($PSBoundParameters.ContainsKey('Apply') -or $Init) {
    $id = if ($Apply) { $Apply } else { Get-CurrentThemeId }
    if (-not $themes.Contains($id)) { throw "Unknown theme '$id'. Themes: $($themes.Keys -join ', ')" }
    Set-Theme $id -Init:$Init
    "Applied $($themes[$id].name)"
    exit 0
}

# ---------------------------------------------------------------- picker

# Preview pane: a mock terminal drawn in each theme's colors, written to files fzf can show instantly
function Write-Preview($t, $file) {
    $width = 46
    $lines = [Collections.Generic.List[string]]::new()
    # Each line is a list of (color, text) pairs, padded to $width on the theme's background
    function Add-Line([object[]]$parts, $lineBg = $t.background) {
        $back = Get-Ansi $lineBg -Background
        $text = ''; $len = 0
        for ($i = 0; $i -lt $parts.Count; $i += 2) {
            $text += (Get-Ansi $parts[$i]) + $parts[$i + 1]; $len += $parts[$i + 1].Length
        }
        $lines.Add("$back $text$(' ' * [Math]::Max(0, $width - $len - 1))$esc[0m")
    }
    $swatch = { param($colors) $out = @(); foreach ($c in $colors) { $out += $t[$c], '███ ' }; $out }

    Add-Line @()
    Add-Line @($t.accent, " $($t.name)", $t.dark_foreground, "  $($t.mode)")
    Add-Line @()
    Add-Line (& $swatch 'lighter_background', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'light_foreground')
    Add-Line (& $swatch 'dark_foreground', 'bright_red', 'bright_green', 'bright_yellow', 'bright_blue', 'bright_magenta', 'bright_cyan', 'bright_foreground')
    Add-Line @()
    Add-Line @($t.accent, ' ~/projects', $t.magenta, ' git:(', $t.red, 'main', $t.magenta, ')', $t.foreground, ' $ ls')
    Add-Line @($t.blue, ' src/  ', $t.blue, 'docs/  ', $t.foreground, 'README.md  ', $t.green, 'build.ps1')
    Add-Line @($t.dark_foreground, ' # 3 files changed')
    Add-Line @($t.green, ' ok   ', $t.foreground, 'all tests passed')
    Add-Line @($t.yellow, ' warn ', $t.foreground, 'deprecated option')
    Add-Line @($t.red, ' err  ', $t.foreground, 'file not found')
    Add-Line @($t.cyan, ' info ', $t.foreground, 'listening on :3000')
    Add-Line @()
    Add-Line @($t.bright_foreground, ' > selected line') $t.selection
    Add-Line @($t.foreground, '   another line')
    Add-Line @()
    [IO.File]::WriteAllLines($file, $lines, [Text.UTF8Encoding]::new($false))
}

$previewDir = Join-Path $env:TEMP 'betterhotkeys-themes'
New-Item -ItemType Directory -Force $previewDir | Out-Null
$current = Get-CurrentThemeId
$ids = @($themes.Keys | Sort-Object { $themes[$_].name })
$ui = Get-CurrentTheme
$accent = Get-Ansi $ui.accent; $dim = Get-Ansi $ui.dark_foreground; $reset = "$esc[0m"

$rows = for ($i = 0; $i -lt $ids.Count; $i++) {
    $t = $themes[$ids[$i]]
    Write-Preview $t (Join-Path $previewDir "$i.txt")
    $mark = if ($ids[$i] -eq $current) { "$accent●$reset" } else { ' ' }
    "$mark {0,-20} $dim{1}$reset`t{2}" -f $t.name, $t.mode, $ids[$i]
}

$fzf = Get-Command fzf -ErrorAction SilentlyContinue
$fzf = if ($fzf) { $fzf.Source } else {
    Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\junegunn.fzf*\fzf.exe" | Select-Object -First 1 -ExpandProperty FullName
}
$start = [array]::IndexOf($ids, $current) + 1
# Previews are referenced relative to fzf's working directory, avoiding quoting issues in cmd
Push-Location $previewDir
$choice = $rows | & $fzf --ansi --delimiter="`t" --with-nth=1 --layout=reverse --border=rounded --border-label=' Themes ' `
    --prompt='  ' --pointer='>' --info=inline-right --header='Enter apply  ·  Esc close' --header-first `
    --gutter=' ' --with-shell='cmd /s /c' --preview='type {n}.txt' --preview-window='right,48,border-left' `
    --bind="load:pos($start)" "--color=$(Get-FzfColors $ui)"
Pop-Location
if (-not $choice) { exit 0 }
Set-Theme ($choice -split "`t")[-1]
