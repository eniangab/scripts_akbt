# Script to create scheduled task for Parkwood Guestbook backup
# Run this script as Administrator to create the scheduled task

param(
    [string]$ScriptPath = "C:\Scripts\backup-and-reset-guests.ps1",
    [string]$LogPath = "C:\Logs\guestbook-backup.log"
)

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator', then run this script again." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

try {
    Write-Host "Creating Parkwood Guestbook Backup Scheduled Task..." -ForegroundColor Green
    
    # Create directories if they don't exist
    $scriptDir = Split-Path $ScriptPath -Parent
    $logDir = Split-Path $LogPath -Parent
    
    if (!(Test-Path $scriptDir)) {
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
        Write-Host "Created script directory: $scriptDir" -ForegroundColor Yellow
    }
    
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Write-Host "Created log directory: $logDir" -ForegroundColor Yellow
    }
    
    # Copy the backup script to the target location if it doesn't exist there
    $currentScriptLocation = Join-Path $PSScriptRoot "backup-and-reset-guests.ps1"
    if ((Test-Path $currentScriptLocation) -and !(Test-Path $ScriptPath)) {
        Copy-Item -Path $currentScriptLocation -Destination $ScriptPath -Force
        Write-Host "Copied backup script to: $ScriptPath" -ForegroundColor Yellow
    }
    
    # Define task properties
    $taskName = "Parkwood Guestbook Weekly Backup"
    $taskDescription = "Weekly backup and reset of Parkwood Church guestbook data. Runs every Sunday at 7:00 PM."
    
    # Create the scheduled task action
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" -LogFile `"$LogPath`""
    
    # Create the scheduled task trigger (Every Sunday at 7:00 PM)
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "19:00"
    
    # Create task settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -WakeToRun -ExecutionTimeLimit (New-TimeSpan -Hours 2) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)
    
    # Create principal (run as SYSTEM with highest privileges)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    # Remove existing task if it exists
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "Removing existing scheduled task..." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    
    # Register the scheduled task
    Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $action -Trigger $trigger -Settings $settings -Principal $principal
    
    Write-Host "`nScheduled task created successfully!" -ForegroundColor Green
    Write-Host "`nTask Details:" -ForegroundColor Cyan
    Write-Host "  Name: $taskName"
    Write-Host "  Schedule: Every Sunday at 7:00 PM"
    Write-Host "  Script Path: $ScriptPath"
    Write-Host "  Log Path: $LogPath"
    Write-Host "  Wake Computer: Yes"
    Write-Host "  Run as: SYSTEM account"
    
    # Show the task in Task Scheduler
    Write-Host "`nTask has been created and can be viewed in Task Scheduler." -ForegroundColor Green
    Write-Host "You can also run it manually by executing:" -ForegroundColor Yellow
    Write-Host "  Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor White
    
    # Test network connectivity to backup location
    Write-Host "`nTesting network connectivity to backup location..." -ForegroundColor Cyan
    $backupPath = "\\pnas4\pshare4_backup"
    
    if (Test-Path $backupPath) {
        Write-Host "Successfully connected to backup location: $backupPath" -ForegroundColor Green
    } else {
        Write-Host "Warning: Cannot access backup location: $backupPath" -ForegroundColor Red
        Write-Host "  Make sure:" -ForegroundColor Yellow
        Write-Host "  - Network share is accessible"
        Write-Host "  - SYSTEM account has permissions to the share"
        Write-Host "  - You may need to run the task under a domain account with network access"
    }
    
    # Offer to run a test
    Write-Host "`nWould you like to run a test of the backup script now? (Y/N): " -ForegroundColor Cyan -NoNewline
    $response = Read-Host
    
    if ($response -match '^[Yy]') {
        Write-Host "`nRunning test backup..." -ForegroundColor Yellow
        try {
            & $ScriptPath -LogFile $LogPath
            Write-Host "Test completed. Check the log file for details: $LogPath" -ForegroundColor Green
        } catch {
            Write-Host "Test failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
} catch {
    Write-Host "Error creating scheduled task: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}

Write-Host "`nSetup completed successfully!" -ForegroundColor Green
Read-Host "`nPress Enter to exit"