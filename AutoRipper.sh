#!/bin/bash

# Logging function definition (must be defined before use)
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local level="INFO"
    local message="$1"
    
    # Check if second parameter is provided for log level
    if [ -n "$2" ]; then
        level="$2"
    fi
    
    # Format log message
    local formatted_message="[$level] $timestamp - $message"
    
    # Output to terminal using stderr to avoid capture in command substitution
    case "$level" in
        "ERROR") echo -e "\e[31m$formatted_message\e[0m" >&2 ;;  # Red for errors
        "WARNING") echo -e "\e[33m$formatted_message\e[0m" >&2 ;; # Yellow for warnings
        "SUCCESS") echo -e "\e[32m$formatted_message\e[0m" >&2 ;; # Green for success
        "PROCESS") echo -e "\e[36m$formatted_message\e[0m" >&2 ;; # Cyan for process info
        *) echo "$formatted_message" >&2 ;;  # Default color for INFO
    esac
    
    # Save to log file
    echo "$formatted_message" >> "$logFile"
}

# Path to MakeMKV CLI
makeMKVPath="/usr/bin/makemkvcon"

# Blu-ray drive (replace 'sr0' with the appropriate drive identifier for your system)
drive="/dev/sr0"

# Output directory for temporary storage
outputDirectory="$HOME/Videos/Rips"

# SMB share details
smbShare="//canohomeserver.local/media/Movies"
mountPoint="/mnt/smbshare"

# Make sure the output directory exists
mkdir -p "$outputDirectory"

# Logging
logFile="$outputDirectory/ripper_log.txt"
touch "$logFile"

# smbcredentials
smbConfigFile="$HOME/.smbcredentials"
if [ ! -f "$smbConfigFile" ]; then
    echo "Creating SMB credentials file..."
    read -p "Enter SMB Username: " smbUsername
    echo "username=$smbUsername" >> "$smbConfigFile"
    read -s -p "Enter SMB Password: " smbPassword
    echo "password=$smbPassword" >> "$smbConfigFile"
    chmod 600 "$smbConfigFile"
    echo -e "\nCredentials stored securely."
fi


# Path to MakeMKV settings file
settingsFilePath="$HOME/.MakeMKV/settings.conf"

# Function to check if a disc is in the drive
check_disc_in_drive() {
    # More reliable method using both blkid and checking if the device exists
    if [ -e "$drive" ] && blkid -p "$drive" &>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to rip the Blu-ray using MakeMKV
rip_bluray() {
    local drive=$1
    local outputDirectory=$2
    
    # Create a unique directory for this rip
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local ripDir="$outputDirectory/rip_$timestamp"
    mkdir -p "$ripDir"
    log "Created temporary directory for ripping: $ripDir" "INFO"
    
    # MakeMKV CLI command to rip the titles
    log "Starting MakeMKV to rip titles (minimum length: 3600 seconds)..." "PROCESS"
    log "Command: $makeMKVPath --robot mkv disc:0 all \"$ripDir\" --minlength=3600 --decrypt" "INFO"
    
    # Run MakeMKV and save output to log file
    $makeMKVPath --robot mkv disc:0 all "$ripDir" --minlength=3600 --decrypt > "$ripDir/rip_log.txt" 2>&1
    
    local exitCode=$?
    if [ $exitCode -eq 0 ]; then
        log "Rip process completed successfully" "SUCCESS"
        
        # Count how many files were created
        local fileCount=$(find "$ripDir" -type f -name "*.mkv" | wc -l)
        log "Created $fileCount MKV files in $ripDir" "INFO"
        
        echo "$ripDir"
    else
        log "Error occurred during ripping (exit code: $exitCode)" "ERROR"
        log "Check $ripDir/rip_log.txt for details" "ERROR"
        return 1
    fi
}

# Function to eject the disc
eject_disc() {
    log "Ejecting disc..."
    eject "$drive" 2>/dev/null || 
    sudo eject "$drive" 2>/dev/null || 
    { log "Failed to eject disc using eject command"; return 1; }
    
    log "Disc ejected successfully"
    return 0
}

# Function to fetch and update the latest MakeMKV beta key
update_makemkv_key() {
    local url="https://forum.makemkv.com/forum/viewtopic.php?f=5&t=1053"
    
    echo "Checking for latest MakeMKV key..."
    echo "Fetching from $url"
    
    # Use curl with browser-like user agent and follow redirects
    pageContent=$(curl -s -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" "$url")
    
    if [ -z "$pageContent" ]; then
        echo "Failed to fetch the MakeMKV forum page"
            return 1
    fi

    # Save response for debugging
    mkdir -p "$outputDirectory"
    echo "$pageContent" > "$outputDirectory/makemkvpage.html"

    # Extract the key - precise HTML-based extraction
    # First look for text between <pre><code> and </code></pre>
    newKey=$(echo "$pageContent" | grep -o "<pre><code>.*</code></pre>" | sed 's/<pre><code>//;s/<\/code><\/pre>//')
    
    # If that doesn't work, try extracting from the surrounding div structure
    if [ -z "$newKey" ]; then
        echo "Could not find key between <pre><code> tags, trying alternate method"
        # Try with the full div structure
        newKey=$(echo "$pageContent" | grep -o '<div class="codebox">.*<pre><code>.*</code></pre>.*</div>' | 
                 sed 's/.*<pre><code>//;s/<\/code><\/pre>.*//')
    fi
    
    # Final fallback to pattern matching
    if [ -z "$newKey" ]; then
        echo "Could not extract key using HTML structure, trying pattern matching"
        # Try matching the pattern directly
        newKey=$(echo "$pageContent" | grep -o "T-[A-Za-z0-9_]\{60,\}" | head -1)
    fi
    
    if [ -n "$newKey" ]; then
        echo "Latest MakeMKV key found: $newKey"
        
        # Ensure the directory exists
        mkdir -p "$(dirname "$settingsFilePath")"
        
        if [ -e "$settingsFilePath" ]; then
            # Check if key already exists
            currentKey=$(grep "app_Key" "$settingsFilePath" | cut -d "=" -f2 | tr -d ' "')
            if [ "$currentKey" = "$newKey" ]; then
                echo "Current key is already up to date."
                rm -rf $outputDirectory/makemkvpage.html
                return 0
            fi
            
            # Update the key
            if grep -q "app_Key" "$settingsFilePath"; then
                sed -i "s/app_Key = .*/app_Key = \"$newKey\"/" "$settingsFilePath"
            else
                echo "app_Key = \"$newKey\"" >> "$settingsFilePath"
            fi
        else
            echo "app_Key = \"$newKey\"" > "$settingsFilePath"
        fi
        echo "MakeMKV key updated to: $newKey"
        rm -rf $outputDirectory/makemkvpage.html
    else
        echo "No valid key found on the MakeMKV forum page."
        rm -rf $outputDirectory/makemkvpage.html
        return 1
    fi
}


# Function to evaluate and clean up ripped files
evaluate_and_cleanup() {
    local ripDir="$1"
    
    # Validate input parameters
    if [ ! -d "$ripDir" ]; then
        log "Error: Rip directory does not exist: $ripDir" "ERROR"
        return 1
    fi
    
    log "Processing files in $ripDir..." "PROCESS"
    
    # Count the total number of files
    local totalFiles=$(find "$ripDir" -type f -name "*.mkv" | wc -l)
    log "Found $totalFiles MKV files to evaluate" "INFO"
    
    if [ $totalFiles -eq 0 ]; then
        log "No MKV files found in $ripDir" "ERROR"
        return 1
    fi
    
    # Find the largest file - likely the main movie
    log "Identifying largest file (likely the main feature)..." "INFO"
    local largestFile=$(find "$ripDir" -type f -name "*.mkv" -printf "%s %p\n" | sort -nr | head -1 | cut -d' ' -f2-)
    
    if [ -z "$largestFile" ]; then
        log "Failed to identify largest file" "ERROR"
        return 1
    fi
    
    # Get file size in human-readable format
    local fileSize=$(du -h "$largestFile" | cut -f1)
    log "Largest file found: $(basename "$largestFile") ($fileSize)" "INFO"
    
    # Extract the title directly from the filename
    local filename=$(basename "$largestFile")
    # Get everything before "_t" which is the title portion
    local discTitle=${filename%_t*}
    
    log "Extracted title from filename: \"$discTitle\"" "INFO"
    
    # Create new filename with disc title - REMOVE the "_t##" suffix
    local newFileName="$outputDirectory/${discTitle}.mkv"
    log "Creating final file: $newFileName" "PROCESS"
    log "Copying file (this may take a while for large files)..." "INFO"
    
    cp "$largestFile" "$newFileName"
    local cpStatus=$?
    
    if [ $cpStatus -eq 0 ]; then
        log "Successfully created final file: $newFileName" "SUCCESS"
        
        # Show file details
        local finalSize=$(du -h "$newFileName" | cut -f1)
        log "Final file size: $finalSize" "INFO"
        
        # Clean up temporary rip directory after copying the file
        log "Cleaning up temporary files..." "INFO"
        rm -rf "$ripDir"
        log "Temporary directory removed" "INFO"
        
        echo "$newFileName"
    else
        log "Failed to create final file (status: $cpStatus)" "ERROR"
        return 1
    fi
}


# Function to mount SMB share
mount_smb_share() {
    if [ ! -d "$mountPoint" ]; then
        log "Creating mount point directory: $mountPoint"
        mkdir -p "$mountPoint"
    fi

    if ! mountpoint -q "$mountPoint"; then
        log "Mounting SMB share..."
        
        # Try to mount using direct user mount (requires proper fstab setup)
        mount "$mountPoint" 2>/dev/null
        
        if [ $? -ne 0 ]; then
            log "Direct mount failed. Make sure your fstab is properly configured with the 'user' option."
            return 1
        else
            log "SMB share mounted successfully"
        fi
    else
        log "SMB share already mounted"
    fi
}

# Function to move file to SMB share
move_file_to_smb_share() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        log "Error: File $file does not exist" "ERROR"
        return 1
    fi
    
    # Check if mount point is available
    if ! mountpoint -q "$mountPoint"; then
        log "SMB share not mounted, attempting to mount" "WARNING"
        if ! mount_smb_share; then
            log "Failed to mount SMB share. Saving file locally only." "ERROR"
            return 1
        fi
    fi
    
    local filename=$(basename "$file")
    local filesize=$(du -h "$file" | cut -f1)
    
    log "Moving file \"$filename\" ($filesize) to SMB share..." "PROCESS"
    log "Destination: $mountPoint/" "INFO"
    
    # Check if file with same name already exists on SMB share
    if [ -f "$mountPoint/$filename" ]; then
        log "Warning: File with same name already exists on SMB share" "WARNING"
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local newname="${filename%.*}_$timestamp.${filename##*.}"
        log "Renaming to: $newname" "INFO"
        filename=$newname
    fi
    
    log "Copying file to SMB share (this may take a while)..." "INFO"
    cp "$file" "$mountPoint/$filename"
    
    if [ $? -eq 0 ]; then
        log "Successfully copied \"$filename\" to SMB share" "SUCCESS"
        log "Removing local copy..." "INFO"
        rm "$file"
        if [ $? -eq 0 ]; then
            log "Local copy removed" "INFO"
        else
            log "Warning: Failed to remove local copy" "WARNING"
        fi
    else
        log "Failed to copy file to SMB share" "ERROR"
        return 1
    fi
}

# Function to handle the complete ripping process
process_disc() {
    log "=== Starting new disc processing ===" "PROCESS"
    log "Drive: $drive" "INFO"
    log "Output directory: $outputDirectory" "INFO"
    
    # Display date and time
    local startTime=$(date +"%Y-%m-%d %H:%M:%S")
    log "Process started at: $startTime" "INFO"
    
    # Rip the disc - now only returns the rip directory
    local ripDir=""
    ripDir=$(rip_bluray "$drive" "$outputDirectory")
    local ripStatus=$?
    
    if [ $ripStatus -ne 0 ]; then
        log "Ripping failed with status code: $ripStatus" "ERROR"
        return 1
    fi
    
    # Validate ripDir exists
    if [ ! -d "$ripDir" ]; then
        log "Rip directory does not exist: $ripDir" "ERROR"
        return 1
    fi
    
    log "Ripping completed successfully" "SUCCESS"
    log "Temporary rip directory: $ripDir" "INFO"
    
    # Evaluate and clean up - now gets title from the filename
    local finalFile=""
    finalFile=$(evaluate_and_cleanup "$ripDir")
    local cleanupStatus=$?
    
    if [ $cleanupStatus -ne 0 ]; then
        log "File processing failed with status code: $cleanupStatus" "ERROR"
        return 1
    fi
    
    # Validate finalFile exists
    if [ ! -f "$finalFile" ]; then
        log "Final file does not exist: $finalFile" "ERROR"
        return 1
    fi
    
    # Move to SMB share
    log "Preparing to transfer file to network storage..." "PROCESS"
    if ! move_file_to_smb_share "$finalFile"; then
        log "Failed to move file to SMB share" "ERROR"
        return 1
    fi
    
    # Eject the disc
    log "Ejecting disc..." "PROCESS"
    eject_disc
    
    # Calculate total processing time
    local endTime=$(date +"%Y-%m-%d %H:%M:%S")
    local startSecs=$(date -d "$startTime" +%s)
    local endSecs=$(date -d "$endTime" +%s)
    local totalSecs=$((endSecs - startSecs))
    local hours=$((totalSecs / 3600))
    local minutes=$(( (totalSecs % 3600) / 60 ))
    local seconds=$((totalSecs % 60))
    
    log "Process completed at: $endTime" "INFO"
    log "Total processing time: ${hours}h ${minutes}m ${seconds}s" "INFO"
    log "=== Disc processing completed successfully ===" "SUCCESS"
}

# Main program

log "Starting Automatic Blu-ray Ripper"

# Update MakeMKV key on startup
update_makemkv_key

# Mount the SMB share
mount_smb_share

# Main loop: monitor for disc and rip automatically
lastKeyUpdate=$(date +%s)
lastDiscState="false"
discWaitCount=0

log "Entering main monitoring loop"

while true; do
    currentDiscState=$(check_disc_in_drive)
    
    # Only proceed if the drive state has changed to "disc inserted"
    if [[ "$currentDiscState" == "true" && "$lastDiscState" == "false" ]]; then
        log "Disc detected in drive $drive"
        
        # Wait a moment for the disc to be fully readable
        log "Waiting for disc to become ready..."
        sleep 10
        
        # Process the disc
        process_disc
        
        # Update state
        lastDiscState="false"
        discWaitCount=0
    elif [[ "$currentDiscState" == "false" && "$lastDiscState" == "true" ]]; then
        # Disc was removed
        log "Disc removed from drive"
        lastDiscState="false"
        discWaitCount=0
    elif [[ "$currentDiscState" == "false" ]]; then
        # No disc, only log periodically to avoid filling the log
        discWaitCount=$((discWaitCount + 1))
        if [ $((discWaitCount % 10)) -eq 0 ]; then
            log "No disc detected. Waiting..."
        fi
        # Check for key update every 24 hours
        now=$(date +%s)
        if (( now > lastKeyUpdate + 86400 )); then

            update_makemkv_key
            lastKeyUpdate="$now"
        fi
    fi
    
    # Update the disc state
    lastDiscState="$currentDiscState"
    
    
    # Delay to prevent constant polling
    sleep 30
done