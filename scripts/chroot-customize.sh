#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends   ansible git whiptail vim htop network-manager net-tools wireless-tools wpasupplicant ca-certificates

# Activer le service first-boot pour motd installé (optionnel)
if systemctl list-unit-files | grep -q '^firstboot-custom.service'; then
  systemctl enable firstboot-custom.service || true
fi

# Nettoyage
apt-get clean
rm -rf /var/lib/apt/lists/*
