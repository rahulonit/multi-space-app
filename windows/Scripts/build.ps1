# PowerShell Build & Publish Script for PINGGO Windows App
param(
    [string]$Configuration = "Release",
    [string]$Platform = "x64",
    [switch]$SelfContained = $true
)

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  PINGGO Windows Native App Builder (.NET 8 + WinUI 3)" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Join-Path $ScriptDir "..\PINGGO"
$OutputDir = Join-Path $ScriptDir "..\dist\windows"

# Verify dotnet CLI
if (-not (Get-Command "dotnet" -ErrorAction SilentlyContinue)) {
    Write-Error ".NET 8 SDK is not installed or not available in PATH. Please install from https://dotnet.microsoft.com/download/dotnet/8.0"
    exit 1
}

Write-Host "Project Directory: $ProjectDir" -ForegroundColor Yellow
Write-Host "Output Directory:  $OutputDir" -ForegroundColor Yellow
Write-Host "Publishing self-contained Windows executable..." -ForegroundColor Green

$publishArgs = @(
    "publish",
    "$ProjectDir\PINGGO.csproj",
    "-c", $Configuration,
    "-r", "win-$Platform",
    "-p:Platform=$Platform",
    "-o", $OutputDir
)

if ($SelfContained) {
    $publishArgs += "--self-contained"
    $publishArgs += "true"
}

& dotnet @publishArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n[SUCCESS] PINGGO Windows build complete!" -ForegroundColor Green
    Write-Host "Executable: $OutputDir\PINGGO.exe" -ForegroundColor Cyan
} else {
    Write-Error "Build failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
