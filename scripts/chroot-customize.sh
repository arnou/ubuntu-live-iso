#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

# Ensure universe/multiverse repositories are enabled (required for ansible et al.)
if ! grep -Eq '^[^#].*\buniverse\b' /etc/apt/sources.list; then
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  fi
  CODENAME="${CODENAME:-$(lsb_release -cs 2>/dev/null || true)}"
  if [ -n "${CODENAME}" ]; then
    cat <<EOF_UNIVERSE >/etc/apt/sources.list.d/universe-multiverse.list
# Added by chroot-customize.sh to provide universe/multiverse packages
deb http://archive.ubuntu.com/ubuntu ${CODENAME} universe
deb http://archive.ubuntu.com/ubuntu ${CODENAME}-updates universe
deb http://archive.ubuntu.com/ubuntu ${CODENAME} multiverse
deb http://archive.ubuntu.com/ubuntu ${CODENAME}-updates multiverse
EOF_UNIVERSE
  fi
fi

apt-get update

PACKAGES=(
  ansible-core
  git
  whiptail
  vim
  htop
  network-manager
  net-tools
  iw
  wpasupplicant
  ca-certificates
)

apt-get install -y --no-install-recommends "${PACKAGES[@]}"

# Activer le service first-boot pour motd installé (optionnel)
if systemctl list-unit-files | grep -q '^firstboot-custom.service'; then
  systemctl enable firstboot-custom.service || true
fi

# Nettoyage
apt-get clean
rm -rf /var/lib/apt/lists/*
