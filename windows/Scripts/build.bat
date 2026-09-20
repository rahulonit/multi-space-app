@echo off
setlocal
echo ===================================================
echo   Building PINGGO Windows App (.NET 8 + WinUI 3)
echo ===================================================

cd /d "%~dp0\..\PINGGO"

:: Check if .NET SDK is installed
dotnet --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] .NET 8 SDK is not installed or not in PATH.
    echo Please install .NET 8 SDK from https://dotnet.microsoft.com/download/dotnet/8.0
    pause
    exit /b 1
)

echo Restoring NuGet packages and compiling PINGGO...
dotnet build PINGGO.csproj -c Release -p:Platform=x64

if %errorlevel% neq 0 (
    echo [ERROR] Build failed!
    pause
    exit /b %errorlevel%
)

echo.
echo ===================================================
echo   Build Succeeded!
echo   Executable located at:
echo   windows\PINGGO\bin\x64\Release\net8.0-windows10.0.19041.0\PINGGO.exe
echo ===================================================
pause
