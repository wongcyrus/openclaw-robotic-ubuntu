#!/usr/bin/env bash

# ==============================================================================
#                      UBUNTU NEW SERVER INITIALIZER SCRIPT
# ==============================================================================
# This script automates setting up a new server by:
# 1. Cloning all relevant workspace git repositories.
# 2. Installing NVM and Node.js v22.22.3 (if not installed).
# 3. Generating the SSH Tunnel configuration.
# 4. Creating and enabling all 4 Systemd User Services.
# 5. Enabling Systemd Linger for the current user (auto-runs services on boot).
# ==============================================================================

set -euo pipefail

WORKSPACE_DIR="$HOME/Documents"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

echo "========================================="
echo "📁 1. Creating Workspace Directory..."
echo "========================================="
mkdir -p "$WORKSPACE_DIR"
mkdir -p "$SYSTEMD_USER_DIR"

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
        git -C "$target_path" submodule update --init --recursive
    else
        echo "📥 Cloning $repo_name (with submodules)..."
        git clone --recursive "${REPOS[$repo_name]}" "$target_path"
    fi
done

echo "========================================="
echo "🟢 3. Node.js & NVM Setup..."
echo "========================================="
# Install NVM if not present
if [ ! -d "$HOME/.nvm" ]; then
    echo "📥 Installing NVM (Node Version Manager)..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

# Load NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

echo "📦 Installing Node.js v22.22.3..."
nvm install v22.22.3 || echo "Warning: Failed to install node v22.22.3 via nvm. If already installed, ignoring."
nvm use v22.22.3 || echo "Warning: Failed to switch to node v22.22.3."

NODE_BIN_DIR="$HOME/.nvm/versions/node/v22.22.3/bin"
if [ ! -d "$NODE_BIN_DIR" ]; then
    # Fallback to current node location if the specific version folder doesn't match
    NODE_BIN_DIR=$(dirname "$(which node || echo '/usr/bin/node')")
fi
echo "🔗 Detected node binary directory: $NODE_BIN_DIR"

echo "========================================="
echo "🔑 4. SSH Key & ssh-tunnel.sh Setup..."
echo "========================================="
# Check if key exists, generate if missing
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo "🔑 Generating secure Ed25519 SSH key pair..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
else
    echo "✅ Existing SSH key pair found."
fi

# Prompt for SSH Tunnel details or use defaults
read -p "Enter remote server IP for SSH Tunnel [default: 192.168.249.129]: " REMOTE_IP
REMOTE_IP=${REMOTE_IP:-192.168.249.129}

read -p "Enter remote SSH user [default: developer]: " REMOTE_USER
REMOTE_USER=${REMOTE_USER:-developer}

# Create ssh-tunnel.sh
echo "📝 Creating ssh-tunnel.sh..."
cat << EOF > "$WORKSPACE_DIR/ssh-tunnel.sh"
#!/bin/bash
ssh -N -L 4000:localhost:4000 -i \$HOME/.ssh/id_ed25519 ${REMOTE_USER}@${REMOTE_IP}
EOF
chmod +x "$WORKSPACE_DIR/ssh-tunnel.sh"

echo "========================================="
echo "⚙️ 5. Generating Systemd User Services..."
echo "========================================="

# --- 1. ssh-tunnel.service ---
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

# --- 2. xiaoice-openclaw-api.service ---
echo "⚙️ Generating xiaoice-openclaw-api.service..."
cat << EOF > "$SYSTEMD_USER_DIR/xiaoice-openclaw-api.service"
[Unit]
Description=Xiaoice OpenClaw API Docker Compose Service
After=docker.service network-online.target
Wants=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$WORKSPACE_DIR/xiaoice-openclaw-api
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
After=docker.service network-online.target
Wants=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$WORKSPACE_DIR/openclaw-character-dashboard
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
After=network-online.target
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
After=docker.service network-online.target
Wants=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$WORKSPACE_DIR/amazon-nova-robotics/domain-expansion-ar-game
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
Restart=no

[Install]
WantedBy=default.target
EOF

echo "========================================="
echo "⚡ 6. Activating Services & Enabling Linger..."
echo "========================================="
# Enable linger
loginctl enable-linger "$USER"

# Reload, enable, and start services
systemctl --user daemon-reload

SERVICES=(
    "ssh-tunnel.service"
    "xiaoice-openclaw-api.service"
    "openclaw-character-dashboard.service"
    "claw3d.service"
    "domain-expansion-ar-game.service"
)

for svc in "${SERVICES[@]}"; do
    echo "⚡ Enabling and Starting $svc..."
    systemctl --user enable "$svc"
    systemctl --user start "$svc" || echo "Warning: Failed to start $svc immediately (might need manual project setups like docker build or npm install first)."
done

echo "========================================================================"
echo "🎉 Setup Complete!"
echo "========================================================================"
echo "⚠️ IMPORTANT MANUAL STEP:"
echo "Before the SSH Tunnel starts working, you MUST copy your new SSH public key"
echo "to the remote server by running this command:"
echo "  ssh-copy-id -i ~/.ssh/id_ed25519.pub ${REMOTE_USER}@${REMOTE_IP}"
echo "========================================================================"
