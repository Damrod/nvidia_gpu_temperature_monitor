# Get the message from arguments
$Message = $args[0]

try {
    # Ensure we have a message to log
    if (-not $Message) {
        throw "No message provided to log"
    }

    # Set up log file path
    $logPath = "C:\Windows\Temp\gpu_monitor_install.log"
    
    # Create timestamp and log message
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    
    # Write to log file
    Add-Content -Path $logPath -Value $logMessage -Force
    Write-Host "Log written successfully: $logMessage" -ForegroundColor Green
}
catch {
    $errorMsg = "Failed to write log: $_"
    Write-Host $errorMsg -ForegroundColor Red
    
    # Try one more time with Out-File as fallback
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$timestamp - ERROR: $Message (Error: $_)" | Out-File -FilePath $logPath -Append -Force
        Write-Host "Wrote to log using fallback method" -ForegroundColor Yellow
    }
    catch {
        Write-Host "Failed to write log even with fallback method: $_" -ForegroundColor Red
    }
}
finally {
    Write-Host "`nKeeping window open for 15 seconds..." -ForegroundColor Cyan
    Start-Sleep -Seconds 0
} 