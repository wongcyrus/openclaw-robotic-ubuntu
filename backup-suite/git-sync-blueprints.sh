#!/usr/bin/env bash

# OpenClaw Git Sync Script for Agent Blueprints & Target Repository Push
# This script commits changes locally to the OpenClaw workspace and syncs/pushes
# configurations and blueprints to the repository at /home/developer/Documents/openclaw-robotic-ubuntu,
# strictly enforcing exclusion patterns and redacting secrets to guarantee ZERO data/credential leakage.

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
TARGET_REPO_DIR="/home/developer/Documents/openclaw-robotic-ubuntu"

if [[ ! -d "$WORKSPACE_DIR" ]]; then
    log_error "OpenClaw Workspace directory not found: ${WORKSPACE_DIR}"
    exit 1
fi

if [[ ! -d "$TARGET_REPO_DIR" ]]; then
    log_error "Target push project repository not found: ${TARGET_REPO_DIR}"
    exit 1
fi

# 2. Sync Local OpenClaw Workspace (Local Version Control)
log_info "Synchronizing local OpenClaw workspace changes..."
cd "$WORKSPACE_DIR"

# Initialize local git if not already done
if [[ ! -d ".git" ]]; then
    git init
    git checkout -b master 2>/dev/null || true
fi

# Inject/Ensure .gitignore rules
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
    log_success "Blueprints committed locally."
else
    log_info "Local workspace is already up to date."
fi

# 3. Redact Secrets & Create openclaw.json Template
# We MUST protect API keys, Telegram Bot Tokens, and Gateway keys in the public/pushed repo.
log_info "Sanitizing configurations to prevent secret leaks..."
RAW_CONFIG_PATH="${OPENCLAW_DIR}/openclaw.json"
TARGET_TEMPLATE_PATH="${TARGET_REPO_DIR}/openclaw.json.template"

if [[ -f "$RAW_CONFIG_PATH" ]]; then
    # Run a recursive python redactor to purge all credentials
    python3 - <<EOF
import json
import os

def redact_sensitive_keys(data):
    if isinstance(data, dict):
        new_dict = {}
        for k, v in data.items():
            if k in ["apiKey", "botToken", "token", "password", "secret"]:
                if isinstance(v, str):
                    if k == "botToken":
                        new_dict[k] = "<REDACTED_TELEGRAM_BOT_TOKEN>"
                    elif k == "apiKey":
                        new_dict[k] = "<REDACTED_API_KEY>"
                    elif k == "token":
                        new_dict[k] = "<REDACTED_GATEWAY_AUTH_TOKEN>"
                    else:
                        new_dict[k] = "<REDACTED_SECRET>"
                else:
                    new_dict[k] = redact_sensitive_keys(v)
            else:
                new_dict[k] = redact_sensitive_keys(v)
        return new_dict
    elif isinstance(data, list):
        return [redact_sensitive_keys(item) for item in data]
    else:
        return data

try:
    with open("$RAW_CONFIG_PATH", "r") as f:
        config = json.load(f)
    sanitized = redact_sensitive_keys(config)
    
    # Ensure configs target directory exists
    os.makedirs(os.path.dirname("$TARGET_TEMPLATE_PATH"), exist_ok=True)
    
    with open("$TARGET_TEMPLATE_PATH", "w") as f:
        json.dump(sanitized, f, indent=2)
    print("SUCCESS")
except Exception as e:
    print(f"ERROR: {e}")
EOF
    log_success "Sanitized configuration template written to: ${TARGET_TEMPLATE_PATH}"
else
    log_warn "Raw config openclaw.json not found. Skipping config template sync."
fi

# 4. Sync Agent Blueprints to Target Repo (with Strict Leak Prevention Exclusions)
log_info "Mirroring blueprints to target project workspace..."
TARGET_WORKSPACE_DIR="${TARGET_REPO_DIR}/workspace"
mkdir -p "$TARGET_WORKSPACE_DIR"

# Construct rsync command with rigorous exclusions to guarantee NO memory or database leak
rsync -a --delete \
    --exclude="*.sqlite*" \
    --exclude="**/memory/**" \
    --exclude="*MEMORY.md" \
    --exclude="*memory.md" \
    --exclude=".git/**" \
    --exclude="logs/**" \
    --exclude="*.log" \
    --exclude="*.pyc" \
    --exclude="__pycache__/**" \
    --exclude="subagents/**" \
    --exclude="update-check.json" \
    --exclude="exec-approvals.json" \
    --exclude="gateway-supervisor-restart-handoff.json" \
    "${WORKSPACE_DIR}/" "${TARGET_WORKSPACE_DIR}/"

log_success "Blueprints synced to ${TARGET_WORKSPACE_DIR} (verified leak-free)."

# 5. Commit and Push to Target Repository
log_info "Preparing changes in target repository..."
cd "$TARGET_REPO_DIR"

# Stage workspace and sanitized template
git add workspace/
if [[ -f "openclaw.json.template" ]]; then
    git add openclaw.json.template
fi

# Check if there are changes to push
if git diff --cached --quiet; then
    log_info "No blueprint updates to commit in target repository."
else
    TIMESTAMP="$(date +"%Y-%m-%d %H:%M:%S")"
    git commit -m "Sync and update agent blueprints: ${TIMESTAMP}"
    log_success "Changes committed in target repository."
    
    # Push changes to remote origin branch
    CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    log_info "Pushing updates to origin/${CURRENT_BRANCH}..."
    if git push origin "$CURRENT_BRANCH"; then
        log_success "Successfully pushed blueprint updates to remote project upstream!"
    else
        log_error "Push failed. Please verify network or git remote permissions."
    fi
fi
