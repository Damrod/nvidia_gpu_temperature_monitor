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
$LogDir = Join-Path $BuildDir "logs"

function Find-WiXToolset {
    $wixPaths = @(
        "C:\Program Files (x86)\WiX Toolset v3.14\bin",
        "C:\Program Files (x86)\WiX Toolset v3.11\bin",
        "C:\Program Files\WiX Toolset v3.14\bin",
        "C:\Program Files\WiX Toolset v3.11\bin"
    )
    
    foreach ($path in $wixPaths) {
        if (Test-Path (Join-Path $path "candle.exe")) {
            return $path
        }
    }
    return $null
}

function Test-WiXToolset {
    $wixPath = Find-WiXToolset
    if ($wixPath) {
        $env:Path = "$wixPath;$env:Path"
        Write-Host "Found WiX Toolset at: $wixPath" -ForegroundColor Green
        return $true
    }
    return $false
}

function Build-MockNvidiaSmi {
    Write-Host "Building mock nvidia-smi..." -ForegroundColor Cyan
    
    # Clean previous build artifacts but preserve logs
    if (Test-Path $BuildDir) { 
        Get-ChildItem -Path $BuildDir -Exclude "logs" | Remove-Item -Recurse -Force 
    }
    if (Test-Path $DistDir) { Remove-Item -Path $DistDir -Recurse -Force }
    
    # Create build directories
    New-Item -ItemType Directory -Force -Path $BuildDir, $DistDir, $LogDir | Out-Null
    
    # Build mock nvidia-smi with correct path
    $mockNvidiaSmiPath = Join-Path $ProjectRoot "src\mock\nvidia_smi.py"
    Write-Host "Building from: $mockNvidiaSmiPath" -ForegroundColor Cyan
    
    $buildLog = Join-Path $LogDir "mock_nvidia_smi_build.log"
    $process = Start-Process -FilePath "python" -ArgumentList "-m PyInstaller --onefile `"$mockNvidiaSmiPath`" --name nvidia-smi --distpath `"$DistDir`"" -NoNewWindow -Wait -PassThru -RedirectStandardOutput $buildLog -RedirectStandardError "$buildLog.err"
    
    if ($process.ExitCode -ne 0) {
        Get-Content $buildLog, "$buildLog.err"
        throw "Failed to build mock nvidia-smi"
    }
}

function Build-Installer {
    Write-Host "Building installer with enhanced logging..." -ForegroundColor Cyan
    
    # Compile WiX source
    $WixObj = Join-Path $BuildDir "installer.wixobj"
    $MsiFile = Join-Path $DistDir "gpu-temp-monitor-setup.msi"
    $candleLog = Join-Path $LogDir "candle.log"
    $lightLog = Join-Path $LogDir "light.log"
    
    # Change to scripts directory for WiX tools
    Push-Location $PSScriptRoot
    
    try {
        # Build installer with additional validation and logging
        Write-Host "Compiling WiX source..." -ForegroundColor Cyan
        $candleArgs = @(
            "-ext", "WixUtilExtension",
            "-ext", "WixUIExtension",
            "-arch", "x64",
            "-v",
            "-trace",
            "installer.wxs",
            "-out", $WixObj
        )
        
        $process = Start-Process -FilePath "candle.exe" -ArgumentList $candleArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $candleLog -RedirectStandardError "$candleLog.err"
        if ($process.ExitCode -ne 0) {
            Get-Content $candleLog, "$candleLog.err"
            throw "Failed to compile WiX source"
        }
        
        Write-Host "Linking WiX objects..." -ForegroundColor Cyan
        $lightArgs = @(
            "-ext", "WixUtilExtension",
            "-ext", "WixUIExtension",
            "-cultures:en-us",
            "-loc", "installer.wxl",
            "-out", $MsiFile,
            "-v",
            "-sval",
            "-dcl:high",
            "-notidy",
            $WixObj
        )
        
        $process = Start-Process -FilePath "light.exe" -ArgumentList $lightArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $lightLog -RedirectStandardError "$lightLog.err"
        if ($process.ExitCode -ne 0) {
            Get-Content $lightLog, "$lightLog.err"
            throw "Failed to link WiX objects"
        }
        
        # Verify the MSI after creation
        Write-Host "Verifying MSI package..." -ForegroundColor Cyan
        $msival = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin\x86\msival.exe"
        if (Test-Path $msival) {
            $msivalLog = Join-Path $LogDir "msival.log"
            $process = Start-Process -FilePath $msival -ArgumentList $MsiFile -NoNewWindow -Wait -PassThru -RedirectStandardOutput $msivalLog -RedirectStandardError "$msivalLog.err"
            if ($process.ExitCode -ne 0) {
                Get-Content $msivalLog, "$msivalLog.err"
                Write-Warning "MSI validation found issues"
            }
        }
        
        # Clean up intermediate files but keep logs
        Remove-Item $WixObj -Force -ErrorAction SilentlyContinue
        
        Write-Host "Build logs available in: $LogDir" -ForegroundColor Green
    }
    finally {
        # Restore original directory
        Pop-Location
    }
}

try {
    # Check WiX toolset
    if (-not (Test-WiXToolset)) {
        Write-Host "WiX Toolset not found in common installation paths. Please install WiX Toolset v3.11 or later:" -ForegroundColor Yellow
        Write-Host "1. Download from: https://github.com/wixtoolset/wix3/releases/latest" -ForegroundColor Yellow
        Write-Host "2. Run the installer" -ForegroundColor Yellow
        Write-Host "3. Add WiX bin directory to PATH" -ForegroundColor Yellow
        exit 1
    }
    
    # Build mock nvidia-smi first
    Build-MockNvidiaSmi
    
    # Build the installer
    Build-Installer
    
    Write-Host "`nBuild completed successfully!" -ForegroundColor Green
    Write-Host "Installer is available at: $MsiFile" -ForegroundColor Green
    Write-Host "Build logs are available in: $LogDir" -ForegroundColor Green
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Check the logs in $LogDir for more details" -ForegroundColor Yellow
    exit 1
} 