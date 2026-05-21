#!/usr/bin/env bash

# OpenClaw Restore Utility
# Restores configurations and agent blueprints from a previously generated backup archive,
# taking a temporary rollback backup of current settings beforehand for safety.

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

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=backup.conf
    source "$CONFIG_FILE"
else
    log_error "Configuration file not found: ${CONFIG_FILE}"
    exit 1
fi

# Pre-flight check
if [[ ! -d "$OPENCLAW_DIR" ]]; then
    log_warn "Target directory ${OPENCLAW_DIR} does not exist. It will be created during restoration."
fi

# 1. Identify and Select Backup Archive
SELECTED_ARCHIVE=""

if [[ $# -ge 1 ]]; then
    SELECTED_ARCHIVE="$1"
else
    # Interactive selection from BACKUP_DIR
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "Backup storage directory ${BACKUP_DIR} does not exist."
        exit 1
    fi
    
    # List backups
    mapfile -t ARCHIVES < <(find "$BACKUP_DIR" -type f \( -name "openclaw_blueprints_*.*" \) | sort -r)
    
    if [[ ${#ARCHIVES[@]} -eq 0 ]]; then
        log_error "No backup archives found in ${BACKUP_DIR}."
        exit 1
    fi
    
    log_info "Available backups in ${BACKUP_DIR}:"
    for i in "${!ARCHIVES[@]}"; do
        base_name="$(basename "${ARCHIVES[$i]}")"
        file_size="$(du -sh "${ARCHIVES[$i]}" | cut -f1)"
        file_mtime="$(date -r "${ARCHIVES[$i]}" +"%Y-%m-%d %H:%M:%S")"
        echo -e "  [$((i + 1))] ${base_name} (${file_size}, modified: ${file_mtime})"
    done
    
    echo -ne "\nSelect an archive to restore [1-${#ARCHIVES[@]}]: "
    read -r SELECTION
    
    # Validate input
    if [[ ! "$SELECTION" =~ ^[0-9]+$ ]] || [[ "$SELECTION" -lt 1 ]] || [[ "$SELECTION" -gt ${#ARCHIVES[@]} ]]; then
        log_error "Invalid selection. Exiting."
        exit 1
    fi
    
    SELECTED_ARCHIVE="${ARCHIVES[$((SELECTION - 1))]}"
fi

if [[ ! -f "$SELECTED_ARCHIVE" ]]; then
    log_error "Backup file not found: ${SELECTED_ARCHIVE}"
    exit 1
fi

log_info "Selected archive: ${SELECTED_ARCHIVE}"

# 2. Handle Decryption if Encrypted (.gpg)
ARCHIVE_TO_EXTRACT="$SELECTED_ARCHIVE"
TEMP_DECRYPTED=""

if [[ "$SELECTED_ARCHIVE" == *.gpg ]]; then
    TEMP_DECRYPTED="/tmp/openclaw_blueprints_decrypted_$(date +"%Y%m%d_%H%M%S")"
    log_info "Backup is GPG encrypted. Decrypting..."
    
    if [[ -n "${GPG_PASSPHRASE}" ]]; then
        # Automated decryption
        if echo "${GPG_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 --decrypt -o "$TEMP_DECRYPTED" "$SELECTED_ARCHIVE"; then
            log_success "Decryption successful."
            ARCHIVE_TO_EXTRACT="$TEMP_DECRYPTED"
        else
            log_error "Decryption failed. Please verify your passphrase in backup.conf."
            exit 1
        fi
    else
        # Interactive decryption
        log_warn "No GPG passphrase provided in config. Prompting interactively..."
        if gpg --decrypt -o "$TEMP_DECRYPTED" "$SELECTED_ARCHIVE"; then
            log_success "Decryption successful."
            ARCHIVE_TO_EXTRACT="$TEMP_DECRYPTED"
        else
            log_error "Decryption failed."
            exit 1
        fi
    fi
fi

# Clean up decrypted file on exit
cleanup() {
    if [[ -n "$TEMP_DECRYPTED" ]] && [[ -f "$TEMP_DECRYPTED" ]]; then
        rm -f "$TEMP_DECRYPTED"
        log_info "Temporary decrypted file cleared."
    fi
}
trap cleanup EXIT

# 3. Create Safety Rollback of current files
ROLLBACK_DIR="/tmp/openclaw_rollback_before_restore_$(date +"%Y%m%d_%H%M%S")"
if [[ -d "$OPENCLAW_DIR" ]]; then
    log_warn "Before restoring, creating a safety rollback of your current configuration..."
    log_info "Rollback location: ${ROLLBACK_DIR}"
    
    mkdir -p "$ROLLBACK_DIR"
    # Copy configuration files and directories if they exist (ignoring sqlite databases)
    # We copy: openclaw.json, workspace configs, credentials, identity
    if [[ -f "${OPENCLAW_DIR}/openclaw.json" ]]; then
        cp "${OPENCLAW_DIR}/openclaw.json" "${ROLLBACK_DIR}/"
    fi
    for folder in workspace credentials identity; do
        if [[ -d "${OPENCLAW_DIR}/${folder}" ]]; then
            # Mirror the folder structure without sqlite files
            mkdir -p "${ROLLBACK_DIR}/${folder}"
            rsync -a --exclude="*.sqlite*" --exclude="*/memory/*" "${OPENCLAW_DIR}/${folder}/" "${ROLLBACK_DIR}/${folder}/" || cp -a "${OPENCLAW_DIR}/${folder}" "${ROLLBACK_DIR}/"
        fi
    done
    log_success "Safety rollback saved successfully to ${ROLLBACK_DIR}."
fi

# 4. Perform Restoration
OPENCLAW_PARENT="$(dirname "$OPENCLAW_DIR")"

log_info "Restoring configurations and blueprints to ${OPENCLAW_DIR}..."
# Extract the tarball. 
# tar is run relative to the parent directory (e.g. /home/developer) to restore the .openclaw directory contents
if tar -xf "$ARCHIVE_TO_EXTRACT" -C "$OPENCLAW_PARENT"; then
    log_success "Extraction completed successfully."
else
    log_error "Extraction failed! Attempting to restore safety rollback..."
    if [[ -d "$ROLLBACK_DIR" ]]; then
        cp -af "${ROLLBACK_DIR}/." "$OPENCLAW_DIR/"
        log_success "Rollback applied successfully. Your system is untouched."
    fi
    exit 1
fi

log_success "OpenClaw configurations and agent blueprints have been successfully restored!"
log_info "Note: SQLite databases and conversational memories were not affected by this restoration."
