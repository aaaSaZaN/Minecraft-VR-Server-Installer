@echo off
chcp 65001 > nul

:: If setup.ps1 is missing, download it from github
if not exist "%~dp0setup.ps1" (
    echo Скачивание скрипта установки...
    curl -sSL -o "%~dp0setup.ps1" https://raw.githubusercontent.com/aaaSaZaN/Minecraft-VR-Server-Installer/master/setup.ps1
)

:: Run setup.ps1 in PowerShell bypass mode
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
pause
