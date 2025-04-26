@echo off
setlocal enabledelayedexpansion

echo Building GPU Temperature Monitor Installer...

REM Check if NSIS is installed
where /q makensis.exe
if errorlevel 1 (
    echo NSIS not found. Please install NSIS from https://nsis.sourceforge.io/Download
    echo Make sure to add it to your PATH
    pause
    exit /b 1
)

REM Build mock nvidia-smi first
echo Building mock nvidia-smi...
python -m PyInstaller --onefile ..\src\mock\nvidia_smi.py --name nvidia-smi --distpath ..\dist
if errorlevel 1 (
    echo Failed to build mock nvidia-smi
    pause
    exit /b 1
)

REM Build the installer
echo Building installer...
makensis windows_installer.nsi
if errorlevel 1 (
    echo Failed to build installer
    pause
    exit /b 1
)

echo.
echo Build completed successfully!
echo The installer is available as gpu-temp-monitor-setup.exe
echo.
pause 