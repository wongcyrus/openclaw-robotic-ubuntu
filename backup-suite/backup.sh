#!/usr/bin/env bash

# OpenClaw Backup Utility
# This script bundles and backs up OpenClaw configurations and agent workspace structures (blueprints),
# excluding large sqlite databases, conversation histories (memory/ folders), and active logs.

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/backup.conf"

# Colors for elegant CLI feedback
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

# 1. Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=backup.conf
    source "$CONFIG_FILE"
    log_info "Loaded configuration from ${CONFIG_FILE}"
else
    log_error "Configuration file not found: ${CONFIG_FILE}"
    exit 1
fi

# 2. Validation Checks
if [[ ! -d "$OPENCLAW_DIR" ]]; then
    log_error "OpenClaw directory does not exist: ${OPENCLAW_DIR}"
    exit 1
fi

# Ensure backup storage directory exists
mkdir -p "$BACKUP_DIR"

# Resolve directories to absolute paths
OPENCLAW_DIR="$(cd "$OPENCLAW_DIR" && pwd)"
BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd)"

OPENCLAW_PARENT="$(dirname "$OPENCLAW_DIR")"
OPENCLAW_BASE="$(basename "$OPENCLAW_DIR")"

# Set file extension based on compression
case "$COMPRESSION_TYPE" in
    gzip)   TAR_FLAG="-z"; EXT="tar.gz" ;;
    bzip2)  TAR_FLAG="-j"; EXT="tar.bz2" ;;
    xz)     TAR_FLAG="-J"; EXT="tar.xz" ;;
    *)      log_warn "Unknown compression type: ${COMPRESSION_TYPE}. Defaulting to gzip."; TAR_FLAG="-z"; EXT="tar.gz" ;;
esac

# Create backup filename
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
BACKUP_FILENAME="openclaw_blueprints_${TIMESTAMP}.${EXT}"
TEMP_BACKUP_PATH="/tmp/${BACKUP_FILENAME}"
FINAL_BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

log_info "Starting OpenClaw agent and config backup..."
log_info "Source: ${OPENCLAW_DIR}"
log_info "Temporary Output: ${TEMP_BACKUP_PATH}"

# 3. Build Exclusion Flags for tar
# We want to match paths relative to the archive root
TAR_EXCLUDE_FLAGS=()
for pattern in "${EXCLUDES[@]}"; do
    # tar's --exclude is matched against paths inside the archive.
    # Since we are backing up the directory '.openclaw' using `-C /home/developer .openclaw`,
    # the paths inside the archive look like '.openclaw/openclaw.json', '.openclaw/workspace/AGENTS.md', etc.
    # Thus, excluding '.openclaw/pattern' or simply 'pattern' is correct.
    TAR_EXCLUDE_FLAGS+=("--exclude=${OPENCLAW_BASE}/${pattern}")
    # Also add standard wildcards to prevent nested subdirectories from sliding in
    TAR_EXCLUDE_FLAGS+=("--exclude=${pattern}")
done

# 4. Execute Tar archiving
log_info "Bundling files (excluding memory/diaries, logs, and sqlite databases)..."
if tar "$TAR_FLAG" -cf "$TEMP_BACKUP_PATH" -C "$OPENCLAW_PARENT" "${TAR_EXCLUDE_FLAGS[@]}" "$OPENCLAW_BASE"; then
    log_info "Archive created successfully."
else
    log_error "Failed to create archive."
    rm -f "$TEMP_BACKUP_PATH"
    exit 1
fi

# 5. Handle optional encryption
if [[ "${ENCRYPT_BACKUPS}" == "true" ]]; then
    ENCRYPTED_PATH="${FINAL_BACKUP_PATH}.gpg"
    log_info "Encrypting backup archive with GPG..."
    
    if [[ -n "${GPG_PASSPHRASE}" ]]; then
        # Automated symmetric encryption using provided passphrase
        if echo "${GPG_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 -o "$ENCRYPTED_PATH" "$TEMP_BACKUP_PATH"; then
            log_success "Backup encrypted successfully."
            rm -f "$TEMP_BACKUP_PATH"
            FINAL_BACKUP_PATH="$ENCRYPTED_PATH"
        else
            log_error "Encryption failed."
            rm -f "$TEMP_BACKUP_PATH"
            exit 1
        fi
    else
        # Interactive symmetric encryption
        log_warn "No GPG passphrase provided in config. Prompting interactively..."
        if gpg --symmetric --cipher-algo AES256 -o "$ENCRYPTED_PATH" "$TEMP_BACKUP_PATH"; then
            log_success "Backup encrypted successfully."
            rm -f "$TEMP_BACKUP_PATH"
            FINAL_BACKUP_PATH="$ENCRYPTED_PATH"
        else
            log_error "Encryption failed."
            rm -f "$TEMP_BACKUP_PATH"
            exit 1
        fi
    fi
else
    # Simply move the temporary backup to the final destination
    mv "$TEMP_BACKUP_PATH" "$FINAL_BACKUP_PATH"
fi

# 6. Set secure permissions if configured
if [[ "${STRICT_PERMISSIONS}" == "true" ]]; then
    log_info "Applying secure owner-only permissions (chmod 600) to archive..."
    chmod 600 "$FINAL_BACKUP_PATH"
fi

log_success "Backup saved to: ${FINAL_BACKUP_PATH}"
log_info "Backup size: $(du -sh "$FINAL_BACKUP_PATH" | cut -f1)"

# 7. Retention management (Pruning old backups)
log_info "Managing retention (deleting backups older than ${RETENTION_DAYS} days in ${BACKUP_DIR})..."
# Find and delete matching files older than RETENTION_DAYS
# Matches openclaw_blueprints_*.tar.gz or .tar.gz.gpg
find "$BACKUP_DIR" -type f \( -name "openclaw_blueprints_*.*" \) -mtime +"$RETENTION_DAYS" -print -delete | while read -r deleted_file; do
    log_warn "Pruned expired backup file: $(basename "$deleted_file")"
done

log_success "OpenClaw backup routine completed successfully!"
