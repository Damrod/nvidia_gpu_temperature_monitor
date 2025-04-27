# GPU Temperature Monitor - Installer Builder Script
#
# Purpose: Creates a distributable MSI installer package for end users.
# This script is used by developers to create release packages, NOT for installation.
#
# What this script does:
# 1. Builds a standalone mock nvidia-smi executable for systems without NVIDIA GPUs
# 2. Creates an MSI installer package using WiX Toolset
# 3. Outputs a distributable installer in the dist/ directory
#
# Usage:
# 1. Run from PowerShell: .\scripts\build_installer.ps1
# 2. Distribute the resulting MSI file to end users
#
# Requirements:
# - WiX Toolset must be installed and in PATH
# - Python with PyInstaller package

param (
    [switch]$Release
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $ProjectRoot "build"
$DistDir = Join-Path $ProjectRoot "dist"

function Test-WiXToolset {
    try {
        $null = Get-Command candle.exe -ErrorAction Stop
        $null = Get-Command light.exe -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Build-MockNvidiaSmi {
    Write-Host "Building mock nvidia-smi..."
    
    # Clean previous build artifacts
    if (Test-Path $BuildDir) { Remove-Item -Path $BuildDir -Recurse -Force }
    if (Test-Path $DistDir) { Remove-Item -Path $DistDir -Recurse -Force }
    
    # Create build directories
    New-Item -ItemType Directory -Force -Path $BuildDir, $DistDir | Out-Null
    
    # Build mock nvidia-smi
    python -m PyInstaller --onefile (Join-Path $ProjectRoot "src\mock\nvidia_smi.py") --name nvidia-smi --distpath $DistDir
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build mock nvidia-smi"
    }
}

function Build-Installer {
    Write-Host "Building installer..."
    
    # Compile WiX source
    $WixObj = Join-Path $BuildDir "installer.wixobj"
    $MsiFile = Join-Path $DistDir "gpu-temp-monitor-setup.msi"
    
    # Change to scripts directory for WiX tools
    Push-Location $PSScriptRoot
    
    try {
        # Build installer with additional validation
        candle.exe -ext WixUtilExtension `
                  -ext WixUIExtension `
                  -arch x64 `
                  -v `
                  -trace `
                  installer.wxs `
                  -out $WixObj
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to compile WiX source"
        }
        
        light.exe -ext WixUtilExtension `
                 -ext WixUIExtension `
                 -cultures:en-us `
                 -loc installer.wxl `
                 -out $MsiFile `
                 -v `
                 -sval `
                 -dcl:high `
                 -notidy `
                 $WixObj
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to link WiX objects"
        }
        
        # Verify the MSI after creation
        Write-Host "Verifying MSI package..."
        $msival = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin\x86\msival.exe"
        if (Test-Path $msival) {
            & $msival $MsiFile
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "MSI validation found issues"
            }
        }
        
        # Clean up intermediate files
        Remove-Item $WixObj -Force
    }
    finally {
        # Restore original directory
        Pop-Location
    }
}

try {
    # Check WiX toolset
    if (-not (Test-WiXToolset)) {
        Write-Host "WiX Toolset not found. Please install WiX Toolset v3.11 or later:" -ForegroundColor Yellow
        Write-Host "1. Download from: https://github.com/wixtoolset/wix3/releases/latest" -ForegroundColor Yellow
        Write-Host "2. Run the installer" -ForegroundColor Yellow
        Write-Host "3. Add WiX bin directory to PATH (typically 'C:\Program Files (x86)\WiX Toolset v3.11\bin')" -ForegroundColor Yellow
        exit 1
    }
    
    # Build mock nvidia-smi first
    Build-MockNvidiaSmi
    
    # Build the installer
    Build-Installer
    
    Write-Host "`nBuild completed successfully!" -ForegroundColor Green
    Write-Host "Installer is available at: $MsiFile" -ForegroundColor Green
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
} 