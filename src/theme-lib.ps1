# Omarchy theme helpers shared by the BetterHotkeys menus.
# themes.json holds the palettes (from Omarchy's themes/*/colors.toml); theme.txt holds the
# current theme id, set by the Win+Shift+T theme picker (themes.ps1).

function Get-Themes {
    Get-Content (Join-Path $PSScriptRoot 'themes.json') -Raw | ConvertFrom-Json -AsHashtable
}

function Get-CurrentThemeId {
    $file = Join-Path $PSScriptRoot 'theme.txt'
    $id = if (Test-Path $file) { (Get-Content $file -Raw).Trim() }
    if ($id -and (Get-Themes).Contains($id)) { $id } else { 'hackerman' }
}

function Get-CurrentTheme { (Get-Themes)[(Get-CurrentThemeId)] }

# "#82FB9C" -> ANSI 24-bit foreground (or background with -Background)
function Get-Ansi([string]$hex, [switch]$Background) {
    $r, $g, $b = 1, 3, 5 | ForEach-Object { [Convert]::ToInt32($hex.Substring($_, 2), 16) }
    "$([char]27)[$(if ($Background) { 48 } else { 38 });2;$r;$g;${b}m"
}

function Get-FzfColors($theme) {
    $t = $theme
    "border:$($t.muted),label:$($t.accent),prompt:$($t.accent),pointer:$($t.accent),header:$($t.dark_foreground)," +
    "hl:$($t.accent),hl+:$($t.accent),info:$($t.dark_foreground),fg+:$($t.bright_foreground),bg+:$($t.selection),gutter:-1"
}
