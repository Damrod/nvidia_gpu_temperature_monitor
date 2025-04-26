; GPU Temperature Monitor Windows Installer
; Bundles everything into a single executable

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

; General
Name "GPU Temperature Monitor"
OutFile "gpu-temp-monitor-setup.exe"
InstallDir "$PROGRAMFILES64\GPU Temperature Monitor"
RequestExecutionLevel admin

; Interface Settings
!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_RIGHT
!define MUI_HEADERIMAGE_BITMAP "${NSISDIR}\Contrib\Graphics\Header\win.bmp"
!define MUI_WELCOMEFINISHPAGE_BITMAP "${NSISDIR}\Contrib\Graphics\Wizard\win.bmp"

; Pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

; Languages
!insertmacro MUI_LANGUAGE "English"

; Variables
Var PythonPath
Var PythonExe
Var NvidiaSmiExists

; Functions
Function .onInit
    ${If} ${RunningX64}
        SetRegView 64
    ${EndIf}
    
    ; Check for admin rights
    UserInfo::GetAccountType
    Pop $0
    ${If} $0 != "admin"
        MessageBox MB_ICONSTOP "Administrator rights required!"
        Abort
    ${EndIf}
    
    ; Check for Python 3.x
    EnumRegKey $0 HKLM "SOFTWARE\Python\PythonCore" 0
    ${If} $0 == ""
        MessageBox MB_YESNO|MB_ICONQUESTION "Python is not installed. Would you like to download and install Python 3.12?" IDYES download IDNO abort
        abort:
            Abort
        download:
            ExecShell "open" "https://www.python.org/downloads/"
            Abort
    ${EndIf}
    
    ; Get Python installation path
    ReadRegStr $PythonPath HKLM "SOFTWARE\Python\PythonCore\$0\InstallPath" ""
    ${If} $PythonPath == ""
        MessageBox MB_OK|MB_ICONEXCLAMATION "Python installation found but unable to locate path. Please repair Python installation."
        Abort
    ${EndIf}
    StrCpy $PythonExe "$PythonPath\python.exe"
    
    ; Check if nvidia-smi exists
    ${If} ${FileExists} "C:\Windows\System32\nvidia-smi.exe"
        StrCpy $NvidiaSmiExists "1"
    ${Else}
        StrCpy $NvidiaSmiExists "0"
    ${EndIf}
FunctionEnd

Section "MainSection" SEC01
    SetOutPath "$INSTDIR"
    SetOverwrite on
    
    ; Create virtual environment
    DetailPrint "Creating virtual environment..."
    nsExec::ExecToLog '"$PythonExe" -m venv "$INSTDIR\.venv"'
    
    ; Install dependencies
    DetailPrint "Installing dependencies..."
    nsExec::ExecToLog '"$INSTDIR\.venv\Scripts\python.exe" -m pip install --upgrade pip'
    File "requirements.txt"
    nsExec::ExecToLog '"$INSTDIR\.venv\Scripts\pip.exe" install -r "$INSTDIR\requirements.txt"'
    
    ; Copy main program files
    File /r "..\src\*.*"
    File "..\requirements.txt"
    File ".env.example"
    ${If} ${FileExists} ".env"
        File ".env"
    ${Else}
        CopyFiles ".env.example" ".env"
    ${EndIf}
    
    ; Install mock nvidia-smi if needed
    ${If} $NvidiaSmiExists == "0"
        DetailPrint "Installing mock nvidia-smi..."
        File "..\dist\nvidia-smi.exe"
        CopyFiles "$INSTDIR\nvidia-smi.exe" "C:\Windows\System32\nvidia-smi.exe"
    ${EndIf}
    
    ; Create and start Windows service
    DetailPrint "Installing Windows service..."
    nsExec::ExecToLog '"$INSTDIR\.venv\Scripts\python.exe" "$INSTDIR\gpu_monitor.py" --install'
    
    ; Create uninstaller
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    
    ; Create start menu shortcuts
    CreateDirectory "$SMPROGRAMS\GPU Temperature Monitor"
    CreateShortCut "$SMPROGRAMS\GPU Temperature Monitor\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
    
    ; Write registry entries for uninstaller
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\GPUTempMonitor" \
                     "DisplayName" "GPU Temperature Monitor"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\GPUTempMonitor" \
                     "UninstallString" "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Uninstall"
    ; Stop and remove service
    nsExec::ExecToLog '"$INSTDIR\.venv\Scripts\python.exe" "$INSTDIR\gpu_monitor.py" --uninstall'
    
    ; Remove mock nvidia-smi if we installed it
    ${If} ${FileExists} "C:\Windows\System32\nvidia-smi.exe.backup"
        Delete "C:\Windows\System32\nvidia-smi.exe"
        Rename "C:\Windows\System32\nvidia-smi.exe.backup" "C:\Windows\System32\nvidia-smi.exe"
    ${EndIf}
    
    ; Remove program files
    RMDir /r "$INSTDIR"
    RMDir /r "$SMPROGRAMS\GPU Temperature Monitor"
    
    ; Remove registry entries
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\GPUTempMonitor"
SectionEnd 