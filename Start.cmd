@echo off
set "FEZFIX_START=%~f0"

rem 管理者権限でなければ、UACを表示してStart.cmdを管理者として起動し直します。
powershell.exe -NoProfile -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if errorlevel 1 (
    powershell.exe -NoProfile -Command "Start-Process -FilePath $env:FEZFIX_START -Verb RunAs"
    exit /b
)

rem 管理者権限でFEZClipboardFix本体を起動します。
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FEZClipboardFix.ps1"
