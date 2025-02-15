#!/usr/bin/env bash

RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[0;33m'
BLU='\033[0;34m'
CYN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

ONION_PATH="./Onion-v4.3.1-1"
BIOS_PATH="./BIOS"
SETS_DIR="./sets"

check_and_install_prerequisites() {
  echo -e "${CYN}Checking prerequisites...${RESET}"
  
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
    echo -e "${RED}No supported package manager found (apt, dnf, or pacman)${RESET}"
    echo -e "${YEL}Please install the following packages manually:${RESET}"
    echo -e "- rsync\n- wget\n- curl\n- parted\n- udisks2"
    exit 1
  fi
  
  # Check sudo access
  if ! sudo -v; then
    echo -e "${RED}Sudo access is required to install missing packages${RESET}"
    exit 1
  fi
  
  local MISSING_PKGS=()
  
  # Check for required packages
  if ! command -v rsync &>/dev/null; then
    MISSING_PKGS+=("rsync")
  fi
  
  if ! command -v wget &>/dev/null; then
    MISSING_PKGS+=("wget")
  fi
  
  if ! command -v curl &>/dev/null; then
    MISSING_PKGS+=("curl")
  fi
  
  if ! command -v parted &>/dev/null; then
    MISSING_PKGS+=("parted")
  fi
  
  if ! command -v udisksctl &>/dev/null; then
    case $PKG_MANAGER in
      "apt")
        MISSING_PKGS+=("udisks2")
        ;;
      "dnf")
        MISSING_PKGS+=("udisks2")
        ;;
      "pacman")
        MISSING_PKGS+=("udisks2")
        ;;
    esac
  fi
  
  # Install missing packages if any
  if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${YEL}The following packages need to be installed:${RESET}"
    printf '%s\n' "${MISSING_PKGS[@]}"
    
    echo -e "${CYN}Updating package lists...${RESET}"
    if ! sudo $UPDATE_CMD; then
      echo -e "${RED}Failed to update package lists${RESET}"
      exit 1
    fi
    
    echo -e "${CYN}Installing missing packages...${RESET}"
    if ! sudo $INSTALL_CMD "${MISSING_PKGS[@]}"; then
      echo -e "${RED}Failed to install one or more packages${RESET}"
      exit 1
    fi
    
    echo -e "${GRN}Successfully installed all required packages${RESET}"
  else
    echo -e "${GRN}All required packages are already installed${RESET}"
  fi
}

check_and_install_prerequisites

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
    rsync -a --info=progress2 "$ONION_PATH"/ "$MOUNT_POINT"/
    
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
    rsync -a --info=progress2 "$BIOS_PATH"/ "$MOUNT_POINT/BIOS/"
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
          select BOXART_CHOICE in "2D Box" "2D Box and Screenshot" "Miyoo Mix"; do
            [ -n "$BOXART_CHOICE" ] && break
          done
          
          # Install ROMs based on model choice
          if [ "$MODEL_CHOICE" = "Miyoo Plus" ]; then
            if [ -d "$SETS_DIR/done-set-three_202501/Configs for Plus Model" ]; then
              echo -e "${CYN}Installing Miyoo Plus configurations...${RESET}"
              rsync -a --info=progress2 "$SETS_DIR/done-set-three_202501/Configs for Plus Model/RetroArch/" "$MOUNT_POINT/RetroArch/"
              rsync -a --info=progress2 "$SETS_DIR/done-set-three_202501/Configs for Plus Model/Saves/" "$MOUNT_POINT/Saves/"
            else
              echo -e "${RED}Configuration directory for Miyoo Plus not found${RESET}"
            fi
          elif [ "$MODEL_CHOICE" = "Miyoo v4" ]; then
            if [ -d "$SETS_DIR/done-set-three_202501/Configs for V4 Model" ]; then
              echo -e "${CYN}Installing Miyoo v4 configurations...${RESET}"
              rsync -a --info=progress2 "$SETS_DIR/done-set-three_202501/Configs for V4 Model/RetroArch/" "$MOUNT_POINT/RetroArch/"
              rsync -a --info=progress2 "$SETS_DIR/done-set-three_202501/Configs for V4 Model/Saves/" "$MOUNT_POINT/Saves/"
            else
              echo -e "${RED}Configuration directory for Miyoo v4 not found${RESET}"
            fi
          fi

          # Install emulator configurations
          if [ -d "$SETS_DIR/done-set-three_202501/Sensible Console Arrangement" ]; then
            echo -e "${CYN}Installing emulator configurations...${RESET}"
            rsync -a --info=progress2 "$SETS_DIR/done-set-three_202501/Sensible Console Arrangement/Emu/" "$MOUNT_POINT/Emu/"
          else
            echo -e "${RED}Emulator configuration directory not found${RESET}"
          fi
          
          # Install base ROMs (always do this for done-set-three)
          if [ -d "$SETS_DIR/done-set-three_202501/Done Set 3/Roms" ]; then
            echo -e "${CYN}Installing base ROM set...${RESET}"
            rsync -a --ignore-existing --info=progress2 "$SETS_DIR/done-set-three_202501/Done Set 3/Roms/" "$MOUNT_POINT/Roms/"
          else
            echo -e "${RED}Base ROM directory not found${RESET}"
          fi
          
          # Install PS1 games if selected
          if [[ "$PS1_YN" =~ ^[Yy]$ ]]; then
            if [ -d "$SETS_DIR/done-set-three_202501/PS1 Addon for 256gb SD Cards/Roms" ]; then
              echo -e "${CYN}Installing PS1 games...${RESET}"
              rsync -a --ignore-existing --info=progress2 "$SETS_DIR/done-set-three_202501/PS1 Addon for 256gb SD Cards/Roms/" "$MOUNT_POINT/Roms/"
            else
              echo -e "${RED}PS1 ROM directory not found${RESET}"
            fi
          fi
          
          # Install artwork based on choice
          case "$BOXART_CHOICE" in
            "2D Box")
              if [ -d "$SETS_DIR/done-set-three_202501/Imgs (2D Box)" ]; then
                echo -e "${CYN}Installing 2D box art...${RESET}"
                rsync -a --info=progress2 "$SETS_DIR/done-set-three_202501/Imgs (2D Box)/Roms/" "$MOUNT_POINT/Roms/"
              else
                echo -e "${RED}2D box art directory not found${RESET}"
              fi
              ;;
            "2D Box and Screenshot")
              if [ -d "$SETS_DIR/done-set-three_202501/Imgs (2D Box and Screenshot)" ]; then
                echo -e "${CYN}Installing 2D box art and screenshots...${RESET}"
                rsync -a --info=progress2 "$SETS_DIR/done-set-three_202501/Imgs (2D Box and Screenshot)/Roms/" "$MOUNT_POINT/Roms/"
              else
                echo -e "${RED}2D box art and screenshots directory not found${RESET}"
              fi
              ;;
            "Miyoo Mix")
              if [ -d "$SETS_DIR/done-set-three_202501/Imgs (Miyoo Mix)" ]; then
                echo -e "${CYN}Installing Miyoo Mix art...${RESET}"
                rsync -a --info=progress2 "$SETS_DIR/done-set-three_202501/Imgs (Miyoo Mix)/Roms/" "$MOUNT_POINT/Roms/"
              else
                echo -e "${RED}Miyoo Mix art directory not found${RESET}"
              fi
              ;;
          esac
          ;;
          
        2) # tiny-best-set (main)
          if [ -d "$SETS_DIR/tiny-best-set-go-games/Roms" ]; then
            echo -e "${CYN}Installing main ROM set...${RESET}"
            rsync -a --info=progress2 "$SETS_DIR/tiny-best-set-go-games/Roms/" "$MOUNT_POINT/Roms/"
          else
            echo -e "${RED}Main ROM set directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms" ]; then
            echo -e "${CYN}Installing artwork...${RESET}"
            rsync -a --info=progress2 "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms/" "$MOUNT_POINT/Roms/"
          else
            echo -e "${RED}Main artwork directory not found${RESET}"
          fi
          ;;
          
        3) # tiny-best-set-go (64 expansion)
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-64-games/Roms" ]; then
            echo -e "${CYN}Installing 64 expansion ROMs...${RESET}"
            rsync -a --info=progress2 "$SETS_DIR/tiny-best-set-go-expansion-64-games/Roms/" "$MOUNT_POINT/Roms/"
          else
            echo -e "${RED}64 expansion ROM directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-64-imgs-onion/Roms" ]; then
            echo -e "${CYN}Installing 64 expansion artwork...${RESET}"
            rsync -a --info=progress2 "$SETS_DIR/tiny-best-set-go-expansion-64-imgs-onion/Roms/" "$MOUNT_POINT/Roms/"
          else
            echo -e "${RED}64 expansion artwork directory not found${RESET}"
          fi
          ;;
          
        4) # tiny-best-set-go (128 expansion)
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-128-games/Roms" ]; then
            echo -e "${CYN}Installing 128 expansion ROMs...${RESET}"
            rsync -a --info=progress2 "$SETS_DIR/tiny-best-set-go-expansion-128-games/Roms/" "$MOUNT_POINT/Roms/"
          else
            echo -e "${RED}128 expansion ROM directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-128-imgs-onion/Roms" ]; then
            echo -e "${CYN}Installing 128 expansion artwork...${RESET}"
            rsync -a --info=progress2 "$SETS_DIR/tiny-best-set-go-expansion-128-imgs-onion/Roms/" "$MOUNT_POINT/Roms/"
          else
            echo -e "${RED}128 expansion artwork directory not found${RESET}"
          fi
          ;;
          
        5) # tiny-best-set (all expansions)
          if [ -d "$SETS_DIR/tiny-best-set-go-games/Roms" ]; then
            echo -e "${CYN}Installing main ROM set...${RESET}"
            rsync -a --info=progress2 "$SETS_DIR/tiny-best-set-go-games/Roms/" "$MOUNT_POINT/Roms/"
          else
            echo -e "${RED}Main ROM set directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms" ]; then
            echo -e "${CYN}Installing main artwork...${RESET}"
            rsync -a --info=progress2 "$SETS_DIR/tiny-best-set-go-imgs-onion/Roms/" "$MOUNT_POINT/Roms/"
          else
            echo -e "${RED}Main artwork directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-64-games/Roms" ]; then
            echo -e "${CYN}Installing 64 expansion ROMs...${RESET}"
            rsync -a --info=progress2 "$SETS_DIR/tiny-best-set-go-expansion-64-games/Roms/" "$MOUNT_POINT/Roms/"
          else
            echo -e "${RED}64 expansion ROM directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-64-imgs-onion/Roms" ]; then
            echo -e "${CYN}Installing 64 expansion artwork...${RESET}"
            rsync -a --info=progress2 "$SETS_DIR/tiny-best-set-go-expansion-64-imgs-onion/Roms/" "$MOUNT_POINT/Roms/"
          else
            echo -e "${RED}64 expansion artwork directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-128-games/Roms" ]; then
            echo -e "${CYN}Installing 128 expansion ROMs...${RESET}"
            rsync -a --info=progress2 "$SETS_DIR/tiny-best-set-go-expansion-128-games/Roms/" "$MOUNT_POINT/Roms/"
          else
            echo -e "${RED}128 expansion ROM directory not found${RESET}"
          fi
          if [ -d "$SETS_DIR/tiny-best-set-go-expansion-128-imgs-onion/Roms" ]; then
            echo -e "${CYN}Installing 128 expansion artwork...${RESET}"
            rsync -a --info=progress2 "$SETS_DIR/tiny-best-set-go-expansion-128-imgs-onion/Roms/" "$MOUNT_POINT/Roms/"
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

