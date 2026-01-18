#!/bin/bash

# setup.sh: Interactive wizard for setting up SSH Minecraft Server with Podman Secrets

set -e

# 1. Detect prerequisites
if ! command -v podman &> /dev/null; then
    echo "Error: podman is not installed. Please install podman and try again."
    exit 1
fi

echo "Welcome to the SSH Minecraft Server Setup Wizard!"
echo "-------------------------------------------------"

# Store absolute path to config file based on initial CWD
CONFIG_FILE="$(pwd)/ssh_minecraft.toml"

# Helper to read a key from TOML-like config
get_config_value() {
    local key=$1
    if [ -f "$CONFIG_FILE" ]; then
        grep "^$key =" "$CONFIG_FILE" | sed -E 's/^.*= "(.*)"$/\1/'
    fi
}

# Load config
if [ -f "$CONFIG_FILE" ]; then
    echo "Found configuration file: $CONFIG_FILE"
    SERVER_PORT=$(get_config_value "server_port")
    SSH_USER=$(get_config_value "ssh_user")
    SSH_PASSWORD=$(get_config_value "ssh_password")
    SERVER_FILEPATH=$(get_config_value "server_filepath")
    SERVER_JAR=$(get_config_value "server_jar")
    START_ON_BOOT=$(get_config_value "start_on_boot")
fi

# 2. Ask for inputs (only if not loaded)

if [ -z "$SERVER_PORT" ]; then
    read -p "Enter server port [25565]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-25565}
else
    echo "Using configured Port: $SERVER_PORT"
fi

if [ -z "$SSH_USER" ]; then
    read -p "Enter SSH username [steve]: " SSH_USER
    SSH_USER=${SSH_USER:-steve}
else
    echo "Using configured SSH User: $SSH_USER"
fi

# Secure password prompt
if [ -z "$SSH_PASSWORD" ]; then
    while true; do
        read -s -p "Enter SSH password: " SSH_PASSWORD
        echo
        read -s -p "Confirm SSH password: " SSH_PASSWORD_CONFIRM
        echo
        if [ "$SSH_PASSWORD" = "$SSH_PASSWORD_CONFIRM" ] && [ -n "$SSH_PASSWORD" ]; then
            break
        else
            echo "Passwords do not match or are empty. Please try again."
        fi
    done
else
    echo "Using configured SSH Password."
fi

if [ -z "$SERVER_FILEPATH" ]; then
    read -p "Enter server filepath [/opt/minecraft]: " SERVER_FILEPATH
    SERVER_FILEPATH=${SERVER_FILEPATH:-/opt/minecraft}
else
    echo "Using configured Server Path: $SERVER_FILEPATH"
fi

if [ -z "$SERVER_JAR" ]; then
    read -p "Enter server jar path [./minecraft_server.jar]: " SERVER_JAR
    SERVER_JAR=${SERVER_JAR:-./minecraft_server.jar}
else
    echo "Using configured Jar Path: $SERVER_JAR"
fi

# Validate server jar exists
if [ ! -f "$SERVER_JAR" ]; then
    echo "Error: Server jar '$SERVER_JAR' not found."
    exit 1
fi

echo "-------------------------------------------------"
echo "Configuration:"
echo "Port: $SERVER_PORT"
echo "User: $SSH_USER"
echo "Path: $SERVER_FILEPATH"
echo "Jar:  $SERVER_JAR"
echo "-------------------------------------------------"

# 3. Secret Management (SSH Host Keys)
echo "Checking SSH host keys in Podman secrets..."

ensure_secret_key() {
    local KEY_TYPE=$1
    local SECRET_NAME="minecraft_host_${KEY_TYPE}_key"
    
    if ! podman secret exists "$SECRET_NAME"; then
        echo "Generating new $KEY_TYPE host key and storing as secret..."
        # Generate temp key (no passphrase)
        ssh-keygen -q -t "$KEY_TYPE" -N "" -f "./temp_key_${KEY_TYPE}"
        # Create secret
        podman secret create "$SECRET_NAME" "./temp_key_${KEY_TYPE}"
        # Clean up local files
        rm "./temp_key_${KEY_TYPE}" "./temp_key_${KEY_TYPE}.pub"
    else
        echo "Secret $SECRET_NAME found. Reusing."
    fi
}

ensure_secret_key "rsa"
ensure_secret_key "ecdsa"
ensure_secret_key "ed25519"

# 5. Create server directory and copy jar
if [ ! -d "$SERVER_FILEPATH" ]; then
    echo "Creating server directory '$SERVER_FILEPATH'..."
    if ! mkdir -p "$SERVER_FILEPATH" 2>/dev/null; then
        echo "Permission denied. Trying with sudo..."
        if ! sudo mkdir -p "$SERVER_FILEPATH"; then
            echo "Error: Failed to create directory. Check permissions."
            exit 1
        fi
        sudo chown "$USER" "$SERVER_FILEPATH"
    fi
fi

echo "Copying server jar..."
cp "$SERVER_JAR" "$SERVER_FILEPATH/minecraft_server.jar"

# 6. Build the container
echo "Building container image 'ssh_minecraft_image'..."
podman build \
    -f Containerfile \
    --build-arg SSH_USER="$SSH_USER" \
    --build-arg SSH_PASSWORD="$SSH_PASSWORD" \
    -t ssh_minecraft_image .

# 7. Start server options
echo "-------------------------------------------------"
if [ -z "$START_ON_BOOT" ]; then
    read -p "Do you want to start the server on startup (systemd)? [y/N]: " START_ON_BOOT
    START_ON_BOOT=${START_ON_BOOT:-n}
else 
    echo "Using configured Start on Boot: $START_ON_BOOT"
fi

CONTAINER_NAME="ssh_minecraft_container"

# Stop existing if any
podman stop "$CONTAINER_NAME" 2>/dev/null || true
podman rm "$CONTAINER_NAME" 2>/dev/null || true

# Common arguments
# We mount secrets directly to /etc/ssh/ssh_host_*_key with mode 0400
PODMAN_ARGS=(
    --name "$CONTAINER_NAME"
    --init # without this, sigterms aren't forwarded
    --stop-signal SIGTERM
    --stop-timeout 60
    -p "${SERVER_PORT}:22"
    -v "${SERVER_FILEPATH}:/opt/minecraft:z"
    --secret source=minecraft_host_rsa_key,target=/etc/ssh/ssh_host_rsa_key,mode=0400
    --secret source=minecraft_host_ecdsa_key,target=/etc/ssh/ssh_host_ecdsa_key,mode=0400
    --secret source=minecraft_host_ed25519_key,target=/etc/ssh/ssh_host_ed25519_key,mode=0400
    -it
)

if [[ "$START_ON_BOOT" =~ ^[Yy]$ ]]; then
    echo "Setting up systemd service..."

    # Run container in background
    podman run -d "${PODMAN_ARGS[@]}" ssh_minecraft_image

    # Generate systemd unit
    mkdir -p ~/.config/systemd/user
    cd ~/.config/systemd/user
    podman generate systemd --new --name "$CONTAINER_NAME" --files

    # Cleanup temp container
    podman stop "$CONTAINER_NAME" 2>/dev/null || true
    podman rm "$CONTAINER_NAME" 2>/dev/null || true

    # Enable and start
    systemctl --user daemon-reload
    systemctl --user enable --now "container-${CONTAINER_NAME}.service"

    echo "Systemd service installed and started."
else
    echo "Starting server in current window..."
    podman run -it --rm "${PODMAN_ARGS[@]}" ssh_minecraft_image
fi

# Save config
echo "Saving configuration to $CONFIG_FILE..."
cat > "$CONFIG_FILE" <<EOF
server_port = "$SERVER_PORT"
ssh_user = "$SSH_USER"
ssh_password = "$SSH_PASSWORD"
server_filepath = "$SERVER_FILEPATH"
server_jar = "$SERVER_JAR"
start_on_boot = "$START_ON_BOOT"
EOF

