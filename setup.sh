#!/bin/bash
# Check if python3 is installed
if ! command -v python3 &> /dev/null
then
    echo "Python 3 is not installed. Please install Python 3 before running the installer."
    exit 1
fi

# If mc_vr_installer.py is missing, download it from github
if [ ! -f "$(dirname "$0")/mc_vr_installer.py" ]; then
    echo "Downloading installer script from GitHub..."
    curl -sSL -o "$(dirname "$0")/mc_vr_installer.py" https://raw.githubusercontent.com/aaaSaZaN/Minecraft-VR-Server-Installer/master/mc_vr_installer.py
fi

# Run the installer
python3 "$(dirname "$0")/mc_vr_installer.py"
