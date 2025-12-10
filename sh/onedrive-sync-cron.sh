#!/bin/bash
# Cron wrapper for OneDrive multi-folder sync
# Schedule: Daily at 2:00 AM
# Cron entry: 0 2 * * * /home/sam/onedrive-sync-cron.sh

export PATH=/usr/local/bin:/usr/bin:/bin
cd "/home/sam"
"/home/sam/setup_onedrive_sync_multi_folders.sh" --auto-sync >> "/var/log/onedrive_sync.log" 2>&1

# run one time sync without cron
# echo "/home/sam/setup_onedrive_sync_multi_folders.sh --auto-sync >> /var/log/onedrive_sync.log 2>&1" | at 13:35
