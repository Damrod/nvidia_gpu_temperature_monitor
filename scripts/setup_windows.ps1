# GPU Temperature Monitor - Windows Setup Script
#
# Purpose: Sets up the development environment and/or performs direct installation.
# This script is used for:
# - Setting up a development environment
# - Direct installation without using the MSI installer
# - Testing and debugging the application
#
# What this script does:
# 1. Configures development tools (WiX Toolset, PyInstaller)
# 2. Installs mock nvidia-smi for systems without NVIDIA GPUs
# 3. Creates and configures the Windows service
# 4. Sets up the runtime environment
#
# Usage:
# 1. Run PowerShell as Administrator
# 2. Run: .\scripts\setup_windows.ps1
#
# Requirements:
# - Administrative privileges
# - Python installed and in PATH
# - WiX Toolset v3.14 installed (will be added to PATH if needed)

# Requires -RunAsAdministrator

# Configuration
$ErrorActionPreference = "Stop"
$ServiceName = "GPUTempMonitor"
$InstallDir = "C:\Program Files\GPU Temperature Monitor"
$VenvDir = Join-Path $InstallDir ".venv"
$MockNvidiaSmiPath = "C:\Windows\System32\nvidia-smi.exe"
$WixPath = "C:\Program Files (x86)\WiX Toolset v3.14\bin"

function Test-NvidiaSmi {
    try {
        $output = & nvidia-smi --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Found existing nvidia-smi installation"
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

function Install-MockNvidiaSmi {
    Write-Host "Creating mock nvidia-smi..."
    
    # Clean previous build artifacts
    Remove-Item -Path "build", "dist" -Recurse -Force -ErrorAction SilentlyContinue
    
    # Build mock nvidia-smi
    python -m PyInstaller --onefile .\src\mock\nvidia_smi.py --name nvidia-smi
    if (-not $?) {
        throw "Failed to build mock nvidia-smi"
    }
    
    # Backup existing nvidia-smi if it exists
    if (Test-Path $MockNvidiaSmiPath) {
        $backupPath = "$MockNvidiaSmiPath.backup"
        Write-Host "Backing up existing nvidia-smi to $backupPath"
        Move-Item -Path $MockNvidiaSmiPath -Destination $backupPath -Force
    }
    
    # Install mock nvidia-smi
    Copy-Item -Path ".\dist\nvidia-smi.exe" -Destination $MockNvidiaSmiPath -Force
    Write-Host "Mock nvidia-smi installed successfully"
    
    # Test the installation
    $temp = & nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Mock nvidia-smi test successful. Current temperature: $temp°C"
    } else {
        throw "Mock nvidia-smi test failed"
    }
}

function Install-Service {
    Write-Host "Installing GPU Temperature Monitor service..."
    
    # Create installation directory
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    
    # Create and activate virtual environment
    python -m venv $VenvDir
    & "$VenvDir\Scripts\Activate.ps1"
    
    # Install dependencies
    python -m pip install --upgrade pip
    pip install -r requirements.txt
    
    # Copy necessary files
    Copy-Item -Path "src\gpu_monitor.py" -Destination $InstallDir -Force
    Copy-Item -Path "requirements.txt" -Destination $InstallDir -Force
    
    # Copy .env if it exists, otherwise create from example
    if (Test-Path ".env") {
        Copy-Item -Path ".env" -Destination $InstallDir -Force
    } elseif (Test-Path ".env.example") {
        Copy-Item -Path ".env.example" -Destination "$InstallDir\.env" -Force
    } else {
        throw "Neither .env nor .env.example found"
    }
    
    # Create Windows service
    $servicePath = "$VenvDir\Scripts\pythonw.exe"
    $serviceArgs = """$InstallDir\gpu_monitor.py"""
    
    # Remove existing service if it exists
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Write-Host "Removing existing service..."
        Stop-Service -Name $ServiceName -Force
        $service = Get-WmiObject -Class Win32_Service -Filter "name='$ServiceName'"
        $service.delete()
    }
    
    # Create new service
    Write-Host "Creating new service..."
    New-Service -Name $ServiceName `
                -DisplayName "GPU Temperature Monitor" `
                -Description "Monitors GPU temperature and prevents overheating" `
                -BinaryPathName "$servicePath $serviceArgs" `
                -StartupType Automatic
    
    Write-Host "Service installed successfully"
}

function Setup-WixTools {
    Write-Host "Configuring WiX Toolset PATH..."

    # Check if WiX directory exists
    if (-not (Test-Path $WixPath)) {
        Write-Warning "WiX installation not found at $WixPath"
        Write-Host "Please install WiX Toolset v3.14 before running this script."
        return $false
    }

    # Get the current system PATH
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")

    # Check if WiX is already in PATH
    if ($currentPath -like "*$WixPath*") {
        Write-Host "WiX is already in the system PATH."
        return $true
    }

    # Add WiX to PATH
    $newPath = $currentPath + ";" + $WixPath
    [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")

    # Update current session's PATH
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine")

    # Verify the addition
    $verifyPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($verifyPath -like "*$WixPath*") {
        Write-Host "WiX has been successfully added to the system PATH."
        
        # Test if WiX tools are accessible
        $candleTest = Get-Command candle.exe -ErrorAction SilentlyContinue
        if ($candleTest) {
            Write-Host "Successfully verified WiX tools are accessible!"
        } else {
            Write-Warning "WiX was added to PATH but tools are not immediately accessible. You may need to restart your terminal."
        }
        return $true
    } else {
        Write-Error "Failed to add WiX to the system PATH."
        return $false
    }
}

# Main installation process
try {
    # Check if running as administrator
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run as Administrator"
    }
    
    # Check Python installation
    python --version
    if (-not $?) {
        throw "Python is not installed or not in PATH"
    }
    
    # Install PyInstaller if needed
    pip show pyinstaller > $null 2>&1
    if (-not $?) {
        Write-Host "Installing PyInstaller..."
        pip install pyinstaller
    }
    
    # Setup WiX tools
    if (-not (Setup-WixTools)) {
        Write-Warning "WiX tools setup failed. Installation will continue but installer creation may not work."
    }
    
    # Check and install mock nvidia-smi if needed
    if (-not (Test-NvidiaSmi)) {
        Write-Host "nvidia-smi not found, installing mock version..."
        Install-MockNvidiaSmi
    }
    
    # Install and start the service
    Install-Service
    Start-Service -Name $ServiceName
    Write-Host "Service started successfully"
    
    Write-Host "`nInstallation completed successfully!"
    Write-Host "The GPU Temperature Monitor service is now running"
    Write-Host "You can manage it using the following commands:"
    Write-Host "  - Stop-Service -Name $ServiceName"
    Write-Host "  - Start-Service -Name $ServiceName"
    Write-Host "  - Get-Service -Name $ServiceName"
    
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
} 