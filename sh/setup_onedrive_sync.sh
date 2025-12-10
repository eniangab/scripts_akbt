#!/bin/bash

################################################################################
# OneDrive Sync Script for Ubuntu Server
# Purpose: Sync network folder to OneDrive for Business
# Author: Created for sam@akwaserver
# Date: December 9, 2025
################################################################################

# Configuration
SOURCE_FOLDER="/15_office_share_00/DOCUMENTS"
MOUNT_POINT="/15_office_share_00"
NETWORK_SHARE="//192.168.2.18/15_office_share_00"
ONEDRIVE_REMOTE="onedrive-work:DOCUMENTS"
LOG_FILE="/var/log/onedrive_sync.log"
LOCK_FILE="/tmp/onedrive_sync.lock"

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

# Mount network share if not already mounted
mount_network_share() {
    if ! mountpoint -q "$MOUNT_POINT"; then
        log "Mounting network share..."
        sudo mkdir -p "$MOUNT_POINT"
        
        # Mount with CIFS (you may need to adjust credentials)
        sudo mount -t cifs "$NETWORK_SHARE" "$MOUNT_POINT" -o username=guest,vers=3.0
        
        if [ $? -eq 0 ]; then
            success_msg "Network share mounted successfully"
        else
            error_exit "Failed to mount network share"
        fi
    else
        success_msg "Network share already mounted"
    fi
}

# Perform sync
sync_to_onedrive() {
    log "Starting sync from $SOURCE_FOLDER to $ONEDRIVE_REMOTE..."
    
    # Check if source folder exists
    if [ ! -d "$SOURCE_FOLDER" ]; then
        error_exit "Source folder $SOURCE_FOLDER does not exist"
    fi
    
    # Perform sync with rclone
    # --progress for progress indication
    # --update to skip files that are newer on destination
    # --create-empty-src-dirs to create empty directories
    # --delete-after to remove files from OneDrive that don't exist in source (full sync)
    # --log-level INFO for detailed logging
    
    rclone sync "$SOURCE_FOLDER" "$ONEDRIVE_REMOTE" \
        --progress \
        --update \
        --create-empty-src-dirs \
        --delete-after \
        --transfers 4 \
        --checkers 8 \
        --log-file="$LOG_FILE" \
        --log-level INFO
    
    if [ $? -eq 0 ]; then
        success_msg "Sync completed successfully"
    else
        error_exit "Sync failed. Check log file: $LOG_FILE"
    fi
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

# Main menu
show_menu() {
    echo ""
    echo "========================================="
    echo "OneDrive Sync Setup and Management"
    echo "========================================="
    echo "1. Install rclone"
    echo "2. Configure OneDrive remote"
    echo "3. Test OneDrive connection"
    echo "4. Run one-time sync"
    echo "5. Setup automatic sync (cron job)"
    echo "6. View sync logs"
    echo "7. Exit"
    echo "========================================="
    read -p "Choose an option [1-7]: " choice
    
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
            check_lock
            check_rclone
            check_onedrive_config
            mount_network_share
            sync_to_onedrive
            ;;
        5)
            setup_cron
            ;;
        6)
            if [ -f "$LOG_FILE" ]; then
                tail -50 "$LOG_FILE"
            else
                warning_msg "Log file does not exist yet"
            fi
            ;;
        7)
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
    
    log "=== OneDrive Sync Script Started ==="
    
    # Check if running in auto-sync mode (from cron)
    if [[ "$1" == "--auto-sync" ]]; then
        check_lock
        check_rclone
        check_onedrive_config
        mount_network_share
        sync_to_onedrive
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
