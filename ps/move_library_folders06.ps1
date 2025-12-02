# MUST RUN AS ADMINISTRATOR
# This script moves Library folders for multiple user accounts to an external drive

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator!"
    Write-Host "Right-click PowerShell and select 'Run as Administrator', then run this script again."
    pause
    exit
}

# Configuration
$driveRoot = "D:\Users\"
$logFile = "$env:TEMP\move_all_users_folders_log.txt"

# List of folders to move
$folders = @("Documents", "Downloads", "Pictures", "Music", "Videos", "Desktop")

# Map of folder names to their registry keys
$folderMap = @{
    "Desktop" = "Desktop"
    "Documents" = "Personal"
    "Downloads" = "{374DE290-123F-4565-9164-39C4925E467B}"
    "Music" = "My Music"
    "Pictures" = "My Pictures"
    "Videos" = "My Video"
}

# Function to log messages
function Log-Message {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $message"
    Add-Content -Path $logFile -Value $entry
    Write-Host $entry
}

# Function to get all local user accounts (excluding system accounts)
function Get-LocalUserAccounts {
    $users = Get-LocalUser | Where-Object {
        $_.Enabled -eq $true -and
        $_.Name -notmatch '^(Administrator|Guest|DefaultAccount|WDAGUtilityAccount)$'
    }
    return $users
}

# Function to move folders for a specific user
function Move-UserFolders {
    param(
        [string]$username,
        [string]$userProfilePath
    )
    
    Log-Message "=========================================="
    Log-Message "Processing user: $username"
    Log-Message "Profile path: $userProfilePath"
    
    $userDestBase = Join-Path $driveRoot $username
    
    # Load user's registry hive if not current user
    $isCurrentUser = $username -eq $env:USERNAME
    $regPathLoaded = $false
    
    if (-not $isCurrentUser) {
        $ntUserPath = Join-Path $userProfilePath "NTUSER.DAT"
        if (Test-Path $ntUserPath) {
            $tempHive = "HKLM\TempUserHive_$username"
            Log-Message "Loading registry hive from $ntUserPath to $tempHive"
            
            reg load $tempHive $ntUserPath 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $regPathLoaded = $true
                Start-Sleep -Seconds 2
            } else {
                Log-Message "ERROR: Failed to load registry hive for $username"
                return $false
            }
        } else {
            Log-Message "ERROR: NTUSER.DAT not found for $username"
            return $false
        }
    }
    
    try {
        foreach ($folder in $folders) {
            Log-Message "  Processing folder: $folder"
            
            # Determine registry path based on whether hive is loaded
            if ($isCurrentUser) {
                $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
            } else {
                $regPath = "Registry::HKLM\TempUserHive_$username\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
            }
            
            $regKey = $folderMap[$folder]
            
            try {
                # Get current path
                $currentPath = (Get-ItemProperty -Path $regPath -Name $regKey -ErrorAction Stop).$regKey
                # Replace environment variables with the target user's actual paths
                $currentPath = $currentPath -replace '%USERPROFILE%', $userProfilePath
                # Don't use ExpandEnvironmentVariables as it uses current user's environment
                # Instead, manually replace common variables if present
                $currentPath = $currentPath -replace '%USERNAME%', $username
                Log-Message "    Current path: $currentPath"
            } catch {
                Log-Message "    ERROR: Could not read registry for $folder"
                continue
            }
            
            $newPath = Join-Path $userDestBase $folder
            
            # Check if already moved
            if ($currentPath -eq $newPath) {
                Log-Message "    Already points to $newPath - Skipping"
                continue
            }
            
            # Create destination folder
            if (-not (Test-Path $newPath)) {
                New-Item -ItemType Directory -Path $newPath -Force | Out-Null
                Log-Message "    Created: $newPath"
            }
            
            # Copy files using robocopy (without /COPYALL to avoid permission issues)
            if (Test-Path $currentPath) {
                Log-Message "    Copying files from $currentPath to $newPath"
                $robocopyLog = "$env:TEMP\robocopy_${username}_${folder}_log.txt"
                
                # Using /COPY:DAT instead of /COPYALL to avoid audit info issues
                robocopy "$currentPath" "$newPath" /E /COPY:DAT /R:3 /W:5 /LOG:"$robocopyLog" /NP | Out-Null
                
                $exitCode = $LASTEXITCODE
                Log-Message "    Robocopy exit code: $exitCode"
                
                if ($exitCode -ge 8) {
                    Log-Message "    ERROR: Robocopy failed - Check log: $robocopyLog"
                    continue
                }
            } else {
                Log-Message "    Source path does not exist: $currentPath"
            }
            
            # Update registry
            try {
                Set-ItemProperty -Path $regPath -Name $regKey -Value $newPath -Type ExpandString -Force
                Log-Message "    Updated registry to: $newPath"
            } catch {
                Log-Message "    ERROR: Failed to update registry - $_"
                continue
            }
        }
    } finally {
        # Unload registry hive if we loaded it
        if ($regPathLoaded) {
            Log-Message "Unloading registry hive for $username"
            [gc]::Collect()
            Start-Sleep -Seconds 2
            reg unload "HKLM\TempUserHive_$username" 2>&1 | Out-Null
        }
    }
    
    Log-Message "Completed processing for $username"
    return $true
}

# Main script execution
Clear-Host
Log-Message "=========================================="
Log-Message "Starting Multi-User Library Folder Move Script"
Log-Message "Target drive: $driveRoot"
Log-Message "=========================================="

# Get all local user accounts
$localUsers = Get-LocalUserAccounts

Write-Host "`nFound the following local user accounts:"
foreach ($user in $localUsers) {
    Write-Host "  - $($user.Name)"
}

Write-Host "`nWhich users would you like to process?"
Write-Host "1. All users listed above"
Write-Host "2. Select specific users"
Write-Host "3. Cancel"
$choice = Read-Host "`nEnter your choice (1-3)"

$usersToProcess = @()

switch ($choice) {
    "1" {
        $usersToProcess = $localUsers
    }
    "2" {
        foreach ($user in $localUsers) {
            $process = Read-Host "Process user '$($user.Name)'? (Y/N)"
            if ($process -eq "Y" -or $process -eq "y") {
                $usersToProcess += $user
            }
        }
    }
    "3" {
        Write-Host "Operation cancelled."
        exit
    }
    default {
        Write-Host "Invalid choice. Exiting."
        exit
    }
}

if ($usersToProcess.Count -eq 0) {
    Write-Host "No users selected. Exiting."
    exit
}

Write-Host "`nWill process the following users:"
foreach ($user in $usersToProcess) {
    Write-Host "  - $($user.Name)"
}

$confirm = Read-Host "`nContinue? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Operation cancelled."
    exit
}

# Process each selected user
foreach ($user in $usersToProcess) {
    $username = $user.Name
    $userProfilePath = "C:\Users\$username"
    
    if (-not (Test-Path $userProfilePath)) {
        Log-Message "Profile path not found for $username, skipping..."
        continue
    }
    
    $success = Move-UserFolders -username $username -userProfilePath $userProfilePath
    
    if (-not $success) {
        Log-Message "Failed to complete processing for $username"
    }
}

Log-Message "=========================================="
Log-Message "All user processing completed!"
Log-Message "Log file: $logFile"
Log-Message "=========================================="

Write-Host "`n✅ Process completed. Check log file: $logFile"
Write-Host "⚠️  IMPORTANT: Each user should log off and back on for changes to take full effect."
Write-Host "⚠️  Verify all files are accessible in F:\{username} folders before deleting originals."
Write-Host "`nPress any key to exit..."
pause