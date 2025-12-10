# MUST RUN AS ADMINISTRATOR
# This script resets Library folder registry entries back to C:\Users locations

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator!"
    pause
    exit
}

$users = @("Admin", "Chuwin", "Office")

# Map of folder names to their registry keys
$folderMap = @{
    "Desktop" = "Desktop"
    "Documents" = "Personal"
    "Downloads" = "{374DE290-123F-4565-9164-39C4925E467B}"
    "Music" = "My Music"
    "Pictures" = "My Pictures"
    "Videos" = "My Video"
}

foreach ($username in $users) {
    Write-Host "`nProcessing user: $username"
    $userProfilePath = "C:\Users\$username"
    
    if (-not (Test-Path $userProfilePath)) {
        Write-Host "  Profile path not found, skipping..."
        continue
    }
    
    # Load user's registry hive if not current user
    $isCurrentUser = $username -eq $env:USERNAME
    $regPathLoaded = $false
    
    if (-not $isCurrentUser) {
        $ntUserPath = Join-Path $userProfilePath "NTUSER.DAT"
        if (Test-Path $ntUserPath) {
            $tempHive = "HKLM\TempUserHive_$username"
            Write-Host "  Loading registry hive..."
            
            reg load $tempHive $ntUserPath 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $regPathLoaded = $true
                Start-Sleep -Seconds 2
            } else {
                Write-Host "  ERROR: Failed to load registry hive"
                continue
            }
        } else {
            Write-Host "  ERROR: NTUSER.DAT not found"
            continue
        }
    }
    
    try {
        # Determine registry path
        if ($isCurrentUser) {
            $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
        } else {
            $regPath = "Registry::HKLM\TempUserHive_$username\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
        }
        
        foreach ($folder in $folderMap.Keys) {
            $regKey = $folderMap[$folder]
            # Use absolute path instead of %USERPROFILE% to avoid expansion issues
            $originalPath = "$userProfilePath\$folder"
            
            try {
                Set-ItemProperty -Path $regPath -Name $regKey -Value $originalPath -Type ExpandString -Force
                Write-Host "  Reset $folder to $originalPath"
            } catch {
                Write-Host "  ERROR: Failed to reset $folder - $_"
            }
        }
    } finally {
        # Unload registry hive if we loaded it
        if ($regPathLoaded) {
            Write-Host "  Unloading registry hive..."
            [gc]::Collect()
            Start-Sleep -Seconds 2
            reg unload "HKLM\TempUserHive_$username" 2>&1 | Out-Null
        }
    }
    
    Write-Host "  Completed for $username"
}

Write-Host "`nRegistry reset complete! You can now run the move script again."
pause
