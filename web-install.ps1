# One-line install for BetterHotkeys, without the SmartScreen warnings an unsigned exe gets:
#   irm https://raw.githubusercontent.com/ItsOverk1ll/BetterHotkeys/main/web-install.ps1 | iex
# Downloads the latest release's source and runs its install.ps1, the same installer the exe runs.
# Works when pasted into Windows PowerShell 5.1 or PowerShell 7.

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    # Windows PowerShell 5.1 may not use TLS 1.2 by default, which GitHub requires
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $repo = 'ItsOverk1ll/BetterHotkeys'
    $tag = (Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'BetterHotkeys' }).tag_name
    Write-Host "`n  Downloading BetterHotkeys $tag..." -ForegroundColor Green

    $work = Join-Path $env:TEMP "betterhotkeys-web-$tag"
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
    New-Item -ItemType Directory $work | Out-Null
    Invoke-WebRequest "https://github.com/$repo/archive/refs/tags/$tag.zip" -OutFile "$work\source.zip" -UseBasicParsing
    Expand-Archive "$work\source.zip" "$work\source" -Force

    # The zip holds one folder, BetterHotkeys-<version>. install.ps1 expects the scripts from src\
    # next to it, the same layout as inside the exe.
    $source = (Get-ChildItem "$work\source" -Directory | Select-Object -First 1).FullName
    $stage = Join-Path $work 'stage'
    New-Item -ItemType Directory $stage | Out-Null
    Copy-Item "$source\install.ps1", "$source\uninstall.ps1" $stage
    Copy-Item "$source\src\*" $stage

    # Always run the installer in Windows PowerShell 5.1, which is what it's written and tested for
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$stage\install.ps1"

    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
