#!/usr/bin/env bash

# OpenClaw Git Sync Script (Local Workspace Only)
# This script ensures a robust .gitignore is set up in your local OpenClaw workspace,
# and automatically commits updates to agent blueprints, configs, and custom scripts locally,
# keeping it entirely self-contained without pushing any files or templates to GitHub.

set -euo pipefail

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/backup.conf"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 1. Load config
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=backup.conf
    source "$CONFIG_FILE"
else
    OPENCLAW_DIR="/home/developer/.openclaw"
fi

WORKSPACE_DIR="${OPENCLAW_DIR}/workspace"

if [[ ! -d "$WORKSPACE_DIR" ]]; then
    log_error "OpenClaw Workspace directory not found: ${WORKSPACE_DIR}"
    exit 1
fi

# 2. Sync Local OpenClaw Workspace (Local Version Control Only)
log_info "Synchronizing local OpenClaw workspace changes..."
cd "$WORKSPACE_DIR"

# Initialize local git if not already done
if [[ ! -d ".git" ]]; then
    git init
    git checkout -b master 2>/dev/null || true
fi

# Inject/Ensure .gitignore rules to prevent memory/data leaks locally
GITIGNORE_FILE=".gitignore"
REQUIRED_IGNORES=(
    "*.sqlite"
    "*.sqlite-shm"
    "*.sqlite-wal"
    "**/memory/"
    "**/memory/**"
    "*MEMORY.md"
    "*memory.md"
    "logs/"
    "*.log"
    "update-check.json"
    "exec-approvals.json"
    "gateway-supervisor-restart-handoff.json"
    "subagents/"
    "**/venv/"
    "**/.venv/"
)

CURRENT_RULES=""
if [[ -f "$GITIGNORE_FILE" ]]; then
    CURRENT_RULES="$(cat "$GITIGNORE_FILE")"
fi

for rule in "${REQUIRED_IGNORES[@]}"; do
    if ! echo "$CURRENT_RULES" | grep -Fqx "$rule" &>/dev/null; then
        echo "$rule" >> "$GITIGNORE_FILE"
    fi
done

git add .
if ! git diff --cached --quiet; then
    TIMESTAMP="$(date +"%Y-%m-%d %H:%M:%S")"
    git commit -m "Auto-commit agent blueprints: ${TIMESTAMP}"
    log_success "Blueprints committed locally inside your private workspace."
else
    log_info "Local workspace is already up to date."
fi
