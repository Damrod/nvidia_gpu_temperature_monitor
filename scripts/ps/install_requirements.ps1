$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Log {
    param([string]$Message)
    & "$scriptPath\logging.ps1" $Message
}

# Parse arguments
$pythonPath = $args[0]
$requirementsPath = $args[1]

try {
    Write-Log "Installing requirements using Python: $pythonPath"
    Write-Log "Requirements file: $requirementsPath"
    
    # Install requirements
    & $pythonPath -m pip install -r $requirementsPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install requirements"
    }
    
    Write-Log "Requirements installed successfully"
}
catch {
    Write-Log "ERROR: Failed to install requirements: $_"
    exit 1
} 