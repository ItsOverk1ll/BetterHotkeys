#Requires AutoHotkey v2.0
#NoTrayIcon

; Used by cheatsheet.ps1: waits for the cheatsheet window to close, then sends
; the chosen hotkey (A_Args[1], AHK syntax like "#+a") to whatever has focus.
; "glazewm:<cmd>;;<cmd>" runs GlazeWM commands instead, since GlazeWM ignores simulated keys.

if A_Args.Length < 1
    ExitApp

WinWaitClose("Hotkeys ahk_exe WindowsTerminal.exe", , 3)
Sleep(150)

keys := A_Args[1]
if (SubStr(keys, 1, 8) = "glazewm:") {
    for cmd in StrSplit(SubStr(keys, 9), ";;")
        RunWait('"C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe" command ' cmd, , "Hide")
}
else if (keys = "#l")
    DllCall("LockWorkStation")  ; Windows blocks simulated Win+L
else {
    SendLevel(1)  ; lets hotkeys in hotkeys.ahk react to this input
    Send(keys)
}
