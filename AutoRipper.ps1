# Path to MakeMKV CLI
$makeMKVPath = "C:\Program Files (x86)\MakeMKV\makemkvcon.exe"
# Blu-ray drive letter (replace 'D:' with the letter of your Blu-ray drive)
$driveLetter = "D:"
# Output directory on your NAS
$outputDirectory = "\\NAS-IP\media\Movies"
# Path to MakeMKV settings file
$settingsFilePath = "$env:USERPROFILE\.MakeMKV\settings.conf"

# Function to check if a disc is in the drive
function Test-DiscInDrive {
    return (Test-Path "$driveLetter\")
}

# Function to rip Blu-ray using MakeMKV in robot mode
function Rip-BluRay {
    param (
        [string]$driveLetter,
        [string]$outputDirectory
    )
    # MakeMKV CLI command with --robot for auto-ripping
    & $makeMKVPath --robot mkv disc:0 all "$outputDirectory" --minlength=3600 --profile=default
    Write-Output "Rip completed and saved to $outputDirectory"
}

# Function to fetch and update the latest MakeMKV beta key
function Update-MakeMKVKey {
    try {
        # Fetch MakeMKV forum page for the latest key
        $url = "https://www.makemkv.com/forum/viewtopic.php?f=5&t=1053"
        $pageContent = Invoke-WebRequest -Uri $url -UseBasicParsing
        $keyPattern = "T-[\w\d]{8}[\w\d]{8}-[\w\d]{5}-[\w\d]{5}-[\w\d]{5}-[\w\d]{5}"
        
        # Correcting the key assignment
        if ($pageContent.Content -match $keyPattern) {
            $newKey = $Matches[0]
            Write-Output "Latest MakeMKV key found: $newKey"

            # Update or add the app_Key in settings.conf
            if (Test-Path $settingsFilePath) {
                # Read existing settings
                $settingsContent = Get-Content -Path $settingsFilePath
                # Check if key exists and update or add it
                if ($settingsContent -match "app_Key =") {
                    $settingsContent = $settingsContent -replace "app_Key = .*", "app_Key = $newKey"
                } else {
                    $settingsContent += "`napp_Key = $newKey"
                }
                # Write the updated settings back
                Set-Content -Path $settingsFilePath -Value $settingsContent -Force
                Write-Output "MakeMKV key updated in settings file."
            } else {
                # Create settings file if it doesn't exist
                $settingsContent = "app_Key = $newKey"
                Set-Content -Path $settingsFilePath -Value $settingsContent -Force
                Write-Output "MakeMKV settings file created and key added."
            }
        } else {
            Write-Output "No new key found on the MakeMKV forum page."
        }
    } catch {
        Write-Output "Failed to update MakeMKV key: $_"
    }
}

# Call Update-MakeMKVKey on startup to ensure the key is current
Update-MakeMKVKey

# Main loop: monitor for disc and rip automatically
$lastKeyUpdate = Get-Date
while ($true) {
    # Check if a disc is in the drive
    if (Test-DiscInDrive) {
        Write-Output "Disc detected in drive $driveLetter. Starting rip..."
        Rip-BluRay -driveLetter $driveLetter -outputDirectory $outputDirectory
        Write-Output "Ejecting disc after rip..."
        (New-Object -comObject Shell.Application).Namespace(17).ParseName("$driveLetter").InvokeVerb("Eject")
    } else {
        Write-Output "No disc detected. Waiting..."
    }

    # Check for key update every 24 hours
    $now = Get-Date
    if ($now -gt $lastKeyUpdate.AddHours(24)) {
        Update-MakeMKVKey
        $lastKeyUpdate = $now
    }

    # Delay to prevent constant polling
    Start-Sleep -Seconds 30
}
