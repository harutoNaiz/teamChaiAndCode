# PowerShell script for: ./sip chai [device]
param (
    [string]$Target = "chai",
    [string]$Device = ""
)

$env:Path += ";C:\flutter_windows_3.24.5-stable\flutter\bin;C:\Users\pes2u\platform-tools;C:\Users\pes2u\jdk-17\bin"
$env:JAVA_HOME = "C:\Users\pes2u\jdk-17"

Write-Host "☕ [sip $Target] Starting teamChaiAndCode stack..." -ForegroundColor Cyan

# 1. Start Flask API in background job if not running
$flaskProcess = Get-Process -Name "python" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*app.py*" }
if (-not $flaskProcess) {
    Write-Host "🌐 Starting Flask backend API (port 5000)..." -ForegroundColor Yellow
    Start-Process python -ArgumentList "app.py" -NoNewWindow
} else {
    Write-Host "🌐 Flask backend API already running." -ForegroundColor Green
}

# 2. Run Flutter App
Push-Location frontend
if ($Device -ne "") {
    Write-Host "📱 Launching Flutter on device $Device..." -ForegroundColor Cyan
    flutter run -d $Device
} else {
    Write-Host "📱 Launching Flutter on default device..." -ForegroundColor Cyan
    flutter run
}
Pop-Location
