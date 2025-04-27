$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Log {
    param([string]$Message)
    & "$scriptPath\logging.ps1" $Message
}

# Parse arguments
$configPath = $args[0]
$gotifyToken = $args[1]
$gotifyServerUrl = $args[2]
$highTemp = $args[3]
$criticalTemp = $args[4]
$checkInterval = $args[5]
$shutdownDelay = $args[6]

try {
    Write-Log "Writing configuration to: $configPath"
    
    # Create the config content
    $configContent = @"
[Gotify]
Token = $gotifyToken
ServerUrl = $gotifyServerUrl

[Temperature]
HighTemp = $highTemp
CriticalTemp = $criticalTemp
CheckInterval = $checkInterval
ShutdownDelay = $shutdownDelay
"@

    # Create directory if it doesn't exist
    $configDir = Split-Path -Parent $configPath
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Write the config file
    $configContent | Out-File -FilePath $configPath -Encoding UTF8 -Force
    Write-Log "Configuration file written successfully"
}
catch {
    Write-Log "ERROR: Failed to write configuration: $_"
    exit 1
} 