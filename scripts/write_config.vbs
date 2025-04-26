Function WriteConfiguration
    ' Get the session parameters
    configPath = Session.Property("CONFIG_PATH")
    gotifyServer = Session.Property("GOTIFY_SERVER")
    gotifyToken = Session.Property("GOTIFY_TOKEN")
    highTemp = Session.Property("HIGH_TEMP")
    criticalTemp = Session.Property("CRITICAL_TEMP")
    checkInterval = Session.Property("CHECK_INTERVAL")
    shutdownDelay = Session.Property("SHUTDOWN_DELAY")

    ' Create the configuration file
    Set fso = CreateObject("Scripting.FileSystemObject")
    Set configFile = fso.CreateTextFile(configPath, True)

    ' Write the configuration
    configFile.WriteLine "[Gotify]"
    configFile.WriteLine "ServerURL = " & gotifyServer
    configFile.WriteLine "Token = " & gotifyToken
    configFile.WriteLine ""
    configFile.WriteLine "[Temperature]"
    configFile.WriteLine "HighThreshold = " & highTemp
    configFile.WriteLine "CriticalThreshold = " & criticalTemp
    configFile.WriteLine ""
    configFile.WriteLine "[Monitoring]"
    configFile.WriteLine "CheckIntervalSeconds = " & checkInterval
    configFile.WriteLine "EmergencyShutdownDurationSeconds = " & shutdownDelay

    configFile.Close
End Function 