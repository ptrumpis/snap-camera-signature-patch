#!/bin/bash
echo "macOS errorfix v1.2 with ($SHELL | v$BASH_VERSION)"

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

server_url="https://studio-app.snapchat.com"

if command -v curl > /dev/null; then
    if curl --output /dev/null --silent --head --fail "$server_url"; then
        echo "The server $server_url is reachable."
    else
        echo "Error: The server $server_url cannot be reached."
    fi
else
    echo "Error: The 'curl' command is not available. Please check in your browser that the URL $server_url is accessible."
fi

echo "Generating MD5 checksum of the Snap Camera binary file"

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
    echo "Error: unknown MD5 checksum '$md5_result', please reinstall Snap Camera application and try again."
    exit 1
fi

echo "Making the binary executable."
chmod +x "/Applications/Snap Camera.app/Contents/MacOS/Snap Camera"

echo "Removing the macOS code signing."
sudo codesign --remove-signature "/Applications/Snap Camera.app"
sudo codesign --remove-signature "/Applications/Snap Camera.app/Contents/MacOS/Snap Camera"

echo "Removing extended file attributes."
sudo xattr -cr "/Applications/Snap Camera.app"

echo "Re-Signing the application."
sudo codesign --force --deep --sign - "/Applications/Snap Camera.app"

echo "You should be able to open Snap Camera now."
