$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Log {
    param([string]$Message)
    & "$scriptPath\logging.ps1" $Message
}

try {
    # Get the arguments
    if ($args.Count -lt 2) {
        throw "Not enough arguments. Expected: <python_path> <venv_path>"
    }
    
    $pythonPath = $args[0].Trim('"')  # Remove any quotes
    $venvPath = $args[1].Trim('"')    # Remove any quotes
    
    Write-Log "Starting virtual environment creation"
    Write-Log "Python Path: $pythonPath"
    Write-Log "Venv Path: $venvPath"
    
    # Ensure Python exists
    if (-not (Test-Path $pythonPath)) {
        throw "Python executable not found at: $pythonPath"
    }
    
    # Create the parent directory if it doesn't exist
    $venvParentDir = Split-Path -Parent $venvPath
    if (-not (Test-Path $venvParentDir)) {
        Write-Log "Creating directory: $venvParentDir"
        New-Item -ItemType Directory -Path $venvParentDir -Force | Out-Null
    }
    
    # Create the virtual environment
    Write-Log "Running: & '$pythonPath' -m venv '$venvPath'"
    & $pythonPath -m venv $venvPath
    if ($LASTEXITCODE -ne 0) {
        throw "Python venv creation failed with exit code: $LASTEXITCODE"
    }
    
    # Verify the venv was created
    $pythonExePath = Join-Path $venvPath "Scripts\python.exe"
    if (-not (Test-Path $pythonExePath)) {
        throw "Virtual environment appears to be missing python.exe at: $pythonExePath"
    }
    
    Write-Log "Virtual environment created successfully at: $venvPath"
}
catch {
    Write-Log "ERROR: Failed to create virtual environment: $_"
    exit 1
} 