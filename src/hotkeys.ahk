#Requires AutoHotkey v2.0
#SingleInstance Force

; Lines starting with ";;" are read by the Win+K cheatsheet, formatted as:  Keys | Description
; Add your own hotkeys here; reload by double-clicking this file.

;; Win + W | Close active window
; Ignores desktop and taskbar so it can't trigger the shutdown dialog
#w:: {
    if !WinActive("ahk_class Progman") && !WinActive("ahk_class WorkerW") && !WinActive("ahk_class Shell_TrayWnd")
        WinClose("A")
}

;; Win + K | Hotkey cheatsheet (toggle)
; Closes on Esc, Enter, or losing focus
#k:: PopupTerminal("Hotkeys", "cheatsheet.ps1", 880, 560, CloseCheatsheetOnBlur)

;; Win + Shift + Space | Web apps: launch, create, remove (toggle)
#+Space:: PopupTerminal("Web Apps", "webapps.ps1", 760, 480)

;; Win + Shift + T | Theme picker (Omarchy themes)
#+t:: PopupTerminal("Themes", "themes.ps1", 900, 560)

; Toggles a small centered terminal titled `name` running a script from this folder
PopupTerminal(name, script, width, height, onBlur := "") {
    title := name " ahk_exe WindowsTerminal.exe"
    if WinExist(title) {
        WinClose(title)
        return
    }
    ; Full path, since PATH may not include PowerShell 7 until the next sign-in after setup
    pwsh := FileExist(A_ProgramFiles "\PowerShell\7\pwsh.exe") ? '"' A_ProgramFiles '\PowerShell\7\pwsh.exe"' : "pwsh"
    try Run('wt.exe -w new --focus --title "' name '" --suppressApplicationTitle ' pwsh ' -NoLogo -NoProfile -File "' A_ScriptDir "\" script '"')
    catch as err {
        MsgBox("Windows Terminal couldn't start:`n" err.Extra "`n`nRun the BetterHotkeys setup again to repair it.", "BetterHotkeys", "Iconx")
        return
    }
    if !WinWait(title, , 5)
        return
    scale := A_ScreenDPI / 96
    w := Round(width * scale), h := Round(height * scale)
    WinMove((A_ScreenWidth - w) // 2, (A_ScreenHeight - h) // 2, w, h, title)
    WinActivate(title)
    if onBlur
        SetTimer(onBlur, 200)
}

CloseCheatsheetOnBlur() {
    title := "Hotkeys ahk_exe WindowsTerminal.exe"
    if !WinExist(title)
        SetTimer(, 0)
    else if !WinActive(title) {
        WinClose(title)
        SetTimer(, 0)
    }
}
