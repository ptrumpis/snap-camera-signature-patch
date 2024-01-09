#!/bin/bash

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

echo "Generating MD5 checksum of the Snap Camera binary file"

md5_result=$(md5sum "/Applications/Snap Camera.app/Contents/MacOS/Snap Camera" | awk '{print $1}')

declare -A md5_messages=(
    ["8dc456e29478a0cdfaedefac282958e7"]="Original binary with original code signing."
    ["15ad19c477d5d246358d68a711e29a6e"]="Original binary no code signing."
    ["1ac420d1828a3d754e99793af098f830"]="Patched binary with original code signing."
    ["e2ed1f2e502617392060270fa6e5e979"]="Patched binary no code signing."
)

if [[ -n ${md5_messages[$md5_result]} ]]; then
    echo "MD5 checksum result: ${md5_messages[$md5_result]}"
else
    echo "Error: unknown MD5 checksum, please reinstall Snap Camera application and try again."
    exit 1
fi

echo "Making the binary executable."
chmod +x "/Applications/Snap Camera.app/Contents/MacOS/Snap Camera"

echo "Removing the macOS code signing."
sudo codesign --remove-signature "/Applications/Snap Camera.app"

echo "Removing extended file attributes."
sudo xattr -cr "/Applications/Snap Camera.app"

echo "Re-Signing the application."
sudo codesign --force --deep --sign - "/Applications/Snap Camera.app"

echo "You should be able to open Snap Camera now."
