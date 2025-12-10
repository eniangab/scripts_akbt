# OneDrive Sync Script for Ubuntu Server

This script synchronizes a network folder from `\\192.168.2.18\15_office_share_00\DOCUMENTS` to your OneDrive for Business account.

## Prerequisites

- Ubuntu Server with network access
- SSH access to the server (sam@akwaserve -p 2305)
- OneDrive for Business account credentials
- Network share accessible from the Ubuntu server

## Quick Start

### 1. Upload Script to Server

```bash
# From your local machine
scp -P 2305 setup_onedrive_sync.sh sam@akwaserve:~/
```

### 2. SSH to Server

```bash
ssh sam@akwaserve -p 2305
```

### 3. Make Script Executable

```bash
chmod +x ~/setup_onedrive_sync.sh
```

### 4. Run Setup

```bash
./setup_onedrive_sync.sh
```

## Setup Steps

### Step 1: Install rclone

From the menu, choose option **1** to install rclone:
- This will download and install the latest version of rclone
- rclone is the tool that handles the OneDrive synchronization

### Step 2: Configure OneDrive Remote

From the menu, choose option **2** to configure OneDrive:

1. When prompted, enter remote name: `onedrive-work`
2. Choose storage type: Look for **Microsoft OneDrive** (usually option 31)
3. Client ID: Press Enter (leave blank)
4. Client Secret: Press Enter (leave blank)
5. Region: Choose **Microsoft Cloud Global** (option 1)
6. Edit advanced config: `n` (No)
7. Use auto config: **Important Note Below**
8. Choose account type: **OneDrive for Business** (option 2)
9. Your browser will open for authentication
10. Log in with your OneDrive credentials: `alexw@8bwhhg.onmicrosoft.com`
11. Grant permissions
12. Return to terminal and confirm

#### Important: Auto Config on Headless Server

If your Ubuntu server doesn't have a desktop environment (headless server), you'll need to use remote config:

1. When asked "Use auto config?", answer `n` (No)
2. rclone will provide a command to run on a machine with a web browser
3. On your **local Windows machine**, run:
   ```powershell
   rclone authorize "onedrive"
   ```
4. A browser window will open - log in to your OneDrive account
5. Copy the resulting token from the terminal
6. Paste it back into the SSH session on your server

### Step 3: Test Connection

From the menu, choose option **3** to test the OneDrive connection:
- This will list your OneDrive folders
- Verify you can see your shared folder

### Step 4: Configure Network Share Mount

Before running sync, you may need to configure the network share credentials:

```bash
# Install CIFS utilities if not already installed
sudo apt-get update
sudo apt-get install cifs-utils

# Create credentials file for security
sudo nano /etc/cifscredentials
```

Add the following content (replace with actual credentials):
```
username=your_network_username
password=your_network_password
domain=WORKGROUP
```

Save and secure the file:
```bash
sudo chmod 600 /etc/cifscredentials
```

### Step 5: Edit Script for Credentials

If you created credentials file, edit the mount command in the script:

```bash
nano ~/setup_onedrive_sync.sh
```

Find the `mount_network_share()` function and update:
```bash
sudo mount -t cifs "$NETWORK_SHARE" "$MOUNT_POINT" -o credentials=/etc/cifscredentials,vers=3.0
```

### Step 6: Run One-Time Sync

From the menu, choose option **4** to run a manual sync:
- This will mount the network share
- Sync all files to OneDrive
- Show progress and completion status

### Step 7: Setup Automatic Sync (Optional)

From the menu, choose option **5** to setup a cron job:
- Choose how often to sync (hourly, every 6 hours, daily, or custom)
- The script will automatically run at the scheduled time

## Understanding the Sync Process

### What the Script Does

1. **Mounts Network Share**: Connects to `\\192.168.2.18\15_office_share_00`
2. **Checks Configuration**: Verifies rclone and OneDrive are configured
3. **Syncs Files**: Uses rclone to sync DOCUMENTS folder to OneDrive
4. **Logs Activity**: Writes detailed logs to `/var/log/onedrive_sync.log`

### Sync Behavior

- **Direction**: One-way sync from network share → OneDrive
- **Updates**: Only uploads newer files (won't overwrite newer OneDrive files)
- **Deletions**: Files deleted from source will NOT be deleted from OneDrive (safe sync)
- **New Files**: All new files in source are uploaded to OneDrive

### OneDrive Folder Structure

Your files will appear in OneDrive at:
```
OneDrive for Business
└── DOCUMENTS/
    └── [your files from network share]
```

You can access them at: https://8bwhhg-my.sharepoint.com/

## Menu Options Explained

1. **Install rclone**: Downloads and installs rclone tool
2. **Configure OneDrive remote**: Sets up connection to your OneDrive account
3. **Test OneDrive connection**: Verifies the configuration works
4. **Run one-time sync**: Performs immediate sync
5. **Setup automatic sync**: Creates scheduled sync job
6. **View sync logs**: Shows recent sync activity
7. **Exit**: Closes the script

## Viewing Logs

### View Recent Logs
From the menu, choose option **6**, or manually:
```bash
tail -f /var/log/onedrive_sync.log
```

### View Full Log
```bash
less /var/log/onedrive_sync.log
```

## Troubleshooting

### Network Share Won't Mount

**Issue**: Cannot mount `\\192.168.2.18\15_office_share_00`

**Solutions**:
```bash
# Test network connectivity
ping 192.168.2.18

# Test SMB connection
sudo apt-get install smbclient
smbclient -L //192.168.2.18

# Check if share is accessible
sudo mount -t cifs //192.168.2.18/15_office_share_00 /mnt/test -o username=guest
```

### OneDrive Authentication Issues

**Issue**: Cannot authenticate with OneDrive

**Solutions**:
- Use remote config method (run `rclone authorize` on local machine)
- Check your OneDrive credentials
- Verify you're using OneDrive for **Business**, not Personal
- Ensure your organization allows third-party apps

### Sync Running Slowly

**Issue**: Sync takes too long

**Solutions**:
- Check network bandwidth
- Adjust transfer settings in script:
  ```bash
  --transfers 8    # Increase parallel transfers (default: 4)
  --checkers 16    # Increase parallel checks (default: 8)
  ```

### Permission Denied

**Issue**: Cannot write to log file or mount point

**Solutions**:
```bash
# Fix log file permissions
sudo chown sam:sam /var/log/onedrive_sync.log

# Fix mount point
sudo mkdir -p /mnt/office_share
sudo chown sam:sam /mnt/office_share
```

## Advanced Configuration

### Exclude Certain Files

Edit the script and add to the `sync_to_onedrive()` function:

```bash
rclone sync "$SOURCE_FOLDER" "$ONEDRIVE_REMOTE" \
    --exclude "*.tmp" \
    --exclude "*.bak" \
    --exclude "Thumbs.db" \
    --progress \
    ...
```

### Change Sync Direction (Two-Way Sync)

**Warning**: This can lead to file conflicts

Replace `rclone sync` with `rclone bisync`:
```bash
rclone bisync "$SOURCE_FOLDER" "$ONEDRIVE_REMOTE" \
    --resync \
    --progress
```

### Email Notifications

Install mail utilities:
```bash
sudo apt-get install mailutils
```

Add to script after sync:
```bash
echo "Sync completed at $(date)" | mail -s "OneDrive Sync Complete" your@email.com
```

## Uninstalling

### Remove Cron Job
```bash
crontab -e
# Delete the line containing onedrive-sync-cron.sh
```

### Remove Files
```bash
rm ~/setup_onedrive_sync.sh
sudo rm /usr/local/bin/onedrive-sync-cron.sh
sudo rm /var/log/onedrive_sync.log
```

### Remove rclone Configuration
```bash
rclone config delete onedrive-work
```

## Security Considerations

1. **Credentials**: Store network credentials in `/etc/cifscredentials` with 600 permissions
2. **Logs**: Logs may contain file names - ensure `/var/log/onedrive_sync.log` has appropriate permissions
3. **Lock File**: Prevents multiple sync processes from running simultaneously
4. **OneDrive Token**: rclone stores encrypted tokens in `~/.config/rclone/rclone.conf`

## Support & Additional Information

- **rclone Documentation**: https://rclone.org/onedrive/
- **OneDrive for Business**: https://www.microsoft.com/en-us/microsoft-365/onedrive/onedrive-for-business
- **Script Location**: `~/setup_onedrive_sync.sh`
- **Log Location**: `/var/log/onedrive_sync.log`

## Configuration Summary

- **Source**: `\\192.168.2.18\15_office_share_00\DOCUMENTS`
- **Destination**: OneDrive for Business (alexw@8bwhhg.onmicrosoft.com)
- **Server**: sam@akwaserve:2305
- **Mount Point**: `/mnt/office_share`
- **Sync Tool**: rclone
