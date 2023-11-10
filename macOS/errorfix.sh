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

echo "Making the binary executable."
chmod +x "/Applications/Snap Camera.app/Contents/MacOS/Snap Camera"

echo "Removing the macOS code signing."
sudo codesign --remove-signature "/Applications/Snap Camera.app"

echo "Removing extended file attributes."
sudo xattr -cr "/Applications/Snap Camera.app"

echo "Re-Signing the application."
sudo codesign --force --deep --sign - "/Applications/Snap Camera.app"

echo "You should be able to open Snap Camera now."
