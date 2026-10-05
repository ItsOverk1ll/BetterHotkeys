; Web app helpers shared by hotkeys.ahk and open-webapp.ahk

; Opens url as an app window (no tabs/address bar) in the default browser, or focuses it if
; already open, then optionally fills the left/right half of the primary monitor.
; titleText identifies the window.
WebApp(url, titleText, side := "") {
    browser := DefaultBrowser()
    if hwnd := FindWebApp(titleText, browser) {
        WinActivate(hwnd)
        return
    }
    Run('"' browser '" --app=' url)
    if !side
        return
    deadline := A_TickCount + 10000
    while !(hwnd := FindWebApp(titleText, browser)) && A_TickCount < deadline
        Sleep(100)
    if !hwnd
        return
    WinActivate(hwnd)
    TileHalf(hwnd, side)
}

; Path of the browser that opens https links, e.g. C:\...\brave.exe. App mode (--app) is a
; Chromium feature, so other browsers (Firefox) fall back to Edge, which every Windows 11 PC has.
DefaultBrowser() {
    try {
        progId := RegRead("HKCU\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice", "ProgId")
        command := RegRead("HKCR\" progId "\shell\open\command")
        if RegExMatch(command, '^"([^"]+)"', &m) || RegExMatch(command, "^(\S+)", &m) {
            SplitPath(m[1], &exe)
            if RegExMatch(exe, "i)^(brave|chrome|msedge|vivaldi|chromium|thorium)\.exe$")
                return m[1]
        }
    }
    return EnvGet("ProgramFiles(x86)") "\Microsoft\Edge\Application\msedge.exe"
}

; App windows have the page title only; regular browser windows end in " - <Browser>"
FindWebApp(titleText, browser) {
    SplitPath(browser, &exe)
    for hwnd in WinGetList("ahk_exe " exe) {
        title := WinGetTitle(hwnd)
        if InStr(title, titleText) && !RegExMatch(title, " - (Brave|Google Chrome|Microsoft\x{200B}? Edge|Vivaldi|Chromium)$")
            return hwnd
    }
    return 0
}

TileHalf(hwnd, side) {
    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
    if WinGetMinMax(hwnd) != 0
        WinRestore(hwnd)
    ; Windows 11 windows have ~7px invisible borders; widen to hide the gap
    pad := Round(7 * A_ScreenDPI / 96)
    w := (r - l) // 2
    x := side = "left" ? l : l + w
    WinMove(x - pad, t, w + pad * 2, b - t + pad, hwnd)
}
