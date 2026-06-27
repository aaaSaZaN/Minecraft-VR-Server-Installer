@echo off
chcp 65001 > nul

:: If setup.ps1 is missing, download it from github
:: Using PowerShell WebClient so the file is saved with UTF-8 BOM (required for PS 5.1)
if not exist "%~dp0setup.ps1" (
    echo Downloading installer...
    powershell -NoProfile -Command "$url='https://raw.githubusercontent.com/aaaSaZaN/Minecraft-VR-Server-Installer/master/setup.ps1'; $out='%~dp0setup.ps1'; $c=(New-Object System.Net.WebClient).DownloadString($url); [System.IO.File]::WriteAllText($out, $c, [System.Text.Encoding]::UTF8)"
)

:: Run setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
pause
