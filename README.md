# automatic-bluray-ripper
A bash script that automates the process of ripping and encoding movies on Physical Media (DVDs,BDs, & UHD-BDs) which installs all dependencies to build MakeMKV & HandBrakeCLI from source, with native support for `smb` shares. 

**This is a WIP with more substantial documation inbound. Stay tuned...**

### Requirements
This was developed and tested for Debian 12. This will require a libre-drive compatible optical drive already flashed and tested.

### Basic usage
`./AutoRipper.sh`
- This will install all needed dependencies and build MakeMKV, HandBrake, and begin ripping + encoding the disk already inserted

### Advanced usage (WIP)
With SMB sharing
`./AutoRipper.sh --smb-share`

Skip encoding
`./AutoRipper.sh --no-encode`

Use a specific preset file
`./AutoRipper.sh --preset-file=UHD-BluRay-Encode.json`

Use a specific preset name
`./AutoRipper.sh --preset="Super HQ 2160p60 4K HEVC Surround"`

Combine options
`./AutoRipper.sh --smb-share --preset-file=UHD-BluRay-Encode.json`

Re-initialize SMB settings
`./AutoRipper.sh --new-smb`
