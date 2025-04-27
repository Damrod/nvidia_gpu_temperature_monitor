Function WriteConfiguration
    ' Get the session parameters
    configPath = Session.Property("CONFIG_PATH")
    gotifyToken = Session.Property("GOTIFY_TOKEN")
    gotifyServerUrl = Session.Property("GOTIFY_SERVER_URL")
    highTempThreshold = Session.Property("HIGH_TEMPERATURE_THRESHOLD")
    criticalTempThreshold = Session.Property("CRITICAL_TEMPERATURE_THRESHOLD")
    checkIntervalSeconds = Session.Property("CHECK_INTERVAL_SECONDS")
    emergencyShutdownSeconds = Session.Property("EMERGENCY_SHUTDOWN_DURATION_SECONDS")
    
    ' Create the configuration file
    Set fso = CreateObject("Scripting.FileSystemObject")
    Set configFile = fso.CreateTextFile(configPath, True)

    ' Write the configuration
    configFile.WriteLine "[Settings]"
    configFile.WriteLine "GOTIFY_TOKEN=" & gotifyToken
    configFile.WriteLine "GOTIFY_SERVER_URL=" & gotifyServerUrl
    configFile.WriteLine "HIGH_TEMPERATURE_THRESHOLD=" & highTempThreshold
    configFile.WriteLine "CRITICAL_TEMPERATURE_THRESHOLD=" & criticalTempThreshold
    configFile.WriteLine "CHECK_INTERVAL_SECONDS=" & checkIntervalSeconds
    configFile.WriteLine "EMERGENCY_SHUTDOWN_DURATION_SECONDS=" & emergencyShutdownSeconds

    configFile.Close
End Function 