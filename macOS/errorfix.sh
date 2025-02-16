#!/bin/bash
echo "---------------------------------------"
echo "macOS errorfix v1.5 with ($SHELL)"
[ -n "$BASH_VERSION" ] && echo "bash version $BASH_VERSION"
[ -n "$ZSH_VERSION" ] && echo "zsh version $ZSH_VERSION"
OS_version=$(sw_vers | awk '/ProductVersion/ {print $2}') || OS_version="(Unknown)"
architecture=$(uname -m)
echo "OS Version: $OS_version"
echo "Architecture: $architecture"
echo "---------------------------------------"

if pgrep -x "Snap Camera" > /dev/null; then
    echo "Snap Camera is running. Terminating application."
    pkill -x "Snap Camera"
fi

if [ ! -d "/Applications/Snap Camera.app" ]; then
    echo "Error: Snap Camera.app directory does not exist."
    exit 1
fi

if [ ! -f "/Applications/Snap Camera.app/Contents/MacOS/Snap Camera" ]; then
    echo "Error: Snap Camera binary does not exist."
    exit 1
fi

ip_to_check="127.0.0.1"
hostname_to_check="studio-app.snapchat.com"

if grep -q "^$ip_to_check\s\+$hostname_to_check" /etc/hosts; then
    echo "/etc/hosts entrry $ip_to_check $hostname_to_check exists."
else
    echo "Error: /etc/hosts entrry $ip_to_check $hostname_to_check does not exist."
    exit 1
fi

if ping -c 1 -W 2 "$hostname_to_check" > /dev/null 2>&1; then
    echo "Ping to host $hostname_to_check succesful."
else
    echo "Ping to host $hostname_to_check failed."
fi

if command -v curl > /dev/null; then
    server_url="https://studio-app.snapchat.com"

    server_response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$server_url" 2>&1)
    if [[ "$server_response" =~ ^[0-9]{3}$ ]]; then
        if [[ "$server_response" != "200" ]]; then
            echo "Error: The server $server_url responded with status: $server_response"
            exit 1
        else
            echo "The server $server_url is reachable."
        fi
    else
        echo "Error: The server $server_url cannot be reached:"
        echo "$server_response"
        exit 1
    fi
else
    echo "Error: The 'curl' command is not available. Please check in your browser that the URL $server_url is accessible."
fi

echo "Generating MD5 checksum of the Snap Camera binary file."

if command -v md5sum > /dev/null; then
    md5_result=$(md5sum "/Applications/Snap Camera.app/Contents/MacOS/Snap Camera" | awk '{print $1}')
else
    md5_result=$(md5 -q "/Applications/Snap Camera.app/Contents/MacOS/Snap Camera")
fi

if [ "$md5_result" = "8dc456e29478a0cdfaedefac282958e7" ]; then
    echo "MD5 checksum result: Original binary with original code signing."
elif [ "$md5_result" = "15ad19c477d5d246358d68a711e29a6e" ]; then
    echo "MD5 checksum result: Original binary no code signing."
elif [ "$md5_result" = "1ac420d1828a3d754e99793af098f830" ]; then
    echo "MD5 checksum result: Patched binary with original code signing."
elif [ "$md5_result" = "e2ed1f2e502617392060270fa6e5e979" ]; then
    echo "MD5 checksum result: Patched binary no code signing."
else
    echo "Unknown MD5 checksum '$md5_result'."
fi

echo "Making the binary executable."
chmod +x "/Applications/Snap Camera.app/Contents/MacOS/Snap Camera"

echo "Removing the macOS code signing."
sudo codesign --remove-signature "/Applications/Snap Camera.app"

echo "Removing extended file attributes."
sudo xattr -cr "/Applications/Snap Camera.app"

echo "Re-signing the application."
sudo codesign --force --deep --sign - "/Applications/Snap Camera.app"

echo "Generating new MD5 checksum."
if command -v md5sum > /dev/null; then
    md5_new=$(md5sum "/Applications/Snap Camera.app/Contents/MacOS/Snap Camera" | awk '{print $1}')
else
    md5_new=$(md5 -q "/Applications/Snap Camera.app/Contents/MacOS/Snap Camera")
fi
echo "New MD5 checksum: '$md5_new'."

echo "Checking I/O registry for DAL entries."
ioreg -l | grep -i "DAL"

if [ "$architecture" == "arm64" ]; then
    echo "Running on ARM architecture. Starting Snap Camera application with Rosetta..."
    arch -x86_64 "/Applications/Snap Camera.app/Contents/MacOS/Snap Camera"
else
    echo "You should be able to open Snap Camera now."
fi

echo "If you continue to have problems, please re-download and re-install Snap Camera from:"
echo "https://bit.ly/snpcm"
