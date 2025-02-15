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

# Initialize variables
GITHUB_REPO="OnionUI/Onion"
LOGOTWEAK_REPO="schmurtzm/Miyoo-Mini-easy-logotweak"
ONION_PATH=""
LOGOTWEAK_PATH=""
BIOS_PATH="./BIOS"
SETS_DIR="./sets"
DEBUG_MODE=false

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
        rsync $flags -v --stats "$src" "$dst"
    else
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

check_and_install_prerequisites

print_banner

if [ ! -d "$BIOS_PATH" ]; then
  echo -e "${YEL}No BIOS folder found; skipping BIOS merge step.${RESET}"
fi

check_onion_version

mapfile -t USB_DISKS < <(lsblk -dno NAME,MODEL,TRAN,SIZE,TYPE | grep usb | awk '{print $1"||"$2" "$3" "$4" "$5}')
[ ${#USB_DISKS[@]} -eq 0 ] && echo -e "${RED}No USB disks found.${RESET}" && exit 1

echo -e "${CYN}Available USB devices:${RESET}"
PS3="Select the device you want to manage (q to quit): "
select ITEM in "${USB_DISKS[@]}"; do
  if [ "$REPLY" = "q" ]; then
    echo -e "${YEL}Exiting...${RESET}"
    exit 0
  fi
  [ -n "$ITEM" ] && break
done

SELECTED_DEVICE="$(cut -d"|" -f1 <<< "$ITEM")"

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

# Get initial mount point
MOUNT_POINT=$(find_mount_point "$SELECTED_DEVICE")

echo -e "${BOLD}Do you want to format /dev/$SELECTED_DEVICE? [y/N]:${RESET}"
read -r DO_FORMAT
if [[ "$DO_FORMAT" =~ ^[Yy]$ ]]; then
  echo -e "${RED}WARNING: This will wipe ALL data on /dev/$SELECTED_DEVICE!${RESET}"
  echo -e "Are you sure? [y/N]: "
  read -r CONFIRM
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    if ! command -v parted &>/dev/null; then
      sudo apt-get update
      sudo apt-get install -y parted
    fi
    # Unmount if mounted
    if [ -n "$MOUNT_POINT" ]; then
      if command -v udisksctl &>/dev/null; then
        udisksctl unmount -b "/dev/${SELECTED_DEVICE}1" &>/dev/null
      else
        sudo umount "/dev/${SELECTED_DEVICE}1" &>/dev/null
      fi
    fi
    echo -e "${CYN}Formatting SD card...${RESET}"
    sudo parted -s "/dev/$SELECTED_DEVICE" mklabel msdos
    sudo parted -s "/dev/$SELECTED_DEVICE" mkpart primary fat32 1MiB 100%
    sudo mkfs.vfat -F 32 -n "ONION" "/dev/${SELECTED_DEVICE}1"
    echo -e "${GRN}Formatting complete.${RESET}"
    echo -e "Remove and reinsert the SD card, then press ENTER."
    read -r
    # Update mount point after format and reinsertion
    MOUNT_POINT=$(find_mount_point "$SELECTED_DEVICE")
  fi
fi

# Always try to find mount point before operations
if [ -z "$MOUNT_POINT" ]; then
  MOUNT_POINT=$(find_mount_point "$SELECTED_DEVICE")
fi

if [ -d "$ONION_PATH" ]; then
  echo -e "${CYN}Would you like to install OnionOS from ${BOLD}$ONION_PATH${CYN}? [y/N]:${RESET}"
  read -r COPY_ONION
  if [[ "$COPY_ONION" =~ ^[Yy]$ ]]; then
    if [ -z "$MOUNT_POINT" ]; then
      echo -e "${RED}No mount point found for /dev/${SELECTED_DEVICE}1${RESET}"
      echo -e "Please make sure the device is properly inserted and mounted."
      exit 1
    fi
    
    # Create necessary directories
    mkdir -p "$MOUNT_POINT/Roms" "$MOUNT_POINT/Emu" "$MOUNT_POINT/BIOS" "$MOUNT_POINT/App"
    
    echo -e "${CYN}Installing OnionOS...${RESET}"
    enhanced_rsync "$ONION_PATH/" "$MOUNT_POINT/" "-a"
    
    echo -e "\n${GRN}OnionOS installation complete!${RESET}"
    echo -e "${YEL}Please follow these steps:${RESET}"
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
      echo -e "${GRN}Device ejected. You can now safely remove the SD card.${RESET}"
    fi
    
    read -r
    # Update mount point after reinsertion
    MOUNT_POINT=$(find_mount_point "$SELECTED_DEVICE")
  fi
fi

# Always try to find mount point before operations
if [ -z "$MOUNT_POINT" ]; then
  MOUNT_POINT=$(find_mount_point "$SELECTED_DEVICE")
fi

# Install Easy Logo Tweak regardless of OnionOS installation choice
if [ -n "$MOUNT_POINT" ]; then
  # Create App directory if it doesn't exist
  mkdir -p "$MOUNT_POINT/App"
  check_and_install_easy_logo_tweak "$MOUNT_POINT"
else
  echo -e "${RED}No mount point found for Easy Logo Tweak installation${RESET}"
  echo -e "Please make sure the device is properly inserted and mounted."
  exit 1
fi

if [ -d "$BIOS_PATH" ]; then
  echo -e "${CYN}Would you like to install BIOS files? [y/N]:${RESET}"
  read -r COPY_BIOS
  if [[ "$COPY_BIOS" =~ ^[Yy]$ ]]; then
    if [ -z "$MOUNT_POINT" ]; then
      echo -e "${RED}No mount point found for /dev/${SELECTED_DEVICE}1${RESET}"
      echo -e "Please make sure the device is properly inserted and mounted."
      exit 1
    fi
    echo -e "${CYN}Copying BIOS files...${RESET}"
    enhanced_rsync "$BIOS_PATH/" "$MOUNT_POINT/BIOS/" "-a"
    echo -e "${GRN}BIOS files installed successfully!${RESET}"
  fi
else
  echo -e "${YEL}No BIOS folder found; skipping BIOS installation.${RESET}"
fi

# Always try to find mount point before operations
if [ -z "$MOUNT_POINT" ]; then
  MOUNT_POINT=$(find_mount_point "$SELECTED_DEVICE")
fi

if [ -d "$SETS_DIR" ]; then
  echo -e "${CYN}Would you like to install a ROM pack? [y/N]${RESET}"
  read -r INSTALL_ROMS
  if [[ "$INSTALL_ROMS" =~ ^[Yy]$ ]]; then
    # Always try to find mount point before operations
    if [ -z "$MOUNT_POINT" ]; then
      MOUNT_POINT=$(find_mount_point "$SELECTED_DEVICE")
    fi
    
    if [ -z "$MOUNT_POINT" ]; then
      echo -e "${RED}No mount point found for /dev/${SELECTED_DEVICE}1${RESET}"
      echo -e "Please make sure the device is properly inserted and mounted."
      exit 1
    fi
    
    echo -e "${CYN}Available ROM packs:${RESET}"
    PS3="Select a ROM pack (q to quit): "
    select SET_CHOICE in \
      "done-set-three" \
      "tiny-best-set (main)" \
      "tiny-best-set-go (64 expansion)" \
      "tiny-best-set-go (128 expansion)" \
      "tiny-best-set (all expansions)"; do
      if [ "$REPLY" = "q" ]; then
        echo -e "${YEL}Skipping ROM installation...${RESET}"
        break
      fi
      
      # Reset PS3 to avoid menu prompt confusion
      PS3="Select option: "
      
      case "$REPLY" in
        1) # done-set-three
          echo -e "Which device model?"
          select MODEL_CHOICE in "Miyoo Plus" "Miyoo v4"; do
            [ -n "$MODEL_CHOICE" ] && break
          done
          
          echo "Include PS1 games? [y/N]"
          read -r PS1_YN
          
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
          if [[ "$PS1_YN" =~ ^[Yy]$ ]]; then
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
          
        2) # tiny-best-set (main)
          if [ -d "$SETS_DIR/tiny-best-set-go-games/Roms" ]; then
            echo -e "${CYN}Installing main ROM set...${RESET}"
            enhanced_rsync "$SETS_DIR/tiny-best-set-go-games/Roms/" "$MOUNT_POINT/Roms/" "-a"
          else
            echo -e "${RED}Main ROM set directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms" ]; then
            echo -e "${CYN}Installing artwork...${RESET}"
            enhanced_rsync "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms/" "$MOUNT_POINT/Roms/" "-a"
          else
            echo -e "${RED}Main artwork directory not found${RESET}"
          fi
          ;;
          
        3) # tiny-best-set-go (64 expansion)
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-64-games/Roms" ]; then
            echo -e "${CYN}Installing 64 expansion ROMs...${RESET}"
            enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-64-games/Roms/" "$MOUNT_POINT/Roms/" "-a"
          else
            echo -e "${RED}64 expansion ROM directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-64-imgs-onion/Roms" ]; then
            echo -e "${CYN}Installing 64 expansion artwork...${RESET}"
            enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-64-imgs-onion/Roms/" "$MOUNT_POINT/Roms/" "-a"
          else
            echo -e "${RED}64 expansion artwork directory not found${RESET}"
          fi
          ;;
          
        4) # tiny-best-set-go (128 expansion)
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-128-games/Roms" ]; then
            echo -e "${CYN}Installing 128 expansion ROMs...${RESET}"
            enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-128-games/Roms/" "$MOUNT_POINT/Roms/" "-a"
          else
            echo -e "${RED}128 expansion ROM directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-128-imgs-onion/Roms" ]; then
            echo -e "${CYN}Installing 128 expansion artwork...${RESET}"
            enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-128-imgs-onion/Roms/" "$MOUNT_POINT/Roms/" "-a"
          else
            echo -e "${RED}128 expansion artwork directory not found${RESET}"
          fi
          ;;
          
        5) # tiny-best-set (all expansions)
          if [ -d "$SETS_DIR/tiny-best-set-go-games/Roms" ]; then
            echo -e "${CYN}Installing main ROM set...${RESET}"
            enhanced_rsync "$SETS_DIR/tiny-best-set-go-games/Roms/" "$MOUNT_POINT/Roms/" "-a"
          else
            echo -e "${RED}Main ROM set directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms" ]; then
            echo -e "${CYN}Installing main artwork...${RESET}"
            enhanced_rsync "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms/" "$MOUNT_POINT/Roms/" "-a"
          else
            echo -e "${RED}Main artwork directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-64-games/Roms" ]; then
            echo -e "${CYN}Installing 64 expansion ROMs...${RESET}"
            enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-64-games/Roms/" "$MOUNT_POINT/Roms/" "-a"
          else
            echo -e "${RED}64 expansion ROM directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-64-imgs-onion/Roms" ]; then
            echo -e "${CYN}Installing 64 expansion artwork...${RESET}"
            enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-64-imgs-onion/Roms/" "$MOUNT_POINT/Roms/" "-a"
          else
            echo -e "${RED}64 expansion artwork directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-128-games/Roms" ]; then
            echo -e "${CYN}Installing 128 expansion ROMs...${RESET}"
            enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-128-games/Roms/" "$MOUNT_POINT/Roms/" "-a"
          else
            echo -e "${RED}128 expansion ROM directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-128-imgs-onion/Roms" ]; then
            echo -e "${CYN}Installing 128 expansion artwork...${RESET}"
            enhanced_rsync "$SETS_DIR/tiny-best-set-go-expansion-128-imgs-onion/Roms/" "$MOUNT_POINT/Roms/" "-a"
          else
            echo -e "${RED}128 expansion artwork directory not found${RESET}"
          fi
          ;;
      esac
      break
    done
  fi
fi

echo -e "${GRN}All steps complete.${RESET}"

# Final unmount and eject
if [ -n "$MOUNT_POINT" ]; then
  echo -e "${CYN}Unmounting and ejecting device...${RESET}"
  if command -v udisksctl &>/dev/null; then
    udisksctl unmount -b "/dev/${SELECTED_DEVICE}1" &>/dev/null
  else
    sudo umount "/dev/${SELECTED_DEVICE}1" &>/dev/null
  fi
  sudo eject "/dev/$SELECTED_DEVICE"
  echo -e "${GRN}Device ejected. You can now safely remove the SD card.${RESET}"
fi

