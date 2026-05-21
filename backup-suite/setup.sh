#!/usr/bin/env bash

# OpenClaw Backup Suite Setup and Scheduling Utility
# Installs automated schedules (via crontab) for backups and git blueprint commits,
# and offers to run a quick test backup immediately.

set -euo pipefail

# Get absolute script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/backup.conf"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup.sh"
GIT_SYNC_SCRIPT="${SCRIPT_DIR}/git-sync-blueprints.sh"

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

# 1. Validation checks
log_info "Setting up OpenClaw Backup and Recovery Suite..."

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Configuration file not found: ${CONFIG_FILE}"
    exit 1
fi

# Make sure all scripts are executable
chmod +x "$BACKUP_SCRIPT" "$GIT_SYNC_SCRIPT"

# 2. Check for Cron command
if ! command -v crontab &>/dev/null; then
    log_warn "crontab utility not found on this system. You will need to trigger backups manually."
    exit 0
fi

# 3. Setup Crontab entries
log_info "Configuring automated schedules in system crontab..."

# Define the cron jobs
BACKUP_CRON_LINE="0 2 * * * \"${BACKUP_SCRIPT}\" > /dev/null 2>&1 # OpenClaw Daily Blueprint Backup"
GIT_CRON_LINE="30 23 * * * \"${GIT_SYNC_SCRIPT}\" > /dev/null 2>&1 # OpenClaw Daily Git Blueprint Sync"

# Fetch existing crontab
TEMP_CRON="$(mktemp)"
crontab -l 2>/dev/null > "$TEMP_CRON" || true

# Append if not already present
UPDATED=0

if ! grep -Fq "$BACKUP_SCRIPT" "$TEMP_CRON"; then
    echo "$BACKUP_CRON_LINE" >> "$TEMP_CRON"
    log_success "Added: Daily configuration and blueprint backup at 2:00 AM."
    UPDATED=1
else
    log_info "Backup job already exists in crontab. Skipping."
fi

if ! grep -Fq "$GIT_SYNC_SCRIPT" "$TEMP_CRON"; then
    echo "$GIT_CRON_LINE" >> "$TEMP_CRON"
    log_success "Added: Daily agent workspace Git auto-commit at 11:30 PM."
    UPDATED=1
else
    log_info "Git Sync job already exists in crontab. Skipping."
fi

# Apply the new crontab
if [[ "$UPDATED" -eq 1 ]]; then
    if crontab "$TEMP_CRON"; then
        log_success "Crontab updated successfully!"
    else
        log_error "Failed to update crontab. Please run manually as a superuser or verify cron service."
    fi
else
    log_info "Your automated schedules are already fully configured!"
fi

rm -f "$TEMP_CRON"

# 4. Prompt for immediate test backup
echo -ne "\nWould you like to run a test backup immediately? (y/N): "
read -r RUN_TEST

if [[ "$RUN_TEST" =~ ^[Yy]$ ]]; then
    log_info "Executing manual test backup..."
    if "$BACKUP_SCRIPT"; then
        log_success "Test backup completed successfully!"
    else
        log_error "Test backup failed. Please check configurations."
    fi
else
    log_info "Setup completed. You can trigger backups manually anytime by running: ${BACKUP_SCRIPT}"
fi
