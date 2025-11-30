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
    # echo "$formatted_message" >> "$logFile"
}

# Blu-ray drive (replace 'sr0' with the appropriate drive identifier for your system)
drive="/dev/sr0"

# Output directory for temporary storage
outputDirectory="$HOME/Videos/Rips"

# SMB share details
mountPoint="/mnt/smbshare"

# Initialize skip_encode & useSmbShare & auto_shutdown flags
skip_encode=false
useSmbShare=false
auto_shutdown=true

#HandBrakeCLI Built-in presets
uhdPresetName="Super HQ 2160p60 4K HEVC Surround"
hdPresetName="Super HQ 1080p30 Surround"
sdPresetName="Super HQ 720p30 Surround"

# AutoRipper.sh directory exported for preset files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define preset names of the preset files
uhdAutoRipperPresetFile="UHD-BluRay-Encode.json"
hdAutoRipperPresetFile="HD-BluRay-Encode.json"
sdAutoRipperPresetFile="SD-DVD-Encode.json"
# Define preset file paths relative to script location
uhdAutoRipperPresetFilePath="${SCRIPT_DIR}/Presets/${uhdAutoRipperPresetFile}"
hdAutoRipperPresetFilePath="${SCRIPT_DIR}/Presets/${hdAutoRipperPresetFile}"
sdAutoRipperPresetFilePath="${SCRIPT_DIR}/Presets/${sdAutoRipperPresetFile}"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --smb-share)
      useSmbShare=true
      shift
      ;;
    --new-smb)
      newSmbShare=true
      shift
      ;;
    --no-encode)
      skip_encode=true
      shift
      ;;
    --no-shutdown)
      auto_shutdown=false
      shift
      ;;
    --preset-file=*)
      presetFile="${1#*=}"  # Extract value after equals sign
      shift
      ;;
    --preset-file)  # Also support space-separated format
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        presetFile="$2"
        shift 2
      else
        log "Error: --preset-file requires a path argument" "ERROR"
        exit 1
      fi
      ;;
    --preset=*)
      userPresetName="${1#*=}"  # Extract value after equals sign
      shift
      ;;
    --preset)  # Also support space-separated format
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        userPresetName="$2"
        shift 2
      else
        log "Error: --preset requires a name argument" "ERROR"
        exit 1
      fi
      ;;
    *)
      # Unknown option
      shift
      ;;
  esac
done

if [ "$newSmbShare" = true ]; then
    rm -rf "$HOME/.smbcredentials"
    useSmbShare=true
fi

if [ "$useSmbShare" = true ]; then
  log "SMB sharing is enabled" "PROCESS"
    # smbcredentials
    smbConfigFile="$HOME/.smbcredentials"
    if [ ! -f "$smbConfigFile" ]; then
        sudo apt install -y cifs-utils
        echo "Creating SMB credentials file..."
        read -p "Enter SMB share path [i.e. //homeserver.local/media/Movies]: " userShare
        echo "smbShare=${userShare:-$smbShare}" >> "$smbConfigFile"
        read -p "Enter SMB Username: " smbUsername
        echo "username=$smbUsername" >> "$smbConfigFile"
        read -s -p "Enter SMB Password: " smbPassword
        echo "password=$smbPassword" >> "$smbConfigFile"
        read -p "Enter local mount point for your Network/SMB share [Press 'Enter' for $mountPoint]: " userMount
        echo "mountPoint=${userMount:-$mountPoint}" >> "$smbConfigFile"
        mkdir -p $mountPoint
        chmod 600 "$smbConfigFile"
        echo -e "\nCredentials stored securely."
    fi
fi

# Configuration file
configFile="$HOME/.autoripperconfig"

# Check if config file exists
if [ ! -f "$configFile" ]; then
  echo "Setting up configuration..."
  
  # Get drive input
  if [ -f "/proc/sys/dev/cdrom/info" ]; then
  driveName=$(grep "drive name:" /proc/sys/dev/cdrom/info | awk '{print $3}')
    if [ -n "$driveName" ]; then
        drive="/dev/$driveName"
        echo "Detected optical drive: $drive"
    fi
  else
    echo "Could not determine optical drive path! Ensure there is one connected to your system and input it!"
  fi
  read -p "Enter optical drive path [Press 'Enter' for '$drive']: " userDrive
  drive=${userDrive:-$drive}
  
  # Get output directory
  read -p "Enter ripping output directory [Press 'Enter' for '$outputDirectory']: " userOutput
  outputDirectory=${userOutput:-$outputDirectory}
  
  # Save to config file
  echo "drive=$drive" > "$configFile"
  echo "outputDirectory=$outputDirectory" >> "$configFile"

  chmod 600 "$configFile"
  echo "Configuration saved."
else
  # Load from config file
  source "$configFile"
  echo "Drive: $drive"
  echo "Output Directory: $outputDirectory"
fi

# Make sure the output directory exists
mkdir -p "$outputDirectory/raw"
mkdir -p "$outputDirectory/encode"

# Logging
logFile="$outputDirectory/ripper_log.txt"
touch "$logFile"

if [ "$skip_encode" = true ]; then
  log "Skipping HandBrake installation check & encoding as requested by -no-encode flag" "WARNING"
  else
    if ! command -v HandBrakeCLI &> /dev/null || ! HandBrakeCLI --version &> /dev/null; then
        echo "Building HandBrake in...." && pwd
        sudo apt update -y
        sudo apt install -y  autoconf \
                    automake \
                    build-essential \
                    ca-certificates \
                    curl \
                    cmake \
                    git \
                    libass-dev \
                    libbz2-dev \
                    libdrm-dev \
                    libfontconfig-dev \
                    libfreetype6-dev \
                    libfribidi-dev \
                    libharfbuzz-dev \
                    libjansson-dev \
                    liblzma-dev \
                    libmp3lame-dev \
                    libnuma-dev \
                    libogg-dev \
                    libopus-dev \
                    libsamplerate0-dev \
                    libspeex-dev \
                    libtheora-dev \
                    libtool \
                    libtool-bin \
                    libturbojpeg0-dev \
                    libssl-dev \
                    libva-dev \
                    libvorbis-dev \
                    libx264-dev \
                    libxml2-dev \
                    libvpx-dev \
                    m4 \
                    make \
                    meson \
                    nasm \
                    ninja-build \
                    openssl \
                    patch \
                    pkg-config \
                    python3 \
                    tar \
                    appstream \
                    desktop-file-utils \
                    gettext \
                    gstreamer1.0-libav \
                    gstreamer1.0-plugins-good \
                    libgstreamer-plugins-base1.0-dev \
                    libgtk-4-dev \
                    zlib1g-dev || { log "Failed to install dependencies" "ERROR"; exit 1; }
        if ! cargo --version &> /dev/null; then
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || { log "Failed to install Rust" "ERROR"; exit 1; }
            source "$HOME/.cargo/env"
            . "$HOME/.cargo/env"
            cargo install cargo-c || { log "Failed to install cargo-c" "ERROR"; exit 1; }
        else 
            log "Cargo installed; checking cargo-c" "PROCESS"
            cargo install cargo-c || { log "Failed to install cargo-c" "ERROR"; exit 1; }
        fi
        cpuCount=$(nproc --all)
        sudo rm -rf HandBrake
        git clone https://github.com/HandBrake/HandBrake.git
        cd HandBrake
        # Default HandBrake with GUI, Intel QSV & H.265 HVEC
        # ./configure --launch-jobs="${cpuCount}" --launch --enable-qsv --enable-vce --enable-gtk --enable-x265
        # Default + Dolby Vision Support; Requires cargo-c to be installed. Try `cargo install cargo-c`
        ./configure --launch-jobs="${cpuCount}" --launch --enable-qsv --enable-vce --enable-gtk --enable-x265 --enable-libdovi
        sudo make --directory=build install || { log "HandBrake failed to compile" "ERROR"; exit 1; }
    fi
fi
if ! command -v makemkvcon &> /dev/null; then
    log "makemkvcon not found in PATH and MakeMKV directory doesn't exist, attempting to build from source..." "WARNING"
    sudo apt update -y
    sudo apt install -y  build-essential \
                    curl \
                    ca-certificates \
                    pkg-config \
                    ffmpeg \
                    libc6-dev \
                    libssl-dev \
                    libexpat1-dev \
                    libavcodec-dev \
                    libgl1-mesa-dev \
                    qtbase5-dev \
                    zlib1g-dev
                    
    LatestMakeMKVVersion=$(curl -s https://www.makemkv.com/download/ | grep -o '[0-9.]*.txt' | sed 's/.txt//') || { log "Failed to download MakeMKV source!" "ERROR"; exit 1; }
    MakeMKVBuildFilesDirectory="MakeMKV/"
    cpuCount=$(nproc --all)
    mkdir -p "MakeMKV"
    cd "MakeMKV"
    curl -# -o makemkv-sha-"${LatestMakeMKVVersion}".txt  \
        https://www.makemkv.com/download/makemkv-sha-"${LatestMakeMKVVersion}".txt
    curl -# -o makemkv-bin-"${LatestMakeMKVVersion}".tar.gz \
        https://www.makemkv.com/download/makemkv-bin-"${LatestMakeMKVVersion}".tar.gz
    curl -# -o makemkv-oss-"${LatestMakeMKVVersion}".tar.gz \
        https://www.makemkv.com/download/makemkv-oss-"${LatestMakeMKVVersion}".tar.gz
    grep "makemkv-bin-${LatestMakeMKVVersion}.tar.gz" "makemkv-sha-${LatestMakeMKVVersion}.txt" | sha256sum -c
    grep "makemkv-bin-${LatestMakeMKVVersion}.tar.gz" "makemkv-sha-${LatestMakeMKVVersion}.txt" | sha256sum -c
    tar xzf makemkv-bin-"${LatestMakeMKVVersion}".tar.gz
    tar xzf makemkv-oss-"${LatestMakeMKVVersion}".tar.gz

    cd makemkv-oss-"${LatestMakeMKVVersion}"
    mkdir -p ./tmp
    ./configure >> /dev/null  2>&1
    sudo make -s -j"${cpuCount}" || { log "Failed to build MakeMKV-oss!" "ERROR"; exit 1; }
    sudo make install || { log "Failed to install MakeMKV-oss!" "ERROR"; exit 1; }

    cd ../makemkv-bin-"${LatestMakeMKVVersion}"
    mkdir -p ./tmp
    echo "yes" >> ./tmp/eula_accepted
    sudo make -s -j"${cpuCount}" || { log "Failed to build MakeMKV!" "ERROR"; exit 1; }
    sudo make install || { log "Failed to install MakeMKV!" "ERROR"; exit 1; }

    makeMKVPath="/usr/bin/makemkvcon"
  else
    makeMKVPath="/usr/bin/makemkvcon"
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
    local ripDir="$outputDirectory/raw/rip_$timestamp"
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
    log "Ejecting disc..." "PROCESS"
    eject "$drive" 2>/dev/null || 
    sudo eject "$drive" 2>/dev/null || 
    { log "Failed to eject disc using eject command" "WARNING"; return 1; }
    
    log "Disc ejected successfully" "SUCCESS"
    return 0
}

# Function to close the disc tray
close_tray() {
    log "Attempting to close disc tray..." "PROCESS"
    eject -t "$drive" 2>/dev/null || 
    sudo eject -t "$drive" 2>/dev/null || 
    { log "Failed to close disc tray using eject command" "WARNING"; return 1; }
    
    log "Disc tray closed successfully" "SUCCESS"
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
        log "MakeMKV key updated to: $newKey" "SUCCESS"
        rm -rf $outputDirectory/makemkvpage.html
    else
        log "No valid key found on the MakeMKV forum page." "WARNING"
        rm -rf $outputDirectory/makemkvpage.html
        return 1
    fi
}

detect_video_resolution() {
    local videoFile="$1"
    local resolution=""
    
    # Use ffprobe to get the resolution information
    if command -v ffprobe &> /dev/null; then
        resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$videoFile")
        log "Detected video resolution: $resolution" "INFO"
        
        # Parse the width from the resolution (format is "1920x1080")
        local width=$(echo "$resolution" | cut -d 'x' -f1)
        
        # Determine resolution category
        if [ -n "$width" ]; then
            if [ "$width" -ge 3840 ]; then
                echo "uhd"
            elif [ "$width" -ge 1920 ]; then
                echo "hd"
            else
                echo "sd"
            fi
        else
            log "Could not detect width from resolution" "WARNING"
            echo "unknown"
        fi
    else
        log "ffprobe not found, cannot detect resolution" "WARNING"
        echo "unknown"
    fi
}

# Function to evaluate, clean up, and encode ripped files
evaluate_and_cleanup() {
    local ripDir="$1"
    local presetPath="$2"      # Optional path to HandBrake preset file
    local presetName="$3"      # Optional preset name to use
    
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
    
    # Group files by their base name (before _t00, _t01, etc.)
    log "Grouping files by base title name..." "INFO"
    
    # Create an associative array to store file groups
    declare -A fileGroups
    
    # Initialize group tracking
    for f in "$ripDir"/*.mkv; do
        local basename=$(basename "$f")
        local baseTitle=${basename%_t*}
        
        if [[ -z "${fileGroups[$baseTitle]}" ]]; then
            fileGroups[$baseTitle]="$f"
        else
            fileGroups[$baseTitle]="${fileGroups[$baseTitle]}|$f"
        fi
    done
    
    # Log the groups found
    log "Found $(echo "${!fileGroups[@]}" | wc -w) distinct title groups" "INFO"
    
    # Now analyze each group to find potential duplicates based on size
    log "Analyzing title groups for duplicates..." "INFO"
    
    local selectedTitle=""
    local selectedGroup=""
    local largestFileSize=0
    
    for group in "${!fileGroups[@]}"; do
        log "Analyzing title group: $group" "INFO"
        
        # Get all files in this group
        IFS='|' read -ra groupFiles <<< "${fileGroups[$group]}"
        log "Group has ${#groupFiles[@]} files" "INFO"
        
        # Check if we have multiple files with identical/similar sizes
        local sizeArray=()
        local identicalSizes=false
        local largestInGroup=""
        local largestSizeInGroup=0
        
        for file in "${groupFiles[@]}"; do
            local fileSize=$(stat -c %s "$file")
            sizeArray+=($fileSize)
            
            # Track largest file in group
            if [ "$fileSize" -gt "$largestSizeInGroup" ]; then
                largestSizeInGroup=$fileSize
                largestInGroup="$file"
            fi
        done
        
        # Determine if files have identical or very similar sizes (within 1% difference)
        local identicalCount=0
        local threshold=$((largestSizeInGroup / 100))  # 1% threshold
        
        for size in "${sizeArray[@]}"; do
            if [ $((largestSizeInGroup - size)) -le $threshold ]; then
                identicalCount=$((identicalCount + 1))
            fi
        done
        
        # If we have multiple files with nearly identical sizes
        if [ $identicalCount -gt 1 ]; then
            log "Detected $identicalCount duplicate titles with similar sizes in group $group" "INFO"
            
            # Prefer lower track numbers (t00, t01) when sizes are similar
            local bestTrack=""
            local bestTrackNum=999
            
            for file in "${groupFiles[@]}"; do
                local fileSize=$(stat -c %s "$file")
                # Only consider files within 1% size difference
                if [ $((largestSizeInGroup - fileSize)) -le $threshold ]; then
                    local basename=$(basename "$file")
                    local trackNum=$(echo "$basename" | grep -o "t[0-9]\+" | sed 's/t//')
                    
                    # Convert to integer
                    trackNum=$((10#$trackNum))
                    
                    if [ $trackNum -lt $bestTrackNum ]; then
                        bestTrackNum=$trackNum
                        bestTrack="$file"
                    fi
                fi
            done
            
            log "Selected track t$(printf "%02d" $bestTrackNum) from duplicate set as it has the lowest track number" "INFO"
            largestInGroup="$bestTrack"
        fi
        
        # Now compare with the best choice so far across all groups
        local groupBestSize=$(stat -c %s "$largestInGroup")
        local sizeMB=$((groupBestSize / 1024 / 1024))
        
        log "Best file in group: $(basename "$largestInGroup") (${sizeMB}MB)" "INFO"
        
        if [ "$groupBestSize" -gt "$largestFileSize" ]; then
            largestFileSize=$groupBestSize
            selectedTitle="$largestInGroup"
            selectedGroup="$group"
        fi
    done
    
    # Final selected title
    if [ -z "$selectedTitle" ] || [ ! -f "$selectedTitle" ]; then
        log "Failed to identify a valid title file" "ERROR"
        return 1
    fi
    
    # Get file size in human-readable format
    local fileSize=$(du -h "$selectedTitle" | cut -f1)
    log "Selected title: $(basename "$selectedTitle") ($fileSize)" "INFO"
    
    # Extract the title directly from the filename
    local filename=$(basename "$selectedTitle")
    local discTitle=${filename%_t*}
    
    log "Extracted title from filename: \"$discTitle\"" "INFO"
    
    # Define file paths with proper organization
    local finalRawFile="$outputDirectory/raw/${discTitle}.mkv"
    local finalEncodedFile="$outputDirectory/encode/${discTitle}.mkv"
    local outputFile=""
    
    log "Deleting unused MKV files to free up space..." "PROCESS"
    local deleteCount=0
    local freedSpaceBytes=0
    
    for f in "$ripDir"/*.mkv; do
        if [ "$f" != "$selectedTitle" ]; then
            local fileSizeBytes=$(stat -c %s "$f")
            freedSpaceBytes=$((freedSpaceBytes + fileSizeBytes))
            local deleteSizeHuman=$(du -h "$f" | cut -f1)
            log "Deleting unused file: $(basename "$f") ($deleteSizeHuman)" "INFO"
            rm "$f"
            deleteCount=$((deleteCount + 1))
        fi
    done
    
    # Convert bytes to GB for reporting
    local freedSpaceGB=$(echo "scale=2; $freedSpaceBytes/1024/1024/1024" | bc)
    log "Deleted $deleteCount unused files, freed approximately ${freedSpaceGB}GB of space" "SUCCESS"
    
    # Check if we're using the file directly or encoding
    if [ "$skip_encode" = false ]; then
        # Move the original file to raw for archiving first
        log "Moving original file to raw directory..." "INFO"
        mv "$selectedTitle" "$finalRawFile"
        
        # Now handle encoding with different presets
        if [ -f "$presetPath" ]; then
            log "Preset File passed in: $presetName" "INFO"
            HandBrakeCLI --preset-import-file "$presetPath" -i "$finalRawFile" -o "$finalEncodedFile" 2>&1 | while read -r line; do
                log "HandBrake: $line" "INFO"
            done
        elif [ -n "$presetName" ]; then
            log "Preset explicitly in: $presetName" "INFO"
            HandBrakeCLI --preset "$presetName" -i "$finalRawFile" -o "$finalEncodedFile" 2>&1 | while read -r line; do
                log "HandBrake: $line" "INFO"
            done
            log "Using user-specified preset: $presetName" "INFO"
        else
            # Auto-detect resolution and select appropriate preset
            log "No preset arguments passed by the user..." "INFO"
            local resolution_type=$(detect_video_resolution "$finalRawFile")
            case "$resolution_type" in
                "uhd")
                    if [ -f "$uhdAutoRipperPresetFilePath" ]; then
                    log "UHD content detected (2160p+), using preset-import-file: $uhdAutoRipperPresetFilePath" "INFO"
                        preset=(--preset-import-file "$uhdAutoRipperPresetFilePath" --preset "$uhdAutoRipperPresetFile")
                    else
                    log "Preset file not used... UHD content detected (2160p+), defaulting to built-in preset: $uhdPresetName" "WARNING"
                        preset=(--preset "$uhdPresetName")
                    fi
                    log "Running HandBrakeCLI encoder..." "PROCESS"
                    HandBrakeCLI "${preset[@]}" -i "$finalRawFile" -o "$finalEncodedFile" 2>&1 | while read -r line; do
                        log "HandBrake: $line" "INFO"
                    done
                    ;;
                "hd")
                    if [ -f "$hdAutoRipperPresetFilePath" ]; then
                    log "HD content detected (1080p), using preset-import-file: $hdAutoRipperPresetFilePath" "INFO"
                        preset=(--preset-import-file "$hdAutoRipperPresetFilePath" --preset "$hdAutoRipperPresetFile")
                    else
                    log "Preset file not used... HD content detected (1080p), defaulting to built-in preset: $hdPresetName" "WARNING"
                        preset=(--preset "$hdPresetName")
                    fi
                    log "Running HandBrakeCLI encoder..." "PROCESS"
                    HandBrakeCLI "${preset[@]}" -i "$finalRawFile" -o "$finalEncodedFile" 2>&1 | while read -r line; do
                        log "HandBrake: $line" "INFO"
                    done
                    ;;
                "sd")
                    if [ -f "$sdAutoRipperPresetFilePath" ]; then
                    log "SD content detected (480p), upscaling to 720p using preset-import-file: $sdAutoRipperPresetFilePath" "INFO"
                        preset=(--preset-import-file "$sdAutoRipperPresetFilePath" --preset "$sdAutoRipperPresetFile")
                    else
                    log "Preset file not used... SD content detected (480p), upscaling to 720p using built-in preset: $sdPresetName" "WARNING"
                        preset=(--preset "$sdPresetName")
                    fi
                    log "Running HandBrakeCLI encoder..." "PROCESS"
                    HandBrakeCLI "${preset[@]}" -i "$finalRawFile" -o "$finalEncodedFile" 2>&1 | while read -r line; do
                        log "HandBrake: $line" "INFO"
                    done
                    ;;
                *)
                    # Fallback to HD preset
                    log "Could not determine resolution, using default HD preset: $hdPresetName" "WARNING"
                    log "Running HandBrakeCLI encoder..." "PROCESS"
                    HandBrakeCLI --preset "$hdPresetName" -i "$finalRawFile" -o "$finalEncodedFile" 2>&1 | while read -r line; do
                        log "HandBrake: $line" "INFO"
                    done
                    ;;
            esac
        fi

        # Check if encoding was successful
        if [ -f "$finalEncodedFile" ]; then
            log "Successfully encoded final file: $finalEncodedFile" "SUCCESS"
            
            # If SMB sharing is enabled, copy the encoded file and delete both encoded and raw files
            if [ "$useSmbShare" = true ]; then
                log "Moving encoded file to SMB share..." "PROCESS"
                move_file_to_smb_share "$finalEncodedFile" true "$finalRawFile"
                outputFile="" # File was deleted after SMB transfer
            else
                # Keep the files locally
                outputFile="$finalEncodedFile"
            fi
        else
            log "Encoding failed, using raw file as final" "WARNING"
            
            # If SMB sharing is enabled, copy the raw file
            if [ "$useSmbShare" = true ]; then
                log "Moving raw file to SMB share..." "PROCESS"
                move_file_to_smb_share "$finalRawFile"
                outputFile="" # File was deleted after SMB transfer
            else
                outputFile="$finalRawFile"
            fi
        fi
    else
        # No encoding, just move the file to raw directory
        log "Skipping encoding, moving selected title directly to raw directory" "INFO"
        mv "$selectedTitle" "$finalRawFile"
        
        # If SMB sharing is enabled, copy the raw file
        if [ "$useSmbShare" = true ]; then
            log "Moving raw file to SMB share..." "PROCESS"
            move_file_to_smb_share "$finalRawFile"
            outputFile="" # File was deleted after SMB transfer
        else
            outputFile="$finalRawFile"
        fi
    fi
}


# Function to mount SMB share
mount_smb_share() {
    if [ ! -d "$mountPoint" ]; then
        log "Creating mount point directory: $mountPoint"
        sudo mkdir -p "$mountPoint"
    fi

    if ! mountpoint -q "$mountPoint"; then
        log "Mounting SMB share..."
        
        # Source the SMB config file to get share path
        if [ -f "$smbConfigFile" ]; then
            source "$smbConfigFile"
        else
            log "SMB configuration file not found" "ERROR"
            return 1
        fi
        
        mount -t cifs "$smbShare" "$mountPoint" -o credentials="$smbConfigFile",iocharset=utf8,file_mode=0777,dir_mode=0777
        
        if [ $? -ne 0 ]; then
            log "Mount failed. Check your SMB credentials and share path." "ERROR"
            return 1
        else
            log "SMB share mounted successfully" "SUCCESS"
        fi
    else
        log "SMB share already mounted" "INFO"
    fi
}

# Function to move file to SMB share
move_file_to_smb_share() {
    local file=$1
    local is_encoded_file=${2:-false}  # Flag to indicate if this is a Handbrake-encoded file
    local raw_source_file=${3:-""}     # Original raw file path (only needed for encoded files)
    
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
        
        # Always delete the file that was just copied
        log "Removing local copy of \"$filename\"..." "INFO"
        rm "$file"
        if [ $? -eq 0 ]; then
            log "Local copy of \"$filename\" removed" "INFO"
        else
            log "Warning: Failed to remove local copy of \"$filename\"" "WARNING"
        fi
        
        # If this is an encoded file, also delete the original raw file
        if [ "$is_encoded_file" = true ] && [ -n "$raw_source_file" ] && [ -f "$raw_source_file" ]; then
            log "Removing original raw file \"$(basename "$raw_source_file")\"..." "INFO"
            rm "$raw_source_file"
            if [ $? -eq 0 ]; then
                log "Original raw file removed" "INFO"
            else
                log "Warning: Failed to remove original raw file" "WARNING"
            fi
        fi
    else
        log "Failed to copy file to SMB share" "ERROR"
        return 1
    fi
    
    return 0
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
    finalFile=$(evaluate_and_cleanup "$ripDir" "$presetFile" "$userPresetName")
    local cleanupStatus=$?
    
    if [ $cleanupStatus -ne 0 ]; then
        log "File processing failed with status code: $cleanupStatus" "ERROR"
        return 1
    fi
    
    # Validate finalFile exists if not using SMB
    if [ -n "$finalFile" ] && [ ! -f "$finalFile" ]; then
        log "Final file does not exist: $finalFile" "ERROR"
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

if [ "$useSmbShare" = true ]; then
    # Mount the SMB share
    mount_smb_share
fi

# Main loop: monitor for disc and rip automatically
lastKeyUpdate=$(date +%s)
lastDiscState="false"
discWaitCount=0
lastActivityTime=$(date +%s)
SHUTDOWN_TIMEOUT=10800  # 3 hours in seconds (3 * 60 * 60)

log "Entering main monitoring loop"

# Auto-shutdown status message
if [ "$auto_shutdown" = true ]; then
    log "Auto-shutdown is ENABLED - system will shutdown after 3 hours of no disc activity" "WARNING"
else
    log "Auto-shutdown is DISABLED (--no-shutdown flag was used)" "INFO"
fi

# Eject any disc that might be in the drive at startup
initialDiscState=$(check_disc_in_drive)
if [[ "$initialDiscState" == "true" ]]; then
    log "Disc detected in drive at startup, ejecting..." "INFO"
    eject_disc
    sleep 10  # Increased wait time for drive to fully eject
    # Verify ejection
    sleep 2
    verifyState=$(check_disc_in_drive)
    if [[ "$verifyState" == "true" ]]; then
        log "Warning: Disc may not have ejected properly" "WARNING"
    fi
fi

# Ensure we start with correct state
lastDiscState=$(check_disc_in_drive)

while true; do
    currentDiscState=$(check_disc_in_drive)
    currentTime=$(date +%s)
    
    # Only proceed if the drive state has changed to "disc inserted"
    if [[ "$currentDiscState" == "true" && "$lastDiscState" == "false" ]]; then
        log "Disc detected in drive $drive"
        
        # Reset activity timer when disc is detected
        lastActivityTime=$(date +%s)
        
        # Wait a moment for the disc to be fully readable
        log "Waiting for disc to become ready..."
        sleep 10
        
        # Process the disc
        process_disc
        
        # Update activity time after processing completes
        lastActivityTime=$(date +%s)
        
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
        
        # Check for shutdown timeout (only if auto_shutdown is enabled)
        if [ "$auto_shutdown" = true ]; then
            timeSinceActivity=$((currentTime - lastActivityTime))
            
            # Log warning at 2 hours 45 minutes (15 minutes before shutdown)
            if [ $timeSinceActivity -ge 9900 ] && [ $timeSinceActivity -lt 9930 ]; then
                log "WARNING: No disc activity for 2 hours 45 minutes. System will shutdown in 15 minutes if no disc is inserted." "WARNING"
            fi
            
            if [ $timeSinceActivity -ge $SHUTDOWN_TIMEOUT ]; then
                log "No disc detected for 3 hours. Initiating shutdown sequence..." "WARNING"
                
                # Close the disc tray before shutdown
                log "Closing disc tray before shutdown..." "PROCESS"
                close_tray
                sleep 2
                
                log "Shutting down system now..." "WARNING"
                sudo shutdown -h now
                exit 0
            fi
        fi
    fi
    
    # Update the disc state
    lastDiscState="$currentDiscState"
    
    # Delay to prevent constant polling
    sleep 30
done