# Builds BetterHotkeys.exe: a self-extracting IExpress package (built into Windows) that runs
# install.ps1 with the scripts in src\.
#   .\build.ps1                build from src\
#   .\build.ps1 -SyncFromLive  first copy the shared scripts from an installed copy
#                              (Documents\AutoHotkey) into src\, to package changes made there.
#                              src\hotkeys.ahk is never overwritten: it's the trimmed version for new PCs.

param([switch]$SyncFromLive)

$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'src'
$stage = Join-Path $env:TEMP 'betterhotkeys-build'
$out = Join-Path $PSScriptRoot 'BetterHotkeys.exe'

if ($SyncFromLive) {
    $live = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AutoHotkey'
    Get-ChildItem $src -File | Where-Object Name -ne 'hotkeys.ahk' | ForEach-Object {
        Copy-Item (Join-Path $live $_.Name) $_.FullName
        "synced $($_.Name)"
    }
}

Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $stage | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'install.ps1'), (Join-Path $PSScriptRoot 'uninstall.ps1') $stage
Copy-Item "$src\*" $stage

$files = Get-ChildItem $stage -File | Select-Object -ExpandProperty Name
$fileStrings = for ($i = 0; $i -lt $files.Count; $i++) { "FILE$i=`"$($files[$i])`"" }
$fileList = for ($i = 0; $i -lt $files.Count; $i++) { "%FILE$i%=" }

@"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$out
FriendlyName=BetterHotkeys
AppLaunched=cmd /c powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
$($fileStrings -join "`r`n")
[SourceFiles]
SourceFiles0=$stage\
[SourceFiles0]
$($fileList -join "`r`n")
"@ | Set-Content "$stage\betterhotkeys.sed" -Encoding Ascii

Remove-Item $out -ErrorAction SilentlyContinue
# IExpress can't open the .sed path if it's quoted (so the path must not contain spaces)
Start-Process iexpress.exe -ArgumentList '/N', '/Q', "$stage\betterhotkeys.sed" -WorkingDirectory $stage -Wait
if (-not (Test-Path $out)) { throw 'IExpress did not produce BetterHotkeys.exe' }
Remove-Item $stage -Recurse -Force
"Built $out ($([Math]::Round((Get-Item $out).Length / 1KB)) KB)"
