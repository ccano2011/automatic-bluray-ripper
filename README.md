# automatic-bluray-ripper
A bash script that automates the process of ripping and encoding movies on Physical Media (DVDs,BDs, & UHD-BDs) which installs all dependencies to build MakeMKV & HandBrakeCLI from source, with native support for `smb` shares. 

**This is a WIP with more substantial documation inbound. Stay tuned...**

### Requirements
This was developed and tested for Debian 12 and a vanilla Ubuntu Server 22.04. This will require a libre-drive compatible optical drive already flashed and tested.

### Basic usage
`./AutoRipper.sh`
- This will install all needed dependencies and build MakeMKV, HandBrake, and begin ripping + encoding the disk already inserted. The included preset files will be chosen depending on the format type.

### Advanced usage (WIP)
With SMB sharing
`./AutoRipper.sh --smb-share`

Skip encoding
`./AutoRipper.sh --no-encode`

Bypass auto shutdown
`./AutoRipper.sh --no-shutdown`

Use a specific preset file
`./AutoRipper.sh --preset-file=UHD-BluRay-Encode.json`

Use a specific preset name (refer to [Handbrake's Preset Documentation](https://handbrake.fr/docs/en/latest/technical/official-presets.html))
`./AutoRipper.sh --preset="Super HQ 2160p60 4K HEVC Surround"`

Combine options
`./AutoRipper.sh --smb-share --preset-file=UHD-BluRay-Encode.json --no-shutdown`

Re-initialize SMB settings
`./AutoRipper.sh --new-smb`

### Troubleshooting/Recommendations for Use

If the MakeMKV beta key is expired and the forum has not updated to a new beta key, please wait for the key to be updated or purchase a key and add it to your install.

If HandBrake is already installed, it is **strongly** recommended to remove it. This script compiles it with all the libraries to ensure it can encode Dolby Vision and other HDR formats.

If MakeMKV is already installed on the system, ensure it's properly added to the PATH so the script can leverage it; otherwise, I also recommend a fresh instance to avoid problems.