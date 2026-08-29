# PowerShell script for: ./make chai
param (
    [string]$Target = "chai"
)

$env:Path += ";C:\flutter_windows_3.24.5-stable\flutter\bin;C:\Users\pes2u\platform-tools;C:\Users\pes2u\jdk-17\bin"
$env:JAVA_HOME = "C:\Users\pes2u\jdk-17"

Write-Host "☕ [make $Target] Initializing teamChaiAndCode environment..." -ForegroundColor Cyan

# 1. Install backend requirements
if (Test-Path "requirements.txt") {
    Write-Host "📦 Installing Python dependencies..." -ForegroundColor Yellow
    pip install -r requirements.txt
}

# 2. Setup Flutter frontend
if (Test-Path "frontend/pubspec.yaml") {
    Write-Host "📱 Fetching Flutter packages..." -ForegroundColor Yellow
    Push-Location frontend
    flutter pub get
    Pop-Location
}

Write-Host "✅ Environment setup complete! Use './sip chai' to run." -ForegroundColor Green
