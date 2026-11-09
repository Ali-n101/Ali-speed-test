param(
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "   Speedtest.net Windows Shortcut Installer          " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Unblock files in case repository was downloaded as a ZIP from GitHub
Write-Host "[1/4] Unblocking script files..." -ForegroundColor Yellow
Get-ChildItem -Path $PSScriptRoot -Recurse -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
Write-Host "      Done." -ForegroundColor Green

# 2. Check or Install Official Ookla Speedtest CLI
Write-Host "[2/4] Checking Official Ookla Speedtest CLI (speedtest.exe)..." -ForegroundColor Yellow

$localBinDir = Join-Path $PSScriptRoot 'bin'
$localExe    = Join-Path $localBinDir 'speedtest.exe'
$appDataExe  = Join-Path $env:LOCALAPPDATA 'AliSpeedTest\bin\speedtest.exe'
$wingetLink  = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\speedtest.exe'

$speedtestExe = $null
foreach ($candidate in @($localExe, $appDataExe, $wingetLink)) {
    if (Test-Path $candidate) {
        $speedtestExe = $candidate
        break
    }
}

if (-not $speedtestExe) {
    $cmd = Get-Command 'speedtest.exe' -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path $cmd.Source)) {
        $speedtestExe = $cmd.Source
    }
}

if (-not $speedtestExe) {
    Write-Host "      Downloading Official Ookla Speedtest CLI (win64)..." -ForegroundColor Cyan
    if (-not (Test-Path $localBinDir)) {
        New-Item -ItemType Directory -Path $localBinDir -Force | Out-Null
    }

    $zipUrl  = 'https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip'
    $tempZip = Join-Path $env:TEMP 'ookla-speedtest-1.2.0-win64.zip'

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
    Expand-Archive -Path $tempZip -DestinationPath $localBinDir -Force
    Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue

    if (Test-Path $localExe) {
        Unblock-File -Path $localExe -ErrorAction SilentlyContinue
        $speedtestExe = $localExe
    } else {
        throw "Failed to extract speedtest.exe from official archive."
    }
}

Write-Host "      Using CLI: $speedtestExe" -ForegroundColor Green

# 3. Pre-accept Ookla license & GDPR terms
Write-Host "[3/4] Initializing Ookla CLI license agreement..." -ForegroundColor Yellow
try {
    & $speedtestExe --accept-license --accept-gdpr --version | Out-Null
} catch { }
Write-Host "      Done." -ForegroundColor Green

# 4. Create Desktop Shortcut
Write-Host "[4/4] Creating Desktop Shortcut (Speedtest.lnk)..." -ForegroundColor Yellow

$desktopDir   = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktopDir 'Speedtest.lnk'
$vbsLauncher  = Join-Path $PSScriptRoot 'launch-silent.vbs'
$iconPath     = Join-Path $PSScriptRoot 'assets\speedtest.ico'

$wshShell = New-Object -ComObject WScript.Shell
$shortcut = $wshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath       = 'wscript.exe'
$shortcut.Arguments        = "//B //Nologo `"$vbsLauncher`""
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.WindowStyle      = 1
$shortcut.Hotkey           = 'Ctrl+Alt+S'
$shortcut.Description      = 'Measure Internet Speed via Speedtest.net without opening a browser'

if (Test-Path $iconPath) {
    $shortcut.IconLocation = "$iconPath,0"
} else {
    $shortcut.IconLocation = 'shell32.dll,13'
}

$shortcut.Save()

Write-Host "      Shortcut created on Desktop: $shortcutPath" -ForegroundColor Green
Write-Host "      Keyboard Shortcut enabled  : Ctrl + Alt + S" -ForegroundColor Green
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "   Setup Complete!                                   " -ForegroundColor Green
Write-Host "   Double-click 'Speedtest' on your Desktop anytime  " -ForegroundColor White
Write-Host "   or press Ctrl + Alt + S to test your speed.       " -ForegroundColor White
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

if (-not $NoLaunch) {
    Write-Host "Launching Speedtest popup now..." -ForegroundColor Cyan
    Start-Process -FilePath 'wscript.exe' -ArgumentList "//B //Nologo `"$vbsLauncher`""
}
