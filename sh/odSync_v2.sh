#!/bin/bash

################################################################################
# OneDrive Multi-Folder Sync Script for Ubuntu Server
# Purpose: Sync multiple folders to OneDrive for Business
# Author: Created for sam@akwaserver
# Date: December 10, 2025
################################################################################

# Configuration File
SYNC_CONFIG="/etc/onedrive_sync_folders.conf"
LOG_FILE="/var/log/onedrive_sync.log"
LOCK_FILE="/tmp/onedrive_sync.lock"
ONEDRIVE_REMOTE_BASE="onedrive-work"

# Sync folder definitions (if config file doesn't exist)
# Format: SOURCE_PATH|ONEDRIVE_PATH|MOUNT_POINT|NETWORK_SHARE
DEFAULT_FOLDERS=(
    "/15_office_share_00/DOCUMENTS|DOCUMENTS|/15_office_share_00|//192.168.2.18/15_office_share_00"
    "/13_media_share_00/MUSIC/GHM|GHM|/13_media_share_00|//192.168.2.18/13_media_share_00"
    "/13_media_share_00/MUSIC/ZEN|ZEN|/13_media_share_00|//192.168.2.18/13_media_share_00"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

# Success message
success_msg() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Warning message
warning_msg() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Check if script is already running
check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        PID=$(cat "$LOCK_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            error_exit "Sync script is already running (PID: $PID)"
        else
            warning_msg "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

# Remove lock file on exit
cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# Check if rclone is installed
check_rclone() {
    if ! command -v rclone &> /dev/null; then
        error_exit "rclone is not installed. Please run the installation first."
    fi
    success_msg "rclone is installed"
}

# Check if OneDrive remote is configured
check_onedrive_config() {
    if ! rclone listremotes | grep -q "onedrive-work:"; then
        error_exit "OneDrive remote 'onedrive-work' is not configured. Please run the configuration first."
    fi
    success_msg "OneDrive remote is configured"
}

# Load sync folders from config file or use defaults
load_sync_folders() {
    if [ -f "$SYNC_CONFIG" ]; then
        mapfile -t SYNC_FOLDERS < "$SYNC_CONFIG"
        log "Loaded ${#SYNC_FOLDERS[@]} folders from $SYNC_CONFIG"
    else
        SYNC_FOLDERS=("${DEFAULT_FOLDERS[@]}")
        log "Using default folder configuration (${#SYNC_FOLDERS[@]} folders)"
    fi
}

# Save sync folders to config file
save_sync_folders() {
    sudo mkdir -p "$(dirname "$SYNC_CONFIG")"
    printf '%s\n' "${SYNC_FOLDERS[@]}" | sudo tee "$SYNC_CONFIG" > /dev/null
    sudo chmod 644 "$SYNC_CONFIG"
    success_msg "Saved configuration to $SYNC_CONFIG"
}

# Mount network share if not already mounted
mount_network_share() {
    local mount_point="$1"
    local network_share="$2"
    
    if ! mountpoint -q "$mount_point"; then
        log "Mounting $network_share to $mount_point..."
        sudo mkdir -p "$mount_point"
        
        # Check if it's already mounted as a local drive
        if mount | grep -q "$mount_point"; then
            success_msg "$mount_point is already mounted"
            return 0
        fi
        
        # Mount with CIFS (you may need to adjust credentials)
        sudo mount -t cifs "$network_share" "$mount_point" -o username=guest,vers=3.0
        
        if [ $? -eq 0 ]; then
            success_msg "Network share mounted successfully"
        else
            warning_msg "Failed to mount network share (may already be mounted)"
        fi
    else
        success_msg "Mount point already exists: $mount_point"
    fi
}

# Perform sync for a single folder
sync_folder_to_onedrive() {
    local source_folder="$1"
    local onedrive_path="$2"
    local onedrive_remote="${ONEDRIVE_REMOTE_BASE}:${onedrive_path}"
    
    log "Starting sync: $source_folder -> $onedrive_remote"
    
    # Check if source folder exists
    if [ ! -d "$source_folder" ]; then
        warning_msg "Source folder $source_folder does not exist - skipping"
        return 1
    fi
    
    # Perform 2-way sync with rclone bisync
    # Note: Files are synced bidirectionally between local and OneDrive
    log "2-way syncing: $source_folder <-> $onedrive_remote"
    
    # Check if bisync state exists - if not, need to initialize with --resync
    BISYNC_STATE_DIR="$HOME/.cache/rclone/bisync"
    BISYNC_STATE_FILE="$BISYNC_STATE_DIR/$(echo "$onedrive_remote" | sed 's/[^a-zA-Z0-9]/_/g').lst"
    
    if [ ! -f "$BISYNC_STATE_FILE" ]; then
        warning_msg "First time sync - initializing bisync for $onedrive_path"
        rclone bisync "$source_folder" "$onedrive_remote" \
            --create-empty-src-dirs \
            --transfers 4 \
            --checkers 8 \
            --log-file="$LOG_FILE" \
            --log-level INFO \
            --resync
        
        if [ $? -eq 0 ]; then
            success_msg "Bisync initialized: $onedrive_path"
            return 0
        else
            error_exit "Bisync initialization failed for $onedrive_path. Check log file: $LOG_FILE"
            return 1
        fi
    else
        # Regular 2-way sync
        rclone bisync "$source_folder" "$onedrive_remote" \
            --create-empty-src-dirs \
            --transfers 4 \
            --checkers 8 \
            --log-file="$LOG_FILE" \
            --log-level INFO \
            --resilient \
            --recover \
            --conflict-resolve newer \
            --conflict-loser num
        
        if [ $? -eq 0 ]; then
            success_msg "2-way sync completed: $onedrive_path"
            return 0
        else
            error_exit "2-way sync failed for $onedrive_path. Check log file: $LOG_FILE"
            return 1
        fi
    fi
}

# Sync all configured folders
sync_all_folders() {
    load_sync_folders
    
    local total=${#SYNC_FOLDERS[@]}
    local current=0
    local success_count=0
    local fail_count=0
    
    log "=== Starting sync of $total folder(s) ==="
    
    for folder_config in "${SYNC_FOLDERS[@]}"; do
        ((current++))
        
        # Skip empty lines or comments
        [[ -z "$folder_config" || "$folder_config" =~ ^# ]] && continue
        
        # Parse the configuration
        IFS='|' read -r source_path onedrive_path mount_point network_share <<< "$folder_config"
        
        log "[$current/$total] Processing: $source_path"
        
        # Mount if needed
        if [ -n "$mount_point" ] && [ -n "$network_share" ]; then
            mount_network_share "$mount_point" "$network_share"
        fi
        
        # Sync the folder
        if sync_folder_to_onedrive "$source_path" "$onedrive_path"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
        
        echo ""
    done
    
    log "=== Sync Summary: $success_count succeeded, $fail_count failed ==="
}

# Install rclone if needed
install_rclone() {
    log "Installing rclone..."
    curl https://rclone.org/install.sh | sudo bash
    
    if [ $? -eq 0 ]; then
        success_msg "rclone installed successfully"
    else
        error_exit "Failed to install rclone"
    fi
}

# Configure OneDrive
configure_onedrive() {
    log "Configuring OneDrive for Business..."
    echo ""
    echo "Follow these steps to configure OneDrive:"
    echo "1. Enter remote name: onedrive-work"
    echo "2. Choose storage type: Microsoft OneDrive (option 31 or search for 'onedrive')"
    echo "3. Leave client_id blank (press Enter)"
    echo "4. Leave client_secret blank (press Enter)"
    echo "5. Choose region: Microsoft Cloud Global (option 1)"
    echo "6. Edit advanced config: No (n)"
    echo "7. Use auto config: Yes (y) - this will open a browser"
    echo "8. Choose account type: OneDrive for Business (option 2)"
    echo "9. Select your drive"
    echo "10. Confirm and save"
    echo ""
    read -p "Press Enter to continue with configuration..."
    
    rclone config
}

# Manage sync folders
manage_folders() {
    load_sync_folders
    
    while true; do
        echo ""
        echo "========================================="
        echo "Manage Sync Folders"
        echo "========================================="
        echo "Current folders:"
        echo ""
        
        local index=1
        for folder_config in "${SYNC_FOLDERS[@]}"; do
            [[ -z "$folder_config" || "$folder_config" =~ ^# ]] && continue
            IFS='|' read -r source_path onedrive_path _ _ <<< "$folder_config"
            echo "$index. $source_path -> OneDrive:/$onedrive_path"
            ((index++))
        done
        
        echo ""
        echo "Actions:"
        echo "a. Add new folder"
        echo "d. Delete folder"
        echo "b. Back to main menu"
        echo "========================================="
        read -p "Choose an action: " action
        
        case $action in
            a|A)
                add_sync_folder
                ;;
            d|D)
                delete_sync_folder
                ;;
            b|B)
                return
                ;;
            *)
                warning_msg "Invalid option"
                ;;
        esac
    done
}

# Add a new sync folder
add_sync_folder() {
    echo ""
    echo "=== Add New Sync Folder ==="
    echo ""
    read -p "Enter source folder path (e.g., /13_media_share_00/MUSIC/GHM): " source_path
    read -p "Enter OneDrive destination folder name (e.g., GHM): " onedrive_path
    read -p "Enter mount point (e.g., /13_media_share_00) or leave blank: " mount_point
    read -p "Enter network share (e.g., //192.168.2.18/13_media_share_00) or leave blank: " network_share
    
    # Validate source path
    if [ ! -d "$source_path" ]; then
        warning_msg "Warning: Source folder $source_path does not exist"
        read -p "Add anyway? (y/n): " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    fi
    
    # Add to array
    local new_entry="${source_path}|${onedrive_path}|${mount_point}|${network_share}"
    SYNC_FOLDERS+=("$new_entry")
    
    # Save configuration
    save_sync_folders
    success_msg "Added: $source_path -> OneDrive:/$onedrive_path"
}

# Delete a sync folder
delete_sync_folder() {
    load_sync_folders
    
    echo ""
    echo "=== Delete Sync Folder ==="
    echo ""
    
    local index=1
    local valid_indices=()
    
    for i in "${!SYNC_FOLDERS[@]}"; do
        folder_config="${SYNC_FOLDERS[$i]}"
        [[ -z "$folder_config" || "$folder_config" =~ ^# ]] && continue
        IFS='|' read -r source_path onedrive_path _ _ <<< "$folder_config"
        echo "$index. $source_path -> OneDrive:/$onedrive_path"
        valid_indices+=("$i")
        ((index++))
    done
    
    echo ""
    read -p "Enter number to delete (or 'c' to cancel): " choice
    
    [[ "$choice" =~ ^[Cc]$ ]] && return
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$index" ]; then
        local array_index=${valid_indices[$((choice-1))]}
        unset 'SYNC_FOLDERS[$array_index]'
        SYNC_FOLDERS=("${SYNC_FOLDERS[@]}") # Re-index array
        save_sync_folders
        success_msg "Folder removed"
    else
        error_exit "Invalid selection"
    fi
}

# Main menu
show_menu() {
    echo ""
    echo "========================================="
    echo "OneDrive Multi-Folder Sync Management"
    echo "========================================="
    echo "1. Install rclone"
    echo "2. Configure OneDrive remote"
    echo "3. Test OneDrive connection"
    echo "4. Manage sync folders"
    echo "5. Run one-time sync (all folders)"
    echo "6. Setup automatic sync (cron job)"
    echo "7. View sync logs"
    echo "8. Exit"
    echo "========================================="
    read -p "Choose an option [1-8]: " choice
    
    case $choice in
        1)
            install_rclone
            ;;
        2)
            configure_onedrive
            ;;
        3)
            check_rclone
            check_onedrive_config
            log "Testing OneDrive connection..."
            rclone lsd onedrive-work:
            ;;
        4)
            manage_folders
            ;;
        5)
            check_lock
            check_rclone
            check_onedrive_config
            sync_all_folders
            ;;
        6)
            setup_cron
            ;;
        7)
            if [ -f "$LOG_FILE" ]; then
                tail -50 "$LOG_FILE"
            else
                warning_msg "Log file does not exist yet"
            fi
            ;;
        8)
            log "Exiting..."
            exit 0
            ;;
        *)
            error_exit "Invalid option"
            ;;
    esac
}

# Setup cron job for automatic sync
setup_cron() {
    log "Setting up automatic sync with cron..."
    
    # Get the full path to this script
    SCRIPT_PATH=$(readlink -f "$0")
    
    echo ""
    echo "Choose sync frequency:"
    echo "1. Every hour"
    echo "2. Every 6 hours"
    echo "3. Daily at 2 AM"
    echo "4. Custom"
    read -p "Choose [1-4]: " freq_choice
    
    case $freq_choice in
        1)
            CRON_SCHEDULE="0 * * * *"
            ;;
        2)
            CRON_SCHEDULE="0 */6 * * *"
            ;;
        3)
            CRON_SCHEDULE="0 2 * * *"
            ;;
        4)
            read -p "Enter cron schedule (e.g., '0 2 * * *' for daily at 2 AM): " CRON_SCHEDULE
            ;;
        *)
            error_exit "Invalid option"
            ;;
    esac
    
    # Create a wrapper script for cron that just runs the sync
    CRON_WRAPPER="/usr/local/bin/onedrive-sync-cron.sh"
    
    sudo tee "$CRON_WRAPPER" > /dev/null <<EOF
#!/bin/bash
# Auto-generated cron wrapper for OneDrive sync
export PATH=/usr/local/bin:/usr/bin:/bin
cd "$(dirname "$SCRIPT_PATH")"
"$SCRIPT_PATH" --auto-sync >> "$LOG_FILE" 2>&1
EOF
    
    sudo chmod +x "$CRON_WRAPPER"
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "$CRON_WRAPPER"; echo "$CRON_SCHEDULE $CRON_WRAPPER") | crontab -
    
    success_msg "Cron job installed: $CRON_SCHEDULE"
    log "Automatic sync will run with schedule: $CRON_SCHEDULE"
}

# Main execution
main() {
    # Create log directory if it doesn't exist
    sudo mkdir -p "$(dirname "$LOG_FILE")"
    sudo touch "$LOG_FILE"
    sudo chmod 666 "$LOG_FILE"
    
    log "=== OneDrive Multi-Folder Sync Script Started ==="
    
    # Check if running in auto-sync mode (from cron)
    if [[ "$1" == "--auto-sync" ]]; then
        check_lock
        check_rclone
        check_onedrive_config
        sync_all_folders
    else
        # Interactive mode
        while true; do
            show_menu
            echo ""
            read -p "Press Enter to continue..."
        done
    fi
}

# Run main function
main "$@"