#!/usr/bin/env bash

# Color definitions
RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[0;33m'
BLU='\033[0;34m'
CYN='\033[0;36m'
MAG='\033[0;35m'
BOLD='\033[1m'
RESET='\033[0m'

# After color definitions and before initialize variables
# Function to find mount point
find_mount_point() {
    local device="$1"
    local mount_point=""
    
    # Try to find existing mount point
    mount_point=$(lsblk -no MOUNTPOINT "/dev/${device}1" 2>/dev/null | head -n1)
    
    if [ -n "$mount_point" ]; then
        echo "$mount_point"
        return 0
    fi
    
    # If not mounted and partition exists, try to mount it
    if [ -b "/dev/${device}1" ]; then
        # Check if udisks2 is available
        if command -v udisksctl &>/dev/null; then
            udisksctl mount -b "/dev/${device}1" &>/dev/null
            sleep 2
            mount_point=$(lsblk -no MOUNTPOINT "/dev/${device}1" 2>/dev/null | head -n1)
        fi
    fi
    
    echo "$mount_point"
}

# Initialize variables
GITHUB_REPO="OnionUI/Onion"
LOGOTWEAK_REPO="schmurtzm/Miyoo-Mini-easy-logotweak"
ONION_PATH=""
LOGOTWEAK_PATH=""
BIOS_PATH="./BIOS"
SETS_DIR="./sets"
DEBUG_MODE=false

# Initialize choice variables
INSTALL_ONION="n"
INSTALL_LOGOTWEAK="n"
INSTALL_BIOS="n"
INSTALL_ROMS="n"
MODEL_CHOICE=""
PS1_CHOICE="n"
BOXART_CHOICE=""
ROM_SET_CHOICE=""
FORMAT_SD="n"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Debug logging function
debug_log() {
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${MAG}[DEBUG] $1${RESET}"
    fi
}

# Enhanced rsync with debug mode
enhanced_rsync() {
    local src="$1"
    local dst="$2"
    local flags="$3"
    
    if [ "$DEBUG_MODE" = true ]; then
        debug_log "Running rsync with:"
        debug_log "Source: $src"
        debug_log "Destination: $dst"
        debug_log "Flags: $flags"
        
        # Show what would be transferred without making changes
        debug_log "Files that would be transferred (dry-run):"
        rsync $flags --dry-run -v --stats "$src" "$dst"
        
        # Ask for confirmation before proceeding
        echo -e "${YEL}Would you like to see what files will be changed? [y/N]${RESET}"
        read -r SHOW_CHANGES
        if [[ "$SHOW_CHANGES" =~ ^[Yy]$ ]]; then
            rsync $flags --dry-run -iv "$src" "$dst"
        fi
        
        echo -e "${YEL}Do you want to proceed with the transfer? [Y/n]${RESET}"
        read -r PROCEED
        if [[ "$PROCEED" =~ ^[Nn]$ ]]; then
            debug_log "Transfer cancelled by user"
            return 1
        fi
        
        # Perform the actual transfer with verbose output
        rsync $flags -v --stats "$src" "$dst"
    else
        # Non-debug mode: show progress but not detailed stats
        rsync $flags --info=progress2 "$src" "$dst"
    fi
}

# Enhanced wget with debug mode
enhanced_wget() {
    local url="$1"
    local output="$2"
    
    if [ "$DEBUG_MODE" = true ]; then
        debug_log "Downloading from: $url"
        debug_log "Output file: $output"
        wget --debug -O "$output" "$url"
    else
        wget -q --show-progress -O "$output" "$url"
    fi
}

# Enhanced unzip with debug mode
enhanced_unzip() {
    local zipfile="$1"
    local dest="$2"
    
    if [ "$DEBUG_MODE" = true ]; then
        debug_log "Extracting: $zipfile"
        debug_log "Destination: $dest"
        unzip -v "$zipfile" -d "$dest"
    else
        unzip -q -o "$zipfile" -d "$dest"
    fi
}

# Formatting functions
print_header() {
    local text="$1"
    echo -e "\n${BOLD}${MAG}════════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${BLU}   $text${RESET}"
    echo -e "${BOLD}${MAG}════════════════════════════════════════════════════════════════════${RESET}\n"
}

print_step() {
    local text="$1"
    echo -e "\n${BOLD}${CYN}→ $text${RESET}\n"
}

print_success() {
    local text="$1"
    echo -e "${GRN}✓ $text${RESET}"
}

print_warning() {
    local text="$1"
    echo -e "${YEL}⚠ $text${RESET}"
}

print_error() {
    local text="$1"
    echo -e "${RED}✗ $text${RESET}"
}

print_info() {
    local text="$1"
    echo -e "${BLU}ℹ $text${RESET}"
}

print_banner() {
    echo -e "${CYN}${BOLD}"
    cat << "EOF"
 __  __ _         
|  \/  (_)_   _  ___   ___ 
| |\/| | | | | |/ _ \ / _ \ 
| |  | | | |_| | (_) | (_) | +
|_|  |_|_|\__, |\___/ \___/
          |___/                    
     ___        _            ___  ____
    / _ \ _ __ (_) ___  _ _ / _ \/ ___|
   | | | | '_ \| |/ _ \| | | | | \___ \
   | |_| | | | | | (_) | | | |_| |___) |
    \___/|_| |_|_|\___/|_|  \___/|____/
EOF
    echo -e "                    Setup Script v1.0${RESET}\n"
}

check_onion_version() {
    print_header "Checking OnionOS Version"
    
    # Get latest release version from GitHub
    print_step "Checking GitHub for latest version"
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | grep -o '"tag_name": ".*"' | cut -d'"' -f4)
    
    if [ -z "$LATEST_VERSION" ]; then
        print_error "Failed to fetch latest version from GitHub"
        return 1
    fi
    
    print_info "Latest version on GitHub: ${BOLD}$LATEST_VERSION${RESET}"
    
    # Find all Onion directories
    local ONION_DIRS=(Onion-v*)
    
    if [ ${#ONION_DIRS[@]} -eq 0 ] || [ ! -d "${ONION_DIRS[0]}" ]; then
        print_warning "No local OnionOS installation found"
        print_step "Downloading latest version ($LATEST_VERSION)"
        download_onion_version "$LATEST_VERSION"
        return
    fi
    
    # Find the latest local version
    local LATEST_LOCAL=""
    local LATEST_LOCAL_DIR=""
    
    for dir in "${ONION_DIRS[@]}"; do
        if [[ $dir =~ Onion-v([0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?) ]]; then
            local version="${BASH_REMATCH[1]}"
            if [ -z "$LATEST_LOCAL" ] || version_gt "$version" "$LATEST_LOCAL"; then
                LATEST_LOCAL="$version"
                LATEST_LOCAL_DIR="$dir"
            fi
        fi
    done
    
    if [ -n "$LATEST_LOCAL" ]; then
        print_info "Latest local version: ${BOLD}$LATEST_LOCAL${RESET}"
        
        # Compare versions
        if version_gt "${LATEST_VERSION#v}" "$LATEST_LOCAL"; then
            print_warning "A newer version is available"
            print_step "Downloading version $LATEST_VERSION"
            download_onion_version "$LATEST_VERSION"
        else
            print_success "Local version is up to date"
            ONION_PATH="./$LATEST_LOCAL_DIR"
        fi
    else
        print_warning "No valid local version found"
        print_step "Downloading latest version ($LATEST_VERSION)"
        download_onion_version "$LATEST_VERSION"
    fi
}

# Helper function to compare version strings
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

# Helper function to download and extract OnionOS
download_onion_version() {
    local version="$1"
    local download_url=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | grep "browser_download_url.*Onion-v.*\.zip" | cut -d'"' -f4)
    
    if [ -z "$download_url" ]; then
        print_error "Failed to get download URL"
        return 1
    fi
    
    local temp_file="onion_temp.zip"
    
    # Download the file
    if ! enhanced_wget "$download_url" "$temp_file"; then
        print_error "Failed to download OnionOS"
        rm -f "$temp_file"
        return 1
    fi
    
    # Extract the file
    print_info "Extracting OnionOS..."
    if ! enhanced_unzip "$temp_file" "./"; then
        print_error "Failed to extract OnionOS"
        rm -f "$temp_file"
        return 1
    fi
    
    # Clean up
    rm -f "$temp_file"
    
    # Set the ONION_PATH to the newly downloaded version
    ONION_PATH="./Onion-${version}"
    
    print_success "Successfully downloaded and extracted OnionOS version $version"
}

check_and_install_easy_logo_tweak() {
    local mount_point="$1"
    
    print_header "Installing Easy Logo Tweak"
    
    print_step "Checking GitHub for latest version"
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/$LOGOTWEAK_REPO/releases/latest" | grep -o '"tag_name": ".*"' | cut -d'"' -f4)
    
    if [ -z "$LATEST_VERSION" ]; then
        print_error "Failed to fetch latest Easy Logo Tweak version from GitHub"
        return 1
    fi
    
    print_info "Latest version on GitHub: ${BOLD}$LATEST_VERSION${RESET}"
    
    # Find local Easy Logo Tweak directory
    local LOGOTWEAK_DIRS=(Easy-LogoTweak_v*)
    local LATEST_LOCAL=""
    local LATEST_LOCAL_DIR=""
    
    if [ ${#LOGOTWEAK_DIRS[@]} -gt 0 ] && [ -d "${LOGOTWEAK_DIRS[0]}" ]; then
        for dir in "${LOGOTWEAK_DIRS[@]}"; do
            if [[ $dir =~ Easy-LogoTweak_v([0-9]+\.[0-9]+\.[0-9]+) ]]; then
                local version="${BASH_REMATCH[1]}"
                if [ -z "$LATEST_LOCAL" ] || version_gt "$version" "$LATEST_LOCAL"; then
                    LATEST_LOCAL="$version"
                    LATEST_LOCAL_DIR="$dir"
                fi
            fi
        done
    fi
    
    local should_download=true
    if [ -n "$LATEST_LOCAL" ]; then
        print_info "Latest local version: ${BOLD}$LATEST_LOCAL${RESET}"
        if ! version_gt "${LATEST_VERSION#v}" "$LATEST_LOCAL"; then
            print_success "Local Easy Logo Tweak version is up to date"
            should_download=false
            LOGOTWEAK_PATH="./$LATEST_LOCAL_DIR"
        else
            print_warning "A newer version of Easy Logo Tweak is available"
        fi
    else
        print_warning "No local Easy Logo Tweak installation found"
    fi
    
    if [ "$should_download" = true ]; then
        print_step "Downloading version $LATEST_VERSION"
        local download_url=$(curl -s "https://api.github.com/repos/$LOGOTWEAK_REPO/releases/latest" | grep "browser_download_url.*\.zip" | cut -d'"' -f4)
        
        if [ -z "$download_url" ]; then
            print_error "Failed to get Easy Logo Tweak download URL"
            return 1
        fi
        
        local temp_file="logotweak_temp.zip"
        LOGOTWEAK_PATH="./Easy-LogoTweak_${LATEST_VERSION}"
        
        # Create version directory
        mkdir -p "$LOGOTWEAK_PATH"
        
        # Download the file
        if ! enhanced_wget "$download_url" "$temp_file"; then
            print_error "Failed to download Easy Logo Tweak"
            rm -f "$temp_file"
            rm -rf "$LOGOTWEAK_PATH"
            return 1
        fi
        
        # Extract the file into the version directory
        print_info "Extracting Easy Logo Tweak..."
        if ! enhanced_unzip "$temp_file" "$LOGOTWEAK_PATH"; then
            print_error "Failed to extract Easy Logo Tweak"
            rm -f "$temp_file"
            rm -rf "$LOGOTWEAK_PATH"
            return 1
        fi
        
        # Clean up
        rm -f "$temp_file"
    fi
    
    # Copy App directory to SD card
    if [ -d "$LOGOTWEAK_PATH/App" ]; then
        print_step "Installing to SD card"
        enhanced_rsync "$LOGOTWEAK_PATH/App/" "$mount_point/App/" "-a"
        print_success "Easy Logo Tweak installation complete!"
    else
        print_error "Could not find App directory in Easy Logo Tweak package"
        return 1
    fi
}

check_and_install_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Detect package manager
    if command -v apt &>/dev/null; then
        PKG_MANAGER="apt"
        INSTALL_CMD="apt-get install -y"
        UPDATE_CMD="apt-get update"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="dnf install -y"
        UPDATE_CMD="dnf check-update"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="pacman -S --noconfirm"
        UPDATE_CMD="pacman -Sy"
    else
        print_error "No supported package manager found (apt, dnf, or pacman)"
        print_warning "Please install the following packages manually:"
        echo -e "- rsync\n- wget\n- curl\n- parted\n- udisks2"
        exit 1
    fi
    
    # Check sudo access
    if ! sudo -v; then
        print_error "Sudo access is required to install missing packages"
        exit 1
    fi
    
    local MISSING_PKGS=()
    
    # Check for required packages
    print_step "Checking required packages"
    for pkg in rsync wget curl parted; do
        if ! command -v $pkg &>/dev/null; then
            MISSING_PKGS+=("$pkg")
            print_warning "$pkg not found"
        else
            print_success "$pkg found"
        fi
    done
    
    if ! command -v udisksctl &>/dev/null; then
        MISSING_PKGS+=("udisks2")
        print_warning "udisks2 not found"
    else
        print_success "udisks2 found"
    fi
    
    # Install missing packages if any
    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        print_step "Installing missing packages"
        printf '%s\n' "${MISSING_PKGS[@]}" | sed 's/^/  - /'
        
        print_info "Updating package lists..."
        if ! sudo $UPDATE_CMD; then
            print_error "Failed to update package lists"
            exit 1
        fi
        
        print_info "Installing packages..."
        if ! sudo $INSTALL_CMD "${MISSING_PKGS[@]}"; then
            print_error "Failed to install one or more packages"
            exit 1
        fi
        
        print_success "Successfully installed all required packages"
    else
        print_success "All required packages are already installed"
    fi
}

collect_user_choices() {
    print_header "Setup Configuration"
    
    print_info "Please insert your SD card into your PC and press ENTER to continue"
    read -r
    
    # Find and select SD card first
    mapfile -t USB_DISKS < <(lsblk -dno NAME,MODEL,TRAN,SIZE,TYPE | grep usb | awk '{print $1"||"$2" "$3" "$4" "$5}')
    if [ ${#USB_DISKS[@]} -eq 0 ]; then
        print_error "No USB disks found."
        print_info "Please make sure your SD card is properly inserted."
        exit 1
    fi
    
    print_header "SD Card Selection"
    print_step "Available USB devices:"
    PS3="Select your SD card device (q to quit): "
    select ITEM in "${USB_DISKS[@]}"; do
        if [ "$REPLY" = "q" ]; then
            print_warning "Exiting..."
            exit 0
        fi
        [ -n "$ITEM" ] && break
    done
    
    SELECTED_DEVICE="$(cut -d"|" -f1 <<< "$ITEM")"
    print_success "Selected device: /dev/$SELECTED_DEVICE"
    
    # Ask if this is a new installation
    print_header "Installation Type"
    
    # Show warning about formatting if this is a new installation
    print_warning "IMPORTANT: Selecting 'New Installation' will:"
    echo -e "  1. FORMAT /dev/$SELECTED_DEVICE (ALL DATA WILL BE ERASED)"
    echo -e "  2. Install the latest version of OnionOS"
    echo -e "  3. Create a fresh configuration\n"
    
    echo -e "Is this a new installation? [y/N]: "
    read -r IS_NEW_INSTALL
    
    if [[ "$IS_NEW_INSTALL" =~ ^[Yy]$ ]]; then
        FORMAT_SD="y"
        INSTALL_ONION="y"
        print_info "The SD card will be formatted and OnionOS will be installed"
        
        # Additional confirmation for formatting
        print_step "⚠️  FORMAT CONFIRMATION"
        echo -e "${RED}WARNING: ALL DATA ON /dev/$SELECTED_DEVICE WILL BE ERASED!${RESET}"
        echo -e "Device details:"
        lsblk -o NAME,SIZE,MODEL,VENDOR,TYPE "/dev/$SELECTED_DEVICE" | grep -v "^$SELECTED_DEVICE[0-9]"
        echo -e "\nType ${BOLD}YES${RESET} in capital letters to confirm format: "
        read -r FORMAT_CONFIRM
        if [ "$FORMAT_CONFIRM" != "YES" ]; then
            print_error "Format not confirmed. Exiting for safety."
            exit 1
        fi
    else
        FORMAT_SD="n"
        INSTALL_ONION="n"
        print_info "Skipping format and OnionOS installation"
    fi
    
    # Ask about Easy Logo Tweak
    print_step "Easy Logo Tweak"
    echo -e "Would you like to install Easy Logo Tweak? [y/N]: "
    read -r INSTALL_LOGOTWEAK
    
    # Ask about BIOS if directory exists
    if [ -d "$BIOS_PATH" ]; then
        print_step "BIOS Installation"
        echo -e "Would you like to install BIOS files? [y/N]: "
        read -r INSTALL_BIOS
    fi
    
    # Ask about ROM sets if directory exists
    if [ -d "$SETS_DIR" ]; then
        print_step "ROM Installation"
        echo -e "Would you like to install ROM sets? [y/N]: "
        read -r INSTALL_ROMS
        
        if [[ "$INSTALL_ROMS" =~ ^[Yy]$ ]]; then
            print_step "ROM Set Selection"
            echo -e "Available ROM packs:"
            PS3="Select a ROM pack (q to quit): "
            select SET_CHOICE in \
                "done-set-three" \
                "tiny-best-go (main)" \
                "tiny-best-go (main) + 64gb expansion" \
                "tiny-best-go (main) + 64gb + 128gb expansion"; do
                if [ "$REPLY" = "q" ]; then
                    INSTALL_ROMS="n"
                    break
                fi
                [ -n "$SET_CHOICE" ] && ROM_SET_CHOICE="$REPLY" && break
            done
            
            if [ "$ROM_SET_CHOICE" = "1" ]; then
                print_step "Device Model Selection"
                select MODEL_CHOICE in "Miyoo Plus" "Miyoo v4"; do
                    [ -n "$MODEL_CHOICE" ] && break
                done
                
                print_step "PS1 Games"
                echo -e "Include PS1 games? [y/N]: "
                read -r PS1_CHOICE
                
                print_step "Box Art Selection"
                print_info "Miyoo Mix is the recommended box art style for the best visual experience"
                select BOXART_CHOICE in "Miyoo Mix (Recommended)" "2D Box" "2D Box and Screenshot"; do
                    [ -n "$BOXART_CHOICE" ] && break
                done
            fi
        fi
    fi
    
    # Show configuration summary
    print_header "Configuration Summary"
    
    # Fix the syntax for the summary output
    echo -e "Installation Type: ${BOLD}$([[ "$IS_NEW_INSTALL" =~ ^[Yy]$ ]] && echo "New Installation" || echo "Update Existing")${RESET}"
    echo -e "Format SD Card: ${BOLD}$([[ "$FORMAT_SD" =~ ^[Yy]$ ]] && echo "Yes" || echo "No")${RESET}"
    echo -e "Install OnionOS: ${BOLD}$([[ "$INSTALL_ONION" =~ ^[Yy]$ ]] && echo "Yes" || echo "No")${RESET}"
    echo -e "Install Easy Logo Tweak: ${BOLD}$([[ "$INSTALL_LOGOTWEAK" =~ ^[Yy]$ ]] && echo "Yes" || echo "No")${RESET}"
    [ -d "$BIOS_PATH" ] && echo -e "Install BIOS: ${BOLD}$([[ "$INSTALL_BIOS" =~ ^[Yy]$ ]] && echo "Yes" || echo "No")${RESET}"
    echo -e "Install ROMs: ${BOLD}$([[ "$INSTALL_ROMS" =~ ^[Yy]$ ]] && echo "Yes" || echo "No")${RESET}"
    
    if [[ "$INSTALL_ROMS" =~ ^[Yy]$ ]]; then
        echo -e "ROM Set: ${BOLD}$SET_CHOICE${RESET}"
        [ "$ROM_SET_CHOICE" = "1" ] && echo -e "Device Model: ${BOLD}$MODEL_CHOICE${RESET}"
        [ "$ROM_SET_CHOICE" = "1" ] && echo -e "Include PS1: ${BOLD}$([[ "$PS1_CHOICE" =~ ^[Yy]$ ]] && echo "Yes" || echo "No")${RESET}"
        [ "$ROM_SET_CHOICE" = "1" ] && echo -e "Box Art: ${BOLD}$BOXART_CHOICE${RESET}"
    fi
    
    print_step "Confirmation"
    echo -e "Proceed with these settings? [Y/n]: "
    read -r PROCEED
    if [[ "$PROCEED" =~ ^[Nn]$ ]]; then
        print_error "Setup cancelled by user"
        exit 0
    fi
}

# After prerequisites check and before device selection
check_and_install_prerequisites

print_banner

# Call collect_user_choices
collect_user_choices

if [ ! -d "$BIOS_PATH" ]; then
    print_warning "No BIOS folder found; skipping BIOS merge step."
fi

# Only check OnionOS version if we're installing it
if [[ "$INSTALL_ONION" =~ ^[Yy]$ ]]; then
    check_onion_version
fi

# Get initial mount point
MOUNT_POINT=$(find_mount_point "$SELECTED_DEVICE")

# Format if requested
if [[ "$FORMAT_SD" =~ ^[Yy]$ ]]; then
    print_step "Preparing to format SD card..."
    
    # Check if device is mounted and unmount all partitions
    if mount | grep -q "/dev/${SELECTED_DEVICE}"; then
        print_info "Unmounting all partitions on /dev/${SELECTED_DEVICE}..."
        for part in $(lsblk -nlo NAME "/dev/${SELECTED_DEVICE}" | grep "^${SELECTED_DEVICE}[0-9]"); do
            if mount | grep -q "/dev/$part"; then
                print_info "Unmounting /dev/$part"
                if command -v udisksctl &>/dev/null; then
                    udisksctl unmount -b "/dev/$part" &>/dev/null
                else
                    sudo umount "/dev/$part" &>/dev/null
                fi
                sleep 1
            fi
        done
    fi
    
    # Double check no partitions are mounted
    if mount | grep -q "/dev/${SELECTED_DEVICE}"; then
        print_error "Unable to unmount all partitions. Please unmount manually and try again."
        exit 1
    fi
    
    print_step "Formatting SD card..."
    
    # Create new partition table
    print_info "Creating new partition table..."
    if ! sudo parted -s "/dev/$SELECTED_DEVICE" mklabel msdos; then
        print_error "Failed to create partition table"
        exit 1
    fi
    
    # Create primary partition
    print_info "Creating primary partition..."
    if ! sudo parted -s "/dev/$SELECTED_DEVICE" mkpart primary fat32 1MiB 100%; then
        print_error "Failed to create partition"
        exit 1
    fi
    
    # Wait for partition to be recognized
    sleep 2
    
    # Format partition
    print_info "Formatting partition as FAT32..."
    if ! sudo mkfs.vfat -F 32 -n "ONION" "/dev/${SELECTED_DEVICE}1"; then
        print_error "Failed to format partition"
        exit 1
    fi
    
    print_success "Formatting complete"
    print_info "Remove and reinsert the SD card, then press ENTER"
    read -r
    
    # Wait for device to be recognized
    sleep 2
    
    # Update mount point after format and reinsertion
    MOUNT_POINT=$(find_mount_point "$SELECTED_DEVICE")
    
    if [ -z "$MOUNT_POINT" ]; then
        print_error "Failed to mount formatted SD card"
        print_info "Please remove and reinsert the SD card, then try again"
        exit 1
    fi
    
    print_success "SD card mounted at $MOUNT_POINT"
fi

# Always try to find mount point before operations
if [ -z "$MOUNT_POINT" ]; then
  MOUNT_POINT=$(find_mount_point "$SELECTED_DEVICE")
fi

# Install OnionOS if selected
if [[ "$INSTALL_ONION" =~ ^[Yy]$ ]] && [ -d "$ONION_PATH" ]; then
  if [ -z "$MOUNT_POINT" ]; then
    print_error "No mount point found for /dev/${SELECTED_DEVICE}1"
    print_info "Please make sure the device is properly inserted and mounted."
    exit 1
  fi
  
  # Create necessary directories
  mkdir -p "$MOUNT_POINT/Roms" "$MOUNT_POINT/Emu" "$MOUNT_POINT/BIOS" "$MOUNT_POINT/App"
  
  print_step "Installing OnionOS..."
  enhanced_rsync "$ONION_PATH/" "$MOUNT_POINT/" "-a"
  
  print_success "OnionOS installation complete!"
  print_info "Please follow these steps:"
  echo -e "1. Remove the SD card and insert it into your Miyoo device"
  echo -e "2. Wait for the Onion installation to complete"
  echo -e "3. After the device restarts, shut it down"
  echo -e "4. Remove the SD card and reinsert it into your computer"
  echo -e "5. Press ENTER when ready to continue"
  
  if [ -n "$MOUNT_POINT" ]; then
    echo -e "${CYN}Unmounting and ejecting device...${RESET}"
    if command -v udisksctl &>/dev/null; then
      udisksctl unmount -b "/dev/${SELECTED_DEVICE}1" &>/dev/null
    else
      sudo umount "/dev/${SELECTED_DEVICE}1" &>/dev/null
    fi
    sudo eject "/dev/$SELECTED_DEVICE"
    print_success "Device ejected. You can now safely remove the SD card."
  fi
  
  read -r
  # Update mount point after reinsertion
  MOUNT_POINT=$(find_mount_point "$SELECTED_DEVICE")
fi

# Install Easy Logo Tweak if selected
if [[ "$INSTALL_LOGOTWEAK" =~ ^[Yy]$ ]]; then
  if [ -n "$MOUNT_POINT" ]; then
    mkdir -p "$MOUNT_POINT/App"
    check_and_install_easy_logo_tweak "$MOUNT_POINT"
  else
    print_error "No mount point found for Easy Logo Tweak installation"
    print_info "Please make sure the device is properly inserted and mounted."
    exit 1
  fi
fi

# Install BIOS if selected
if [[ "$INSTALL_BIOS" =~ ^[Yy]$ ]] && [ -d "$BIOS_PATH" ]; then
  if [ -z "$MOUNT_POINT" ]; then
    print_error "No mount point found for /dev/${SELECTED_DEVICE}1"
    print_info "Please make sure the device is properly inserted and mounted."
    exit 1
  fi
  print_step "Installing BIOS files..."
  enhanced_rsync "$BIOS_PATH/" "$MOUNT_POINT/BIOS/" "-a"
  print_success "BIOS files installed successfully!"
fi

# Install ROMs if selected
if [[ "$INSTALL_ROMS" =~ ^[Yy]$ ]] && [ -d "$SETS_DIR" ]; then
  if [ -z "$MOUNT_POINT" ]; then
    print_error "No mount point found for /dev/${SELECTED_DEVICE}1"
    print_info "Please make sure the device is properly inserted and mounted."
    exit 1
  fi
  
  # Process ROM installation based on earlier choice
  case "$ROM_SET_CHOICE" in
    "2") # tiny-best-go (main)
      if [ -d "$SETS_DIR/tiny-best-set-go-games/Roms" ]; then
        print_step "Installing main ROM set..."
        enhanced_rsync "$SETS_DIR/tiny-best-set-go-games/Roms/" "$MOUNT_POINT/Roms/" "-a"
        if [ -d "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms" ]; then
          print_step "Installing artwork..."
          enhanced_rsync "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms/" "$MOUNT_POINT/Roms/" "-a"
        fi
      else
        print_error "Main ROM set directory not found"
      fi
      ;;
      
    "3") # tiny-best-go (main) + 64gb expansion
      if [ -d "$SETS_DIR/tiny-best-set-go-games/Roms" ]; then
        print_step "Installing main ROM set..."
        enhanced_rsync "$SETS_DIR/tiny-best-set-go-games/Roms/" "$MOUNT_POINT/Roms/" "-a"
        if [ -d "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms" ]; then
          print_step "Installing main artwork..."
          enhanced_rsync "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms/" "$MOUNT_POINT/Roms/" "-a"
        fi
      fi
      
      if [ -d "$SETS_DIR/tiny-best-set-go-expansion-64-games/Roms" ]; then
        print_step "Installing 64GB expansion ROMs..."
        enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-64-games/Roms/" "$MOUNT_POINT/Roms/" "-a"
        if [ -d "$SETS_DIR/tiny-best-set-go-expansion-64-imgs-onion/Roms" ]; then
          print_step "Installing 64GB expansion artwork..."
          enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-64-imgs-onion/Roms/" "$MOUNT_POINT/Roms/" "-a"
        fi
      fi
      ;;
      
    "4") # tiny-best-go (main) + 64gb + 128gb expansion
      if [ -d "$SETS_DIR/tiny-best-set-go-games/Roms" ]; then
        print_step "Installing main ROM set..."
        enhanced_rsync "$SETS_DIR/tiny-best-set-go-games/Roms/" "$MOUNT_POINT/Roms/" "-a"
        if [ -d "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms" ]; then
          print_step "Installing main artwork..."
          enhanced_rsync "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms/" "$MOUNT_POINT/Roms/" "-a"
        fi
      fi
      
      if [ -d "$SETS_DIR/tiny-best-set-go-expansion-64-games/Roms" ]; then
        print_step "Installing 64GB expansion ROMs..."
        enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-64-games/Roms/" "$MOUNT_POINT/Roms/" "-a"
        if [ -d "$SETS_DIR/tiny-best-set-go-expansion-64-imgs-onion/Roms" ]; then
          print_step "Installing 64GB expansion artwork..."
          enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-64-imgs-onion/Roms/" "$MOUNT_POINT/Roms/" "-a"
        fi
      fi
      
      if [ -d "$SETS_DIR/tiny-best-set-go-expansion-128-games/Roms" ]; then
        print_step "Installing 128GB expansion ROMs..."
        enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-128-games/Roms/" "$MOUNT_POINT/Roms/" "-a"
        if [ -d "$SETS_DIR/tiny-best-set-go-expansion-128-imgs-onion/Roms" ]; then
          print_step "Installing 128GB expansion artwork..."
          enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-128-imgs-onion/Roms/" "$MOUNT_POINT/Roms/" "-a"
        fi
      fi
      ;;
      
    "1") # done-set-three
      echo -e "Which device model?"
      select MODEL_CHOICE in "Miyoo Plus" "Miyoo v4"; do
        [ -n "$MODEL_CHOICE" ] && break
      done
      
      echo "Include PS1 games? [y/N]"
      read -r PS1_CHOICE
      
      echo "Choose box art type:"
      print_info "Miyoo Mix is the recommended box art style for the best visual experience"
      select BOXART_CHOICE in "Miyoo Mix (Recommended)" "2D Box" "2D Box and Screenshot"; do
        [ -n "$BOXART_CHOICE" ] && break
      done
      
      # Install ROMs based on model choice
      if [ "$MODEL_CHOICE" = "Miyoo Plus" ]; then
        if [ -d "$SETS_DIR/done-set-three_202501/Configs for Plus Model" ]; then
          echo -e "${CYN}Installing Miyoo Plus configurations...${RESET}"
          enhanced_rsync "$SETS_DIR/done-set-three_202501/Configs for Plus Model/RetroArch/" "$MOUNT_POINT/RetroArch/" "-a"
          enhanced_rsync "$SETS_DIR/done-set-three_202501/Configs for Plus Model/Saves/" "$MOUNT_POINT/Saves/" "-a"
        else
          echo -e "${RED}Configuration directory for Miyoo Plus not found${RESET}"
        fi
      elif [ "$MODEL_CHOICE" = "Miyoo v4" ]; then
        if [ -d "$SETS_DIR/done-set-three_202501/Configs for V4 Model" ]; then
          echo -e "${CYN}Installing Miyoo v4 configurations...${RESET}"
          enhanced_rsync "$SETS_DIR/done-set-three_202501/Configs for V4 Model/RetroArch/" "$MOUNT_POINT/RetroArch/" "-a"
          enhanced_rsync "$SETS_DIR/done-set-three_202501/Configs for V4 Model/Saves/" "$MOUNT_POINT/Saves/" "-a"
        else
          echo -e "${RED}Configuration directory for Miyoo v4 not found${RESET}"
        fi
      fi

      # Install emulator configurations
      if [ -d "$SETS_DIR/done-set-three_202501/Sensible Console Arrangement" ]; then
        echo -e "${CYN}Installing emulator configurations...${RESET}"
        if [ "$DEBUG_MODE" = true ]; then
            print_info "This will merge with your existing Emu directory"
            print_info "Existing files with the same name will be updated"
            print_info "Other files in your Emu directory will not be touched"
        fi
        enhanced_rsync "$SETS_DIR/done-set-three_202501/Sensible Console Arrangement/Emu/" "$MOUNT_POINT/Emu/" "-a"
      else
        echo -e "${RED}Emulator configuration directory not found${RESET}"
      fi
      
      # Install base ROMs (always do this for done-set-three)
      if [ -d "$SETS_DIR/done-set-three_202501/Done Set 3/Roms" ]; then
        echo -e "${CYN}Installing base ROM set...${RESET}"
        enhanced_rsync "$SETS_DIR/done-set-three_202501/Done Set 3/Roms/" "$MOUNT_POINT/Roms/" "-a"
      else
        echo -e "${RED}Base ROM directory not found${RESET}"
      fi
      
      # Install PS1 games if selected
      if [[ "$PS1_CHOICE" =~ ^[Yy]$ ]]; then
        if [ -d "$SETS_DIR/done-set-three_202501/PS1 Addon for 256gb SD Cards/Roms" ]; then
          echo -e "${CYN}Installing PS1 games...${RESET}"
          enhanced_rsync "$SETS_DIR/done-set-three_202501/PS1 Addon for 256gb SD Cards/Roms/" "$MOUNT_POINT/Roms/" "-a"
        else
          echo -e "${RED}PS1 ROM directory not found${RESET}"
        fi
      fi
      
      # Install artwork based on choice
      case "$BOXART_CHOICE" in
        "Miyoo Mix (Recommended)")
            if [ -d "$SETS_DIR/done-set-three_202501/Imgs (Miyoo Mix)" ]; then
                print_step "Installing Miyoo Mix art..."
                print_info "Skipping any existing box art files"
                enhanced_rsync "$SETS_DIR/done-set-three_202501/Imgs (Miyoo Mix)/Roms/" "$MOUNT_POINT/Roms/" "-a"
            else
                print_error "Miyoo Mix art directory not found"
            fi
            ;;
        "2D Box")
            if [ -d "$SETS_DIR/done-set-three_202501/Imgs (2D Box)" ]; then
                print_step "Installing 2D box art..."
                print_info "Skipping any existing box art files"
                enhanced_rsync "$SETS_DIR/done-set-three_202501/Imgs (2D Box)/Roms/" "$MOUNT_POINT/Roms/" "-a"
            else
                print_error "2D box art directory not found"
            fi
            ;;
        "2D Box and Screenshot")
            if [ -d "$SETS_DIR/done-set-three_202501/Imgs (2D Box and Screenshot)" ]; then
                print_step "Installing 2D box art and screenshots..."
                print_info "Skipping any existing box art files"
                enhanced_rsync "$SETS_DIR/done-set-three_202501/Imgs (2D Box and Screenshot)/Roms/" "$MOUNT_POINT/Roms/" "-a"
            else
                print_error "2D box art and screenshots directory not found"
            fi
            ;;
      esac
      ;;
  esac
fi

print_success "All steps complete!"

# Final unmount and eject
if [ -n "$MOUNT_POINT" ]; then
  print_step "Unmounting and ejecting device..."
  if command -v udisksctl &>/dev/null; then
    udisksctl unmount -b "/dev/${SELECTED_DEVICE}1" &>/dev/null
  else
    sudo umount "/dev/${SELECTED_DEVICE}1" &>/dev/null
  fi
  sudo eject "/dev/$SELECTED_DEVICE"
  print_success "Device ejected. You can now safely remove the SD card."
fi

