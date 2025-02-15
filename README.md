# Miyoo Plus OnionOS Setup Script

A bash script to automate the installation and setup of OnionOS, BIOS files, and ROM sets for Miyoo Plus devices.

## ⚠️ Important Notes

- **BIOS files and ROM sets are NOT included** with this script for legal reasons
- You must provide your own BIOS files and ROM sets
- Place them in the appropriate directories as described below before running the script

## 🗂️ Required Directory Structure

```
.
├── BIOS/                     # Place your BIOS files here
├── sets/                     # ROM sets directory
│   ├── done-set-three_202501/
│   │   ├── Configs for Plus Model/
│   │   ├── Configs for V4 Model/
│   │   ├── Done Set 3/
│   │   │   └── Roms/
│   │   ├── Imgs (2D Box)/
│   │   ├── Imgs (2D Box and Screenshot)/
│   │   ├── Imgs (Miyoo Mix)/
│   │   ├── PS1 Addon for 256gb SD Cards/
│   │   └── Sensible Console Arrangement/
│   ├── tiny-best-set-go-games/
│   ├── tiny-best-set-go-imgs-onion/
│   ├── tiny-best-set-go-expansion-64-games/
│   ├── tiny-best-set-go-expansion-64-imgs-onion/
│   ├── tiny-best-set-go-expansion-128-games/
│   └── tiny-best-set-go-expansion-128-imgs-onion/
└── miyoo-onionos-setup.sh   # The setup script
```

## 🚀 Features

- Automatic SD card formatting (optional)
- Automatic download and installation of the latest OnionOS version
- Installation of Easy Logo Tweak (automatically downloads latest version)
- BIOS files installation
- Multiple ROM set installation options:
  - Done Set Three (with model-specific configurations)
  - Tiny Best Set (main)
  - Tiny Best Set GO (64GB expansion)
  - Tiny Best Set GO (128GB expansion)
  - Tiny Best Set (all expansions)
- Artwork installation options:
  - 2D Box Art
  - 2D Box Art with Screenshots
  - Miyoo Mix Style
- Safe device mounting and unmounting


## 📋 Prerequisites

- Linux operating system
- Sudo access
- Package manager (apt, dnf, or pacman)
- Internet connection for downloading dependencies

The script will automatically check for and install the following required packages if missing:
  - `rsync`
  - `wget`
  - `curl`
  - `parted`
  - `udisks2`

## 🛠️ Usage

1. Clone or download this repository
2. Place your BIOS files in the `BIOS` directory
3. Place your ROM sets in the `sets` directory following the structure above
4. Make the script executable:
   ```bash
   chmod +x miyoo-onionos-setup.sh
   ```
5. Run the script:
   ```bash
   ./miyoo-onionos-setup.sh
   ```

## 📝 Script Options

The script will guide you through the following options:

1. **OnionOS Installation**
   - Downloads and installs the latest version
   - Creates necessary directories on SD card

2. **Easy Logo Tweak Installation**
   - Automatically installs/updates to the latest version

3. **BIOS Installation**
   - Copies BIOS files to the appropriate directory

4. **ROM Sets Installation**
   - Choose from multiple ROM set options
   - Model-specific configurations for Miyoo Plus/V4
   - Optional PS1 games installation
   - Various artwork style options

## ⚙️ Device Support

- Miyoo Plus
- Miyoo Mini V4

## 🔒 Safety Features

- Checks for device mount points
- Safe device ejection
- Confirmation prompts for formatting
- Preserves existing files with --ignore-existing option for ROMs

## ⚖️ Legal Notice

This script does not include any copyrighted BIOS files or ROMs. Users must provide their own files and ensure they have the legal right to use them.

## 🤝 Contributing

Feel free to submit issues and enhancement requests! 