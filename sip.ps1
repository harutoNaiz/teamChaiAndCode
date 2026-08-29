# PowerShell script for: ./sip chai [device]
param (
    [string]$Target = "chai",
    [string]$Device = ""
)

$env:Path += ";C:\flutter_windows_3.24.5-stable\flutter\bin;C:\Users\pes2u\platform-tools;C:\Users\pes2u\jdk-17\bin"
$env:JAVA_HOME = "C:\Users\pes2u\jdk-17"
$env:ANDROID_HOME = "C:\Users\pes2u"

# Configure Android SDK path in Flutter
& "C:\flutter_windows_3.24.5-stable\flutter\bin\flutter.bat" config --android-sdk "C:\Users\pes2u" | Out-Null

# Ensure Android SDK licenses exist
$licenseDirs = @(
    "C:\Users\pes2u\licenses",
    "C:\Users\pes2u\AppData\Local\Android\Sdk\licenses",
    "C:\Users\pes2u\platform-tools\licenses"
)
foreach ($dir in $licenseDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $licFile = Join-Path $dir "android-sdk-license"
    if (-not (Test-Path $licFile)) {
        @'
24333f8a63b1d97323d81618f86ba93949b34315
89337d0c0b5b0d9753e959343be27589d4a61c5a
d56f5187479451eabf01fb78af6dfcb131a6481e
84831b9409646a918e30573bab4c9c91346d8abd
'@ | Out-File -FilePath $licFile -Encoding ascii -NoNewline
    }
}

Write-Host "[sip $Target] Starting teamChaiAndCode stack..." -ForegroundColor Cyan

# 1. Start Flask API if python is available
$pyCmd = Get-Command python -ErrorAction SilentlyContinue
if ($pyCmd) {
    $flaskProcess = Get-Process -Name "python" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*app.py*" }
    if (-not $flaskProcess) {
        Write-Host "Starting Flask backend API (port 5000)..." -ForegroundColor Yellow
        Start-Process python -ArgumentList "app.py" -NoNewWindow
    } else {
        Write-Host "Flask backend API already running." -ForegroundColor Green
    }
}

# 2. Run Flutter App
Push-Location frontend
if ($Device -ne "") {
    Write-Host "Launching Flutter on device: $Device" -ForegroundColor Cyan
    & "C:\flutter_windows_3.24.5-stable\flutter\bin\flutter.bat" run -d $Device
} else {
    Write-Host "Launching Flutter on detected device..." -ForegroundColor Cyan
    & "C:\flutter_windows_3.24.5-stable\flutter\bin\flutter.bat" run
}
Pop-Location
