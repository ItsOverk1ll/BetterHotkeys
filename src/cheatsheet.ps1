# Hotkey cheatsheet: custom bindings from hotkeys.ahk (";; Keys | Description" lines),
# GlazeWM bindings ("# doc: Keys | Description" lines) and common Windows built-ins,
# shown in fzf. Opened by Win+K; Enter runs the selected hotkey.

$ErrorActionPreference = 'Stop'
# UTF-8 without BOM, otherwise the first line piped to fzf starts with U+FEFF
[Console]::OutputEncoding = $OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'theme-lib.ps1')

# Common Windows built-ins
$windows = @(
    'Win + Left / Right | Snap window left / right'
    'Win + Up / Down | Maximize / restore or minimize'
    'Win + Shift + Left / Right | Move window to other monitor'
    'Win + Tab | Task view'
    'Win + 1-9 | Open / switch to taskbar app'
    'Win + E | File Explorer'
    'Win + L | Lock PC'
    'Win + D | Show / hide desktop'
    'Win + Home | Minimize all but active window'
    'Win + Z | Snap layouts'
    'Win + Ctrl + D | New virtual desktop'
    'Win + Ctrl + Left / Right | Switch virtual desktop'
    'Win + Ctrl + F4 | Close virtual desktop'
    'Win + V | Clipboard history'
    'Win + Shift + S | Screenshot (Snipping Tool)'
    'Win + PrtScn | Full screenshot to Pictures'
    'Win + . | Emoji and symbols'
    'Win + H | Voice typing'
    'Win + I | Settings'
    'Win + R | Run dialog'
    'Win + X | Power user menu'
    'Win + A | Quick settings'
    'Win + N | Notifications and calendar'
    'Win + P | Display / projection mode'
    'Win + G | Xbox Game Bar'
    'Win + Alt + R | Record screen (Game Bar)'
    'Ctrl + Shift + Esc | Task Manager'
    'Win + Ctrl + Shift + B | Reset graphics driver'
)

$custom = Get-Content (Join-Path $PSScriptRoot 'hotkeys.ahk') |
    Where-Object { $_ -match '^;;\s*\S.*\|' } |
    ForEach-Object { $_ -replace '^;;\s*', '' }

# Each GlazeWM doc line is paired with the "commands:" line that follows it
$glaze = @(); $doc = $null
foreach ($line in Get-Content "$env:USERPROFILE\.glzr\glazewm\config.yaml" -ErrorAction SilentlyContinue) {
    if ($line -match '^\s*#\s*doc:\s*(\S.*\|.*)$') { $doc = $Matches[1] }
    elseif ($doc -and $line -match "commands:\s*\[(.*)\]") {
        $cmds = [regex]::Matches($Matches[1], "'([^']*)'") | ForEach-Object { $_.Groups[1].Value }
        $glaze += [pscustomobject]@{ Line = $doc; Command = $cmds -join ';;' }
        $doc = $null
    }
}

$esc = [char]27
$keyWidth = 32
# A GlazeWM command, if any, rides along after a tab; fzf only displays the first field
function Format-Entry($line, $tag, $color, $command = '') {
    $keys, $desc = $line -split '\s*\|\s*', 2
    "{0}[{1}m{2,-$keyWidth}{0}[0m {3,-42} {0}[90m{4}{0}[0m`t{5}" -f $esc, $color, $keys.Trim(), $desc.Trim(), $tag, $command
}

$entries = @($custom | ForEach-Object { Format-Entry $_ 'apps' '1;32' }) +
           @($glaze | ForEach-Object { Format-Entry $_.Line 'glazewm' '36' $_.Command }) +
           @($windows | ForEach-Object { Format-Entry $_ 'windows' '37' })

$fzf = Get-Command fzf -ErrorAction SilentlyContinue
$fzf = if ($fzf) { $fzf.Source } else {
    Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\junegunn.fzf*\fzf.exe" | Select-Object -First 1 -ExpandProperty FullName
}

$choice = $entries | & $fzf --ansi --delimiter="`t" --with-nth=1 --layout=reverse --gutter=' ' --border=rounded --border-label=' Hotkeys ' `
    --prompt='  ' --pointer='>' --tiebreak=index --info=inline-right `
    --header='Type to filter  ·  Enter to run  ·  Esc to close' --header-first `
    "--color=$(Get-FzfColors (Get-CurrentTheme))"
if (-not $choice) { exit 0 }
$choice, $command = $choice -split "`t", 2

# "Win + Shift + A" -> "#+a". Entries covering several keys ("Left / Right", "1-9") can't be run.
$keys =(($choice -replace "$esc\[[0-9;]*m", '').Substring(0, $keyWidth).Trim()) -split '\s*\+\s*'
$mods = @{ Win = '#'; Ctrl = '^'; Shift = '+'; Alt = '!' }
$named = @{ PrtScn = 'PrintScreen'; Esc = 'Esc'; Tab = 'Tab'; Home = 'Home'; Up = 'Up'; Down = 'Down'
            Left = 'Left'; Right = 'Right'; F4 = 'F4'; Enter = 'Enter'; Space = 'Space' }
$last = $keys[-1]
if ($last -match '/|^\d-\d$') { exit 0 }
$send = -join ($keys[0..($keys.Count - 2)] | ForEach-Object { $mods[$_] })
$send += if ($named.ContainsKey($last)) { '{' + $named[$last] + '}' } else { $last.ToLower() }
if ($command) { $send = "glazewm:$command" }

# AutoHotkey installs per-user or machine-wide depending on how it was installed
$ahk = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe", "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe" |
    Where-Object { Test-Path $_ } | Select-Object -First 1
Start-Process $ahk `
    -ArgumentList "`"$PSScriptRoot\send-hotkey.ahk`"", "`"$send`""
exit 0
