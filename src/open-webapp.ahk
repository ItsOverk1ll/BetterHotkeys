#Requires AutoHotkey v2.0
#NoTrayIcon
#Include webapp-lib.ahk

; Used by webapps.ps1: open-webapp.ahk <url> <name>
; Focuses the app if a window with that name in its title is open, else launches it.

if A_Args.Length < 2
    ExitApp

WinWaitClose("Web Apps ahk_exe WindowsTerminal.exe", , 3)
WebApp(A_Args[1], A_Args[2])
