#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "🔑 This script requires administrator rights. Please enter your password:"
    exec sudo "$0" "$@"
    exit 1
fi

echo "......................................."
echo "macOS errorfix v1.6.0 with ($SHELL)"
[ -n "$BASH_VERSION" ] && echo "bash version $BASH_VERSION"
[ -n "$ZSH_VERSION" ] && echo "zsh version $ZSH_VERSION"
OS_version=$(sw_vers | awk '/ProductVersion/ {print $2}') || OS_version="(Unknown)"
architecture=$(uname -m)
echo "OS Version: $OS_version"
echo "Architecture: $architecture"
echo "......................................."

server_ip="127.0.0.1"
hostname="studio-app.snapchat.com"
server_url="https://$hostname"
app_path="/Applications/Snap Camera.app"
binary_path="$app_path/Contents/MacOS"
binary_file="$binary_path/Snap Camera"
cert_file="$hostname.crt"

if pgrep -x "Snap Camera" > /dev/null; then
    echo "⚠️ Snap Camera is running. Terminating application."
    pkill -x "Snap Camera"
fi

if [ ! -d "$app_path" ]; then
    echo "❌ Error: Snap Camera.app directory does not exist."
    echo "🌐 Please download and install from: https://bit.ly/snpcm"
    exit 1
fi

if [ ! -f "$binary_file" ]; then
    echo "❌ Error: Snap Camera binary does not exist."
    echo "🌐 Please re-download and install from: https://bit.ly/snpcm"
    exit 1
fi

function to_posix_path() {
    local path="$1"
    local resolved_path=""
    if command -v greadlink >/dev/null 2>&1; then
        resolved_path=$(greadlink -f "$path")
    elif command -v perl >/dev/null 2>&1; then
        resolved_path=$(perl -MCwd=realpath -e 'print realpath($ARGV[0])' "$path")
    elif [[ -d "$path" ]]; then
        resolved_path=$(cd "$path" && pwd -P)
    elif [[ -f "$path" ]]; then
        resolved_path="$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"
    fi
    echo "${resolved_path%/}"
}

function verify_directory() {
    local dir
    dir=$(to_posix_path "$1")
    if [[ -d "$dir" && -f "$dir/server.js" && -d "$dir/ssl" ]]; then
        return 0
    else
        return 1
    fi
}

function is_container_running() {
    local container_id
    container_id=$(docker ps -q --filter "name=snap" --filter "name=webapp" | head -n 1)
    if [[ -n "$container_id" ]]; then
        local running
        running=$(docker inspect --format '{{.State.Running}}' "$container_id" 2>/dev/null)
        [[ "$running" == "true" ]] && return 0
    fi
    return 1
}

echo "🔍 Trying to detect Docker webapp container."
container_id=$(docker ps -q -a --filter "name=snap" --filter "name=webapp" | head -n 1)
if [[ -n "$container_id" ]]; then
    running=$(docker inspect --format '{{.State.Running}}' "$container_id")
    if [[ "$running" == "true" ]]; then
        echo "✅ Snap Camera Server is running: $container_id"
    else
        echo "⚠️ Snap Camera Server is not runnning: $container_id"
    fi
else
    echo "⚠️ Unable to auto-detect Snap Camera Server on your system. Please make sure Snap Camera Server is set up and running."
    echo "🌐 Download URL: https://github.com/ptrumpis/snap-camera-server/releases/latest"
fi

echo "🔍 Trying to determine server directory."
project_dir=$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$container_id" 2>/dev/null)
if [[ -n "$project_dir" ]]; then
    echo "📁 Found: '$project_dir'."
    project_dir=$(to_posix_path "$project_dir")
fi

if [[ -z "$project_dir" || ! -d "$project_dir" || ! $(verify_directory "$project_dir") ]]; then
    echo "⚠️ The server directory could not be determined automatically."
    while true; do
        user_input=$(osascript -e 'tell app "Finder" to set folderPath to POSIX path of (choose folder with prompt "Please select the Snap Camera Server directory:")' 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            echo "❌ User canceled directory selection."
            exit 1
        fi
        user_input=$(echo "$user_input" | sed 's/^ *//g' | sed 's/ *$//g')
        if verify_directory "$user_input"; then
            project_dir="${user_input%/}"
            break
        else
            echo "⚠️ Invalid directory: '$user_input'!"
        fi
    done
fi
echo "✅ Snap Camera Server directory: $project_dir"

echo "🔍 Checking if an .env file exists."
envPath="$project_dir/.env"
exampleEnvPath="$project_dir/example.env"
if [[ ! -f "$envPath" ]]; then
    echo "⚠️ An .env file was not found."
    if [[ -f "$exampleEnvPath" ]]; then
        cp "$exampleEnvPath" "$envPath"
        echo "✅ An .env file was created from example.env."
    else
        echo "❌ Error: Neither .env nor example.env found."
        exit 1
    fi
else
    echo "✅ An .env file exists."
fi

echo "🔍 Checking if a '/etc/hosts' entry exists."
if grep -E -q "^$server_ip[[:space:]]+$hostname" /etc/hosts; then
    echo "✅ '/etc/hosts' entry $server_ip $hostname exists."
else
    echo "⚠️ '/etc/hosts' entry $server_ip $hostname does not exist."
    echo "$server_ip $hostname" | sudo tee -a /etc/hosts
    if grep -E -q "^$server_ip[[:space:]]+$hostname" /etc/hosts; then
        echo "✅ '/etc/hosts' entry $server_ip $hostname was created."
    else
        echo "❌ Error: Failed to create '/etc/hosts' entry."
        exit 1
    fi
fi

echo "🔍 Checking if an SSL certificate is present."
certPath="$project_dir/ssl/$cert_file"
genCertScript="$project_dir/gencert.sh"
if [[ ! -f "$certPath" ]]; then
    echo "⚠️ SSL certificate is missing."
    chmod +x "$genCertScript"
    if [[ -x "$genCertScript" ]]; then
        echo "🔄 Generating new SSL certificate..."
        (cd "$project_dir" && ./gencert.sh)
    else
        echo "❌ Error: SSL certificate missing and gencert.sh is not executable or does not exist."
        exit 1
    fi
else
    echo "✅ SSL certificate found."
fi

echo "🛠️ Fixing possible SSL access right issues."
sudo chown -R $(id -un):$(id -gn) "$project_dir/ssl/*"

echo "🛠️ Fixing possible SSL trust issues..."
cert_path="$project_dir/ssl/studio-app.snapchat.com.crt"
cert_hash=$(openssl x509 -in "$cert_path" -noout -fingerprint -sha1 | sed 's/^.*=//')
if [[ -z "$cert_hash" ]]; then
    echo "❌ Error: Failed to read certificate fingerprint! Please check the certificate file."
    exit 1
else
    sudo security delete-certificate -c "$hostname" ~/Library/Keychains/login.keychain-db 2>/dev/null && echo "🗑️ Removed old '$hostname' certificate from Login Keychain."
    sudo security delete-certificate -Z "$cert_hash" ~/Library/Keychains/login.keychain-db 2>/dev/null && echo "🗑️ Removed old certificate from Login Keychain."
    sudo security delete-certificate -c "$hostname" /Library/Keychains/System.keychain 2>/dev/null && echo "🗑️ Removed old '$hostname' certificate from System Keychain."
    sudo security delete-certificate -Z "$cert_hash" /Library/Keychains/System.keychain 2>/dev/null && echo "🗑️ Removed old certificate from System Keychain."
fi
if sudo security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db "$cert_path"; then
    echo "✅ Imported and trusted certificate in Login Keychain."
else
    echo "❌ Error: Failed to mark certificate as trusted in Login Keychain!"
    exit 1
fi
if sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$cert_path"; then
    echo "✅ Imported and trusted certificate in System Keychain."
else
    # Login Keychain should be sufficient
    echo "⚠️ Warning: Failed to mark certificate as trusted in System Keychain!"
fi

if [ -f "$binary_path/Snap_Camera_real" ]; then
    echo "🧾 ARM Wrapper script detected."
    binary_file="$binary_path/Snap_Camera_real"
fi

echo "🔄 Generating MD5 checksum of the Snap Camera binary file."
if command -v md5sum > /dev/null; then
    md5_result=$(md5sum "$binary_file" | awk '{print $1}')
else
    md5_result=$(md5 -q "$binary_file")
fi

if [ "$md5_result" = "8dc456e29478a0cdfaedefac282958e7" ]; then
    echo "✅ MD5 checksum result: Original binary with original code signing."
elif [ "$md5_result" = "15ad19c477d5d246358d68a711e29a6e" ]; then
    echo "✅ MD5 checksum result: Original binary no code signing."
elif [ "$md5_result" = "1ac420d1828a3d754e99793af098f830" ]; then
    echo "✅ MD5 checksum result: Patched binary with original code signing."
elif [ "$md5_result" = "e2ed1f2e502617392060270fa6e5e979" ]; then
    echo "✅ MD5 checksum result: Patched binary no code signing."
else
    echo "⚠️ Unknown MD5 checksum '$md5_result'."
fi

echo "🛠️ Making the Snap Camera binary executable."
chmod +x "$binary_file"

echo "🛠️ Removing the macOS code signing."
if ! sudo codesign --remove-signature "$app_path"; then
    echo "⚠️ Directly removing signature from app bundle failed. Try recursively."
    if find "$app_path" -type f -perm +111 &>/dev/null; then
        perm_flag="+111"
    else
        perm_flag="/111"
    fi
    success=true
    while IFS= read -r file; do
        if ! sudo codesign --remove-signature "$file"; then
            echo "❌ Error: removing signature for file: $file"
            success=false
        fi
    done < <(find "$app_path" -type f -perm $perm_flag)
    if $success; then
        echo "✅ All signatures were successfully removed."
    else
        echo "❌ Error: At least one file could not be freed from the signature."
        exit 1
    fi
else
    echo "✅ Signature removal was successful."
fi

if [ "$architecture" == "arm64" ]; then
    echo "🔍 ARM architecture detected."
    if [ ! -f "$binary_path/Snap_Camera_real" ]; then
        echo "🛠️ Creating x86 wrapper script..."
        mv "$binary_path/Snap Camera" "$binary_path/Snap_Camera_real"
        echo '#!/bin/bash
        arch -x86_64 "'"$binary_path/Snap_Camera_real"'" "$@"' > "$binary_path/Snap Camera"
        chmod +x "$binary_path/Snap Camera"
        binary_file="$binary_path/Snap_Camera_real"
    fi
fi

echo "🛠️ Removing extended file attributes."
sudo xattr -cr "$app_path"

echo "🛠️ Re-signing the Snap Camera application."
if sudo codesign --force --deep --sign - "$app_path"; then
    echo "✅ Re-signing was successful."
else
    echo "❌ Error: Re-signing failed."
    exit 1
fi

echo "🔄 Re-Generating MD5 checksum of the Snap Camera binary file."
if command -v md5sum > /dev/null; then
    md5_new=$(md5sum "$binary_file" | awk '{print $1}')
else
    md5_new=$(md5 -q "$binary_file")
fi
echo "✅ New MD5 checksum: '$md5_new'."

echo "🛠️ Adding Snap Camera to Gatekeeper exceptions."
if sudo spctl --add "$app_path"; then
    echo "✅ Snap Camera successfully added to Gatekeeper exceptions."
else
    echo "⚠️ Failed to add Snap Camera to Gatekeeper exceptions!"
fi

plugin_dir="/Library/CoreMediaIO/Plug-Ins/DAL"
target_plugin="$plugin_dir/SnapCamera.plugin"
source_plugin="$binary_path/SnapCamera.plugin"
if [[ -d "$plugin_dir" && ! -e "$target_plugin" ]]; then
    echo "⚠️ SnapCamera.plugin is missing."
    if [[ -d "$source_plugin" ]]; then
        echo "🛠️ Re-installing Snap Camera Plugin."
        sudo cp -Rp "$source_plugin" "$plugin_dir"
        if [[ -d "$target_plugin" ]]; then
            sudo chown -R root:wheel "$target_plugin"
            sudo chmod -R 755 "$target_plugin"
            sudo xattr -dr com.apple.quarantine "$target_plugin"
            sudo spctl --add "$target_plugin"
            echo "✅ SnapCamera.plugin successfully installed."
        else
             echo "⚠️ Failed to re-install SnapCamera.plugin."
        fi
    else
        echo "⚠️ Source plugin not found at $source_plugin."
    fi
fi

echo "🔍 Checking pf-rules."
tmp_rules="/tmp/pf_rules.conf"
sudo pfctl -sr 2>/dev/null > "$tmp_rules"
if [ ! -s "$tmp_rules" ]; then
    echo "✅ No pf rules found. Skipping pf check."
else
    if grep -q "$hostname" "$tmp_rules"; then
        echo "⚠️ Host $hostname is blocked by pf. Unblocking..."
        grep -v "$hostname" "$tmp_rules" | sudo tee "$tmp_rules.filtered" > /dev/null
        sudo pfctl -f "$tmp_rules.filtered"
        sudo pfctl -e
        echo "✅ Host $hostname was unblocked."
    else
        echo "✅ Host $hostname is not blocked by pf."
    fi
fi

echo "🔍 Checking firewall status."
if [ -f "/Library/Preferences/com.apple.alf.plist" ]; then
    firewall_state=$(sudo defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null)
    case "$firewall_state" in
        0)
            echo "✅ Firewall is disabled. Skipping firewall checks."
            ;;
       1|2)
            echo "✅ Firewall is enabled. Checking if Snap Camera is blocked..."
            blocked_apps=$(sudo defaults read /Library/Preferences/com.apple.alf.plist | grep -A2 "$app_path" | grep -i "block")
            if [[ -n "$blocked_apps" ]]; then
                echo "⚠️ Snap Camera is blocked by firewall. Unblocking..."
                sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$app_path"
                echo "✅ Snap Camera was unblocked."
            else
                echo "✅ Snap Camera is not blocked by firewall."
            fi
            if [[ "$firewall_state" -eq 2 ]]; then
                echo "⚠️ Firewall is in strict mode. Ensuring that Snap Camera is allowed..."
                sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$app_path"
                sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$app_path"
                echo "✅ Snap Camera was explicitly allowed in the firewall."
            fi
            ;;
        *)
            echo "⚠️ Unknown firewall state: $firewall_state. Skipping firewall checks."
            ;;
    esac
else
    echo "⚠️ Firewall configuration file not found. Skipping firewall checks."
fi

if ! is_container_running; then
    echo "🚀 Starting the server with 'docker compose up'."
    (cd "$project_dir" && docker compose up -d)
    max_retries=10
    retries=0
    while [[ $retries -lt $max_retries ]]; do
        echo "⏳ Waiting for the server to start..."
        if is_container_running; then
            echo "✅ Snap Camera Server is now running."
            break
        fi
        ((retries++))
        sleep 5
    done
    if ! is_container_running; then
        echo "❌ Error: Snap Camera Server did not start within the expected time."
        exit 1
    fi
fi

echo "🔍 Sending ping to host $hostname."
if ping -c 1 -W 2000 "$hostname" > /dev/null 2>&1; then
    echo "✅ Ping to host $hostname succesful."
else
    echo "⚠️ Ping to host $hostname failed."
fi

echo "🔍 Sending request to host $server_url."
if command -v curl > /dev/null; then
    server_response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$server_url" 2>&1)
    if [[ "$server_response" == "000" ]]; then
        echo "❌ Error: The server $server_url cannot be reached. Checking details..."
        echo "🔍 Running: curl -v --connect-timeout 5 $server_url"
        curl -v --connect-timeout 5 "$server_url"
        echo "🔍 Running: curl -v --insecure --connect-timeout 5 $server_url"
        curl -v --insecure --connect-timeout 5 "$server_url"
        exit 1
    elif [[ "$server_response" =~ ^[0-9]{3}$ ]]; then
        if [[ "$server_response" != "200" ]]; then
            echo "❌ Error: The server $server_url responded with status: $server_response"
            exit 1
        else
            echo "✅ The server $server_url is reachable."
        fi
    else
        echo "❌ Error: The server $server_url cannot be reached:"
        echo "$server_response"
        exit 1
    fi
else
    echo "❌ Error: The 'curl' command is not available. Please check in your browser that the URL $server_url is accessible."
fi

echo "🔍 Checking System Integrity Protection (SIP) status."
sip_status=$(csrutil status | grep -o "enabled")
if [[ "$sip_status" == "enabled" ]]; then
    echo "⚠️ Warning: System Integrity Protection (SIP) is enabled. Some operations may be restricted!"
else
    echo "✅ System Integrity Protection (SIP) is disabled."
fi

echo "🔍 Checking virtual webcam installation."
system_profiler SPCameraDataType | grep -i -A 5 Snap

echo "🔄 Killing/Restarting camera related processes..."
sudo killall VDCAssistant AppleCameraAssistant 2>/dev/null
sudo launchctl kickstart -k system/com.apple.appleh13camerad 2>/dev/null

echo "🔍 Checking 'appleh13camerad' service."
if [ -f "/System/Library/LaunchDaemons/com.apple.appleh13camerad.plist" ]; then
    if sudo launchctl list | grep -q "com.apple.appleh13camerad"; then
        echo "✅ The service 'appleh13camerad' is running."
    else
        echo "⚠️ The service 'appleh13camerad' is not running."
        echo "🔄 Attempting to start the service..."
        sudo launchctl bootstrap system "/System/Library/LaunchDaemons/com.apple.appleh13camerad.plist"
        if sudo launchctl list | grep -q "com.apple.appleh13camerad"; then
            echo "✅ Service 'appleh13camerad' successfully started."
        else
            echo "⚠️ Failed to start the service."
        fi
    fi
fi

if [ "$architecture" == "arm64" ]; then
    echo "🚀 Starting Snap Camera application with Rosetta..."
    arch -x86_64 "$binary_file" & disown
else
    echo "🚀 Starting Snap Camera..."
    open "$app_path" & disown
fi

echo "🆗 If you continue to have problems, please re-download and re-install Snap Camera from:"
echo "🌐 https://bit.ly/snpcm"
