#!/bin/bash

set -e

# Set non-interactive frontend for APT operations
export DEBIAN_FRONTEND=noninteractive

# Check and install required dependencies
check_dependencies() {
  echo "Checking for required dependencies (curl, gpg)..."
  MISSING_PACKAGES=()
  command -v curl >/dev/null 2>&1 || MISSING_PACKAGES+=("curl")
  command -v gpg >/dev/null 2>&1 || MISSING_PACKAGES+=("gpg")

  if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    echo "Installing missing dependencies: ${MISSING_PACKAGES[*]}"
    apt update --assume-yes
    apt install --assume-yes "${MISSING_PACKAGES[@]}" || echo "Failed to install some dependencies. Continuing anyway."
  fi

  echo "Downloading Docker GPG key..."
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --batch --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || {
    echo "Failed to download and save Docker GPG key. Continuing without Docker repository."
  }
}

# Function to update sources.list based on version
update_sources_list() {
  local version=$1
  local count

  count=$(grep -Evc '^\s*#' /etc/apt/sources.list | grep -c "debian.org/debian" /etc/apt/sources.list || true)

  if [ "$count" -ge 1 ]; then
    echo "'debian.org/debian' appears $count times in uncommented lines of sources.list. Proceeding with replacement."
  else
    echo "The current sources.list does not contain 'debian.org/debian' on any uncommented lines."
    echo "Contents of /etc/apt/sources.list:" >&2
    cat /etc/apt/sources.list
    read -p "Do you want to replace the contents of sources.list? (y/n): " REPLACE
    if [[ ! $REPLACE =~ ^[Yy]$ ]]; then
      echo "Exiting without modifying sources.list."
      exit 1
    fi
  fi

  echo "Updating sources.list to use custom repositories for Debian $version..."

  case $version in
    bullseye)
      cat <<EOF > /etc/apt/sources.list
deb [trusted=yes] https://registry.vnocsymphony.com/repos/apt-mirror/mirror/ftp.us.debian.org/debian bullseye main contrib non-free

deb [trusted=yes] https://registry.vnocsymphony.com/repos/apt-mirror/mirror/ftp.us.debian.org/debian bullseye-updates main contrib non-free

deb [trusted=yes] https://registry.vnocsymphony.com/repos/apt-mirror/mirror/deb.debian.org/debian-security bullseye-security main contrib non-free
EOF
      ;;
    bookworm)
      cat <<EOF > /etc/apt/sources.list
deb [trusted=yes] https://registry.vnocsymphony.com/repos/apt-mirror/mirror/ftp.us.debian.org/debian bookworm main contrib non-free non-free-firmware

deb [trusted=yes] https://registry.vnocsymphony.com/repos/apt-mirror/mirror/ftp.us.debian.org/debian bookworm-updates main contrib non-free non-free-firmware

deb [trusted=yes] https://registry.vnocsymphony.com/repos/apt-mirror/mirror/ftp.us.debian.org/debian bookworm-backports main contrib non-free non-free-firmware

deb [trusted=yes] https://registry.vnocsymphony.com/repos/apt-mirror/mirror/deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware

deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://registry.vnocsymphony.com/repos/apt-mirror/mirror/download.docker.com/linux/debian bookworm stable
EOF
      ;;
    *)
      echo "Unsupported version: $version"
      exit 1
      ;;
  esac
}

# Check if the system is running Debian
if ! grep -qi "debian" /etc/os-release; then
  echo "This script is only for Debian-based systems. Exiting."
  exit 1
fi

if [ ! -f /usr/share/keyrings/docker-archive-keyring.gpg ]; then
  echo "Downloading Docker GPG key..."
  wget https://registry.vnocsymphony.com/cpx/downloads/docker-archive-keyring.gpg -O /usr/share/keyrings/docker-archive-keyring.gpg || {
    # Check and install dependencies
    check_dependencies
  }
else
  echo "Docker GPG key already exists @/usr/share/keyrings/docker-archive-keyring.gpg skipping download."
fi

# Get Debian version
DEBIAN_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'=' -f2 | tr -d '"')

case $DEBIAN_VERSION in
  10)
    echo "Debian 10 (Buster) detected. Upgrading to 11 (Bullseye)..."
    update_sources_list "bullseye"
    ;;
  11)
    echo "Debian 11 (Bullseye) detected. Upgrading to 12 (Bookworm)..."
    update_sources_list "bookworm"
    ;;
  12)
    echo "Debian 12 (Bookworm) detected. Staying on current version, but updating any apps that can be updated..."
    ;;
  *)
    echo "Unsupported Debian version: $DEBIAN_VERSION. Exiting."
    exit 1
    ;;
esac

# Remove the old additional source from the 2020 OVA (if it exists)
if [ -f /etc/apt/sources.list.d/deb_debian_org_debian.list ]; then
  echo "File exists. Deleting /etc/apt/sources.list.d/deb_debian_org_debian.list..."
  rm /etc/apt/sources.list.d/deb_debian_org_debian.list
fi

# Perform updates and upgrades
echo "Running apt update and upgrades..."
apt update --assume-yes
apt upgrade --without-new-pkgs --assume-yes
apt full-upgrade --assume-yes
apt --purge autoremove --assume-yes

# Reset DEBIAN_FRONTEND
unset DEBIAN_FRONTEND

# Prompt for reboot if a full version upgrade was performed
if [[ $DEBIAN_VERSION == 10 || $DEBIAN_VERSION == 11 ]]; then
  echo "###############################################"
echo "# Full version upgrade complete. Reboot now? #"
echo "###############################################"
read -p "(y/n): " REBOOT
  if [[ $REBOOT =~ ^[Yy]$ ]]; then
    echo "Rebooting..."
    reboot
  else
    echo "Please reboot manually later to apply changes."
  fi
fi

echo "Script execution complete."
