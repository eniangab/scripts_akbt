# Parkwood Guestbook Backup and Reset Script
# Runs every Sunday at 7PM to archive current data and reset for new week

param(
    [string]$LogFile = "C:\Logs\guestbook-backup.log"
)

# Create log directory if it doesn't exist
$logDir = Split-Path $LogFile -Parent
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Function to write to log file with timestamp
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry
    Add-Content -Path $LogFile -Value $logEntry
}

try {
    Write-Log "Starting Parkwood Guestbook backup and reset process"
    
    # Define paths
    $baseBackupPath = "\\pnas4\pshare4_backup"
    $archivePath = "$baseBackupPath\gb-archive"
    $uploadsPath = "$baseBackupPath\uploads"
    $guestsCsvPath = "$baseBackupPath\guests.csv"
    $templateCsvPath = "$baseBackupPath\_guests.csv"
    
    # Create datetime stamp for folder name
    $dateStamp = Get-Date -Format "yyyyMMdd-HHmm"
    $archiveFolder = Join-Path $archivePath $dateStamp
    
    Write-Log "Archive folder will be: $archiveFolder"
    
    # Step 1: Create archive folder with datetime stamp
    Write-Log "Step 1: Creating archive folder"
    if (!(Test-Path $archivePath)) {
        New-Item -ItemType Directory -Path $archivePath -Force | Out-Null
        Write-Log "Created base archive directory: $archivePath"
    }
    
    New-Item -ItemType Directory -Path $archiveFolder -Force | Out-Null
    Write-Log "Created archive folder: $archiveFolder"
    
    # Step 2: Move all files from uploads folder to archive folder
    Write-Log "Step 2: Moving upload files to archive"
    if (Test-Path $uploadsPath) {
        $uploadFiles = Get-ChildItem -Path $uploadsPath -File
        if ($uploadFiles.Count -gt 0) {
            foreach ($file in $uploadFiles) {
                $destination = Join-Path $archiveFolder $file.Name
                Move-Item -Path $file.FullName -Destination $destination
                Write-Log "Moved file: $($file.Name)"
            }
            Write-Log "Moved $($uploadFiles.Count) files from uploads folder"
        } else {
            Write-Log "No files found in uploads folder"
        }
    } else {
        Write-Log "Uploads folder not found: $uploadsPath" -Level "WARNING"
    }
    
    # Steps 3 & 4: Move and rename guests.csv to archive folder
    Write-Log "Steps 3-4: Moving and renaming guests.csv to archive"
    if (Test-Path $guestsCsvPath) {
        $archivedGuestsCsv = Join-Path $archiveFolder "guests_$dateStamp.csv"
        Move-Item -Path $guestsCsvPath -Destination $archivedGuestsCsv
        Write-Log "Moved and renamed guests.csv to: guests_$dateStamp.csv"
    } else {
        Write-Log "guests.csv not found: $guestsCsvPath" -Level "WARNING"
    }
    
    # Steps 5 & 6: Copy template file and rename to guests.csv
    Write-Log "Steps 5-6: Creating new guests.csv from template"
    if (Test-Path $templateCsvPath) {
        Copy-Item -Path $templateCsvPath -Destination $guestsCsvPath
        Write-Log "Created new guests.csv from template"
    } else {
        Write-Log "Template file not found: $templateCsvPath" -Level "ERROR"
        throw "Template file _guests.csv not found. Cannot create new guests.csv file."
    }
    
    # Verify the new guests.csv file was created
    if (Test-Path $guestsCsvPath) {
        $fileSize = (Get-Item $guestsCsvPath).Length
        Write-Log "New guests.csv created successfully (Size: $fileSize bytes)"
    } else {
        Write-Log "Failed to create new guests.csv file" -Level "ERROR"
        throw "New guests.csv file was not created successfully"
    }
    
    Write-Log "Backup and reset process completed successfully"
    Write-Log "Archive folder: $archiveFolder"
    
    # Summary of what was archived
    $archivedItems = Get-ChildItem -Path $archiveFolder
    Write-Log "Archived items ($($archivedItems.Count)):"
    foreach ($item in $archivedItems) {
        Write-Log "  - $($item.Name) ($($item.Length) bytes)"
    }
    
} catch {
    Write-Log "Error occurred: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
}

Write-Log "Script execution completed"