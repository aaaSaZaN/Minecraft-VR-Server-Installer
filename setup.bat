@echo off
:: Check if python is installed
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Python is not installed or not in PATH. Please install Python before running this installer.
    pause
    exit /b 1
)

:: If mc_vr_installer.py is missing, download it from github
if not exist "%~dp0mc_vr_installer.py" (
    echo Downloading installer script from GitHub...
    curl -sSL -o "%~dp0mc_vr_installer.py" https://raw.githubusercontent.com/aaaSaZaN/Minecraft-VR-Server-Installer/master/mc_vr_installer.py
)

:: Run the installer
python "%~dp0mc_vr_installer.py"
pause
