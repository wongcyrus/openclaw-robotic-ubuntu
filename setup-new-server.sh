#!/usr/bin/env bash

# ==============================================================================
#                      UBUNTU NEW SERVER INITIALIZER SCRIPT
# ==============================================================================
# This script automates setting up a new server by:
# 1. Creating workspace and configuration directories.
# 2. Cloning all relevant workspace git repositories (and submodules).
# 3. Installing NVM, Node.js v24.21.0, and pnpm.
# 4. Building OpenClaw and linking the openclaw CLI.
# 5. Installing dependencies for Claw3D and Domain Expansion AR Game.
# 6. Setting up local speech-to-text (Whisper) & ffmpeg.
# 7. Generating the SSH Tunnel configuration (optional).
# 8. Configuring Systemd User Environment variables (environment.d).
# 9. Generating Systemd User Services:
#    - openclaw-gateway.service (Port 18789)
#    - xiaoice-openclaw-api.service (Port 3002)
#    - openclaw-character-dashboard.service (Ports 3001, 5173)
#    - claw3d.service (Port 3000)
#    - domain-expansion-ar-game.service (Port 3443)
#    - ssh-tunnel.service (Port 4000, optional)
# 10. Enabling Systemd Linger for the current user and activating all services.
# ==============================================================================

set -euo pipefail

WORKSPACE_DIR="$HOME/Documents"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SYSTEMD_ENV_DIR="$HOME/.config/environment.d"

echo "========================================="
echo "📁 1. Creating Workspace & Config Directories..."
echo "========================================="
mkdir -p "$WORKSPACE_DIR"
mkdir -p "$SYSTEMD_USER_DIR"
mkdir -p "$SYSTEMD_ENV_DIR"
mkdir -p "$HOME/.openclaw/shared"
mkdir -p "$HOME/.local/bin"

echo "========================================="
echo "🌐 2. Cloning Workspace Git Repositories..."
echo "========================================="
declare -A REPOS=(
    ["amazon-nova-robotics"]="https://github.com/wongcyrus/amazon-nova-robotics"
    ["Claw3D"]="https://github.com/wongcyrus/Claw3D"
    ["openclaw"]="https://github.com/openclaw/openclaw"
    ["openclaw-character-dashboard"]="https://github.com/wongcyrus/openclaw-character-dashboard"
    ["robot-group-action-planner"]="https://github.com/wongcyrus/robot-group-action-planner"
    ["xiaoice-openclaw-api"]="https://github.com/wongcyrus/xiaoice-openclaw-api.git"
)

for repo_name in "${!REPOS[@]}"; do
    target_path="$WORKSPACE_DIR/$repo_name"
    if [ -d "$target_path" ]; then
        echo "✅ $repo_name already exists, checking for submodules..."
        git -C "$target_path" submodule update --init --recursive || echo "⚠️ Warning: Failed to update submodules for $repo_name"
    else
        echo "📥 Cloning $repo_name (with submodules)..."
        git clone --recursive "${REPOS[$repo_name]}" "$target_path"
    fi
done

echo "========================================="
echo "🟢 3. Node.js, NVM & PNPM Setup..."
echo "========================================="
# Install NVM if not present
if [ ! -d "$HOME/.nvm" ]; then
    echo "📥 Installing NVM (Node Version Manager)..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

# Load NVM into current shell session
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

NODE_TARGET_VERSION="v24.21.0"
echo "📦 Installing Node.js $NODE_TARGET_VERSION (required by OpenClaw >=24.16.0)..."
nvm install "$NODE_TARGET_VERSION" || echo "Warning: Failed to install node $NODE_TARGET_VERSION via nvm. If already installed, ignoring."
nvm use "$NODE_TARGET_VERSION" || echo "Warning: Failed to switch to node $NODE_TARGET_VERSION."
nvm alias default "$NODE_TARGET_VERSION" || true

NODE_BIN_DIR="$HOME/.nvm/versions/node/$NODE_TARGET_VERSION/bin"
if [ ! -d "$NODE_BIN_DIR" ]; then
    NODE_BIN_DIR=$(dirname "$(which node || echo '/usr/bin/node')")
fi
echo "🔗 Detected node binary directory: $NODE_BIN_DIR"
export PATH="$NODE_BIN_DIR:$HOME/.local/bin:$PATH"

# Install pnpm (required by OpenClaw)
if ! command -v pnpm &> /dev/null; then
    echo "📦 Installing pnpm globally..."
    "$NODE_BIN_DIR/npm" install -g pnpm@12.5.1 || "$NODE_BIN_DIR/npm" install -g pnpm
else
    echo "✅ pnpm is already installed."
fi

echo "========================================="
echo "🦞 3.2. Building OpenClaw & Setting up CLI..."
echo "========================================="
if [ -d "$WORKSPACE_DIR/openclaw" ]; then
    echo "📦 Installing OpenClaw dependencies with pnpm..."
    (cd "$WORKSPACE_DIR/openclaw" && "$NODE_BIN_DIR/pnpm" install)
    
    echo "🔨 Building OpenClaw..."
    (cd "$WORKSPACE_DIR/openclaw" && "$NODE_BIN_DIR/pnpm" build)
    
    echo "🔗 Linking OpenClaw CLI globally..."
    (cd "$WORKSPACE_DIR/openclaw" && "$NODE_BIN_DIR/npm" link)
    if [ -f "$NODE_BIN_DIR/openclaw" ]; then
        ln -sf "$NODE_BIN_DIR/openclaw" "$HOME/.local/bin/openclaw"
    fi
    echo "✅ OpenClaw CLI linked successfully."
fi

echo "========================================="
echo "📦 3.3. Installing Application Dependencies..."
echo "========================================="
# Claw3D dependencies
if [ -d "$WORKSPACE_DIR/Claw3D" ]; then
    echo "📦 Installing Claw3D dependencies..."
    (cd "$WORKSPACE_DIR/Claw3D" && "$NODE_BIN_DIR/npm" install)
fi

# Domain Expansion AR Game dependencies
AR_GAME_DIR="$WORKSPACE_DIR/amazon-nova-robotics/domain-expansion-ar-game"
if [ -d "$AR_GAME_DIR" ] && [ -f "$AR_GAME_DIR/package.json" ]; then
    echo "📦 Installing Domain Expansion AR Game dependencies..."
    (cd "$AR_GAME_DIR" && "$NODE_BIN_DIR/npm" install)
fi

# Ensure .env for xiaoice-openclaw-api
if [ -d "$WORKSPACE_DIR/xiaoice-openclaw-api" ]; then
    if [ ! -f "$WORKSPACE_DIR/xiaoice-openclaw-api/.env" ] && [ -f "$WORKSPACE_DIR/xiaoice-openclaw-api/.env.example" ]; then
        echo "📝 Creating xiaoice-openclaw-api/.env from .env.example..."
        cp "$WORKSPACE_DIR/xiaoice-openclaw-api/.env.example" "$WORKSPACE_DIR/xiaoice-openclaw-api/.env"
    fi
fi

# Ensure .env for openclaw-character-dashboard
if [ -d "$WORKSPACE_DIR/openclaw-character-dashboard" ]; then
    if [ ! -f "$WORKSPACE_DIR/openclaw-character-dashboard/.env" ]; then
        echo "📝 Initializing openclaw-character-dashboard/.env..."
        cat << EOF > "$WORKSPACE_DIR/openclaw-character-dashboard/.env"
API_PORT=3001
OPENCLAW_DATA_PATH=$HOME/.openclaw
SHARED_DATA_PATH=$HOME/.openclaw/shared
VITE_PUBLIC_DIR=public_frieren
VITE_BANNER_TEXT=HKIIT 雲端系統及數據中心管理高級文憑 - OpenClaw 龍蝦 x 葬送的芙莉蓮
EOF
    fi
fi

echo "========================================="
echo "🎙️ 3.5. Local Speech-to-Text (Whisper) Setup..."
echo "========================================="
# Install ffmpeg if not installed
if ! command -v ffmpeg &> /dev/null; then
    echo "📥 Installing system dependency ffmpeg (requires sudo)..."
    sudo apt-get update && sudo apt-get install -y ffmpeg
else
    echo "✅ ffmpeg is already installed."
fi

# Install python3-pip if not installed
if ! command -v pip3 &> /dev/null; then
    echo "📥 Installing python3-pip (requires sudo)..."
    sudo apt-get install -y python3-pip || echo "Warning: Could not install python3-pip automatically."
fi

# Install openai-whisper if not installed
if ! command -v whisper &> /dev/null; then
    if command -v pip3 &> /dev/null; then
        echo "📥 Installing openai-whisper python package..."
        pip3 install --user openai-whisper --break-system-packages || echo "Warning: Failed to install openai-whisper via pip3."
    fi
else
    echo "✅ whisper command is already installed."
fi

echo "========================================="
echo "🔑 4. SSH Key & ssh-tunnel.sh Setup (Optional)..."
echo "========================================="
read -p "Do you want to configure SSH Tunnel? (y/N) [default: n]: " SETUP_SSH
SETUP_SSH=${SETUP_SSH:-n}

REMOTE_IP=""
REMOTE_USER=""

if [[ "$SETUP_SSH" =~ ^[Yy]$ ]]; then
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        echo "🔑 Generating secure Ed25519 SSH key pair..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
    else
        echo "✅ Existing SSH key pair found."
    fi

    read -p "Enter remote server IP for SSH Tunnel [default: 192.168.249.129]: " REMOTE_IP
    REMOTE_IP=${REMOTE_IP:-192.168.249.129}

    read -p "Enter remote SSH user [default: developer]: " REMOTE_USER
    REMOTE_USER=${REMOTE_USER:-developer}

    echo "📝 Creating ssh-tunnel.sh..."
    cat << EOF > "$WORKSPACE_DIR/ssh-tunnel.sh"
#!/bin/bash
ssh -N -L 4000:localhost:4000 -i \$HOME/.ssh/id_ed25519 ${REMOTE_USER}@${REMOTE_IP}
EOF
    chmod +x "$WORKSPACE_DIR/ssh-tunnel.sh"
else
    echo "⏭️ Skipping SSH Key & SSH Tunnel setup..."
fi

echo "========================================="
echo "🌍 4.5. Configuring Systemd User Environment Variables..."
echo "========================================="
CURRENT_MCP=""
if [ -f "$HOME/.openclaw/gateway.systemd.env" ]; then
    CURRENT_MCP=$(grep "^MCP_SERVER_URL=" "$HOME/.openclaw/gateway.systemd.env" | cut -d'=' -f2- || true)
fi
DEFAULT_MCP="${CURRENT_MCP:-https://awsagenticroboticsroructrobottoolgatewayf6afb2aa-qglfdgcbvy.gateway.bedrock-agentcore.us-east-1.amazonaws.com/mcp}"

read -p "Enter MCP_SERVER_URL [default: $DEFAULT_MCP]: " INPUT_MCP
INPUT_MCP=${INPUT_MCP:-$DEFAULT_MCP}

echo "📝 Generating $SYSTEMD_ENV_DIR/mcp.conf..."
cat << EOF > "$SYSTEMD_ENV_DIR/mcp.conf"
MCP_SERVER_URL="$INPUT_MCP"
EOF

# Sync to OpenClaw gateway environment file if present
mkdir -p "$HOME/.openclaw"
if [ -f "$HOME/.openclaw/gateway.systemd.env" ]; then
    if grep -q "^MCP_SERVER_URL=" "$HOME/.openclaw/gateway.systemd.env"; then
        sed -i "s|^MCP_SERVER_URL=.*|MCP_SERVER_URL=$INPUT_MCP|" "$HOME/.openclaw/gateway.systemd.env"
    else
        echo "MCP_SERVER_URL=$INPUT_MCP" >> "$HOME/.openclaw/gateway.systemd.env"
    fi
else
    cat << EOF > "$HOME/.openclaw/gateway.systemd.env"
MCP_SERVER_URL=$INPUT_MCP
EOF
fi

echo "========================================="
echo "⚙️ 5. Generating Systemd User Services..."
echo "========================================="

# --- 1. openclaw-gateway.service ---
echo "⚙️ Generating openclaw-gateway.service..."
cat << EOF > "$SYSTEMD_USER_DIR/openclaw-gateway.service"
[Unit]
Description=OpenClaw Gateway
After=network-online.target
Wants=network-online.target
StartLimitBurst=10
StartLimitIntervalSec=300

[Service]
ExecStart=$NODE_BIN_DIR/node $WORKSPACE_DIR/openclaw/dist/index.js gateway --port 18789
Restart=always
RestartSec=5
RestartPreventExitStatus=78
TimeoutStopSec=330
TimeoutStartSec=30
SuccessExitStatus=0 143
OOMPolicy=continue
KillMode=mixed
EnvironmentFile=-$HOME/.openclaw/gateway.systemd.env
Environment=HOME=$HOME
Environment=TMPDIR=/tmp
Environment=NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
Environment=PATH=$NODE_BIN_DIR:$HOME/.nvm/current/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin
Environment=OPENCLAW_GATEWAY_PORT=18789
Environment=OPENCLAW_SYSTEMD_UNIT=openclaw-gateway.service
Environment="OPENCLAW_WINDOWS_TASK_NAME=OpenClaw Gateway"
Environment=OPENCLAW_WINDOWS_TASK_HIDDEN_LAUNCHER=1
Environment=OPENCLAW_SERVICE_MARKER=openclaw
Environment=OPENCLAW_SERVICE_KIND=gateway

[Install]
WantedBy=default.target
EOF

# --- 2. xiaoice-openclaw-api.service ---
echo "⚙️ Generating xiaoice-openclaw-api.service..."
cat << EOF > "$SYSTEMD_USER_DIR/xiaoice-openclaw-api.service"
[Unit]
Description=Xiaoice OpenClaw API Docker Compose Service
After=docker.service network-online.target openclaw-gateway.service
Wants=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$WORKSPACE_DIR/xiaoice-openclaw-api
ExecStartPre=/usr/bin/bash -c 'until /usr/bin/docker info >/dev/null 2>&1; do sleep 1; done'
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
Restart=no

[Install]
WantedBy=default.target
EOF

# --- 3. openclaw-character-dashboard.service ---
echo "⚙️ Generating openclaw-character-dashboard.service..."
cat << EOF > "$SYSTEMD_USER_DIR/openclaw-character-dashboard.service"
[Unit]
Description=OpenClaw Character Dashboard Docker Compose Service
After=docker.service network-online.target openclaw-gateway.service
Wants=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$WORKSPACE_DIR/openclaw-character-dashboard
ExecStartPre=/usr/bin/bash -c 'until /usr/bin/docker info >/dev/null 2>&1; do sleep 1; done'
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
Restart=no

[Install]
WantedBy=default.target
EOF

# --- 4. claw3d.service ---
echo "⚙️ Generating claw3d.service..."
cat << EOF > "$SYSTEMD_USER_DIR/claw3d.service"
[Unit]
Description=Claw3D Next.js Service
After=network-online.target openclaw-gateway.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$WORKSPACE_DIR/Claw3D
Environment="PATH=$NODE_BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$NODE_BIN_DIR/npm run dev
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

# --- 5. domain-expansion-ar-game.service ---
echo "⚙️ Generating domain-expansion-ar-game.service..."
cat << EOF > "$SYSTEMD_USER_DIR/domain-expansion-ar-game.service"
[Unit]
Description=Domain Expansion AR Game Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$WORKSPACE_DIR/amazon-nova-robotics/domain-expansion-ar-game
Environment="PATH=$NODE_BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="PORT=3443"
ExecStart=$NODE_BIN_DIR/npm run dev
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

# --- 6. ssh-tunnel.service ---
if [[ "$SETUP_SSH" =~ ^[Yy]$ ]]; then
    echo "⚙️ Generating ssh-tunnel.service..."
    cat << EOF > "$SYSTEMD_USER_DIR/ssh-tunnel.service"
[Unit]
Description=SSH Tunnel Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$WORKSPACE_DIR
ExecStart=/usr/bin/bash $WORKSPACE_DIR/ssh-tunnel.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF
fi

echo "========================================="
echo "⚡ 6. Activating Services & Enabling Linger..."
echo "========================================="
# Enable linger to keep services running without active login session
echo "👤 Enabling systemd linger for user: $USER..."
loginctl enable-linger "$USER" || echo "⚠️ Warning: Could not enable linger automatically (may require polkit/root privileges)."

# Reload user systemd manager configuration
echo "🔄 Reloading systemd user daemon..."
systemctl --user daemon-reload

# Define services array for automated activation loop
SERVICES=(
    "openclaw-gateway.service"
    "xiaoice-openclaw-api.service"
    "openclaw-character-dashboard.service"
    "claw3d.service"
    "domain-expansion-ar-game.service"
)

if [[ "$SETUP_SSH" =~ ^[Yy]$ ]]; then
    SERVICES+=("ssh-tunnel.service")
fi

# Enable and start each configured service
for service in "${SERVICES[@]}"; do
    echo "🚀 Enabling and starting $service..."
    systemctl --user enable "$service" || echo "⚠️ Warning: Failed to enable $service"
    systemctl --user restart "$service" || echo "⚠️ Warning: Failed to start $service immediately (check journalctl --user -u $service -e)"
done

echo "========================================="
echo "🎉 Setup Finished! Current Services Summary:"
echo "========================================="
for service in "${SERVICES[@]}"; do
    ACTIVE_STATE=$(systemctl --user is-active "$service" 2>/dev/null || echo "inactive")
    echo "  • $service: $ACTIVE_STATE"
done

if [[ "$SETUP_SSH" =~ ^[Yy]$ ]]; then
    echo "========================================================================"
    echo "⚠️ IMPORTANT MANUAL STEP FOR SSH TUNNEL:"
    echo "Before the SSH Tunnel starts working, you MUST copy your SSH public key"
    echo "to the remote server by running this command:"
    echo "  ssh-copy-id -i ~/.ssh/id_ed25519.pub ${REMOTE_USER}@${REMOTE_IP}"
    echo "========================================================================"
fi
