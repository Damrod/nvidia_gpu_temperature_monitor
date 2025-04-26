; NVIDIA GPU Temperature Monitor Installer
; NSIS script for Windows installation

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

; General
Name "NVIDIA GPU Temperature Monitor"
OutFile "gpu-monitor-setup.exe"
InstallDir "$PROGRAMFILES64\NVIDIA GPU Monitor"
RequestExecutionLevel admin

; Interface Settings
!define MUI_ABORTWARNING

; Pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

; Language
!insertmacro MUI_LANGUAGE "English"

; Variables
Var PythonPath
Var VenvPath

; Functions
Function .onInit
    ; Check for Python installation
    ReadRegStr $PythonPath HKLM "SOFTWARE\Python\PythonCore\3.11\InstallPath" ""
    ${If} $PythonPath == ""
        MessageBox MB_OK|MB_ICONEXCLAMATION "Python 3.11 not found. Please install Python 3.11 first."
        Abort
    ${EndIf}
FunctionEnd

Section "Install"
    SetOutPath "$INSTDIR"
    
    ; Copy files
    File /r "srcs\*.*"
    File ".env.example"
    
    ; Create virtual environment
    ExecWait '"$PythonPath\python.exe" -m venv "$INSTDIR\.venv"'
    
    ; Install dependencies
    ExecWait '"$INSTDIR\.venv\Scripts\pip.exe" install -r "$INSTDIR\requirements.txt"'
    
    ; Create Windows service
    ExecWait '"$INSTDIR\.venv\Scripts\python.exe" "$INSTDIR\gpu_monitor.py" --install'
    
    ; Write installation info
    WriteRegStr HKLM "Software\NVIDIA GPU Monitor" "InstallDir" "$INSTDIR"
    WriteRegStr HKLM "Software\NVIDIA GPU Monitor" "Version" "1.0.0"
    
    ; Create uninstaller
    WriteUninstaller "$INSTDIR\uninstall.exe"
    
    ; Create shortcuts
    CreateDirectory "$SMPROGRAMS\NVIDIA GPU Monitor"
    CreateShortCut "$SMPROGRAMS\NVIDIA GPU Monitor\Uninstall.lnk" "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
    ; Stop and remove service
    ExecWait '"$INSTDIR\.venv\Scripts\python.exe" "$INSTDIR\gpu_monitor.py" --uninstall'
    
    ; Remove files
    RMDir /r "$INSTDIR"
    
    ; Remove shortcuts
    RMDir /r "$SMPROGRAMS\NVIDIA GPU Monitor"
    
    ; Remove registry entries
    DeleteRegKey HKLM "Software\NVIDIA GPU Monitor"
SectionEnd 