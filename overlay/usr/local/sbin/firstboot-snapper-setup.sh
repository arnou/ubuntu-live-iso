#!/usr/bin/env bash
# Configure automatiquement Snapper + grub-btrfs au PREMIER boot du système installé.
set -Eeuo pipefail

LOG=/var/log/firstboot-snapper-setup.log
exec >>"$LOG" 2>&1
echo "[INFO] firstboot-snapper-setup: start at $(date -Is)"

# Ne rien faire en session live
[ -d /run/casper ] && { echo "[INFO] Live session detected. Exit."; exit 0; }

# Vérifier la disponibilité des commandes nécessaires
if ! command -v snapper >/dev/null 2>&1; then
  echo "[WARN] snapper command not available. Exit."
  exit 0
fi

if ! command -v btrfs >/dev/null 2>&1; then
  echo "[WARN] btrfs command not available. Exit."
  exit 0
fi

# Vérifier que la racine est bien sur Btrfs
if ! findmnt -n -o FSTYPE / | grep -qi btrfs; then
  echo "[WARN] Root filesystem is not Btrfs. Exit."
  exit 0
fi

# S'assurer que /.snapshots existe et est monté si présent dans fstab
mkdir -p /.snapshots
if ! mountpoint -q /.snapshots; then
  mount /.snapshots || true
fi

# Initialiser Snapper (idempotent)
if ! test -f /etc/snapper/configs/root; then
  echo "[INFO] snapper create-config /"
  snapper -c root create-config /
  # Politique par défaut : timeline ON, cleanup ON
  sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/' /etc/snapper/configs/root
  sed -i 's/^TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="yes"/' /etc/snapper/configs/root
  sed -i 's/^TIMELINE_MIN_AGE=.*/TIMELINE_MIN_AGE="1800"/' /etc/snapper/configs/root
  systemctl enable snapper-timeline.timer snapper-cleanup.timer || true
fi

# === Quotas Btrfs (aident snapper à nettoyer) ===
echo "[INFO] enabling btrfs quotas where applicable"
btrfs quota enable / || true
if findmnt -n -o FSTYPE /home | grep -qi btrfs; then
  btrfs quota enable /home || true
fi
if findmnt -n -o FSTYPE /var | grep -qi btrfs; then
  btrfs quota enable /var || true
fi

# === Configurations Snapper additionnelles pour /home et /var ===
# /home
if findmnt -n -o FSTYPE /home | grep -qi btrfs; then
  mkdir -p /home/.snapshots
  if [ ! -f /etc/snapper/configs/home ]; then
    echo "[INFO] snapper create-config /home"
    snapper -c home create-config /home
    sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/' /etc/snapper/configs/home
    sed -i 's/^TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="yes"/' /etc/snapper/configs/home
    sed -i 's/^TIMELINE_MIN_AGE=.*/TIMELINE_MIN_AGE="1800"/' /etc/snapper/configs/home
  fi
fi

# /var
if findmnt -n -o FSTYPE /var | grep -qi btrfs; then
  mkdir -p /var/.snapshots
  if [ ! -f /etc/snapper/configs/var ]; then
    echo "[INFO] snapper create-config /var"
    snapper -c var create-config /var
    sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/' /etc/snapper/configs/var
    sed -i 's/^TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="yes"/' /etc/snapper/configs/var
    sed -i 's/^TIMELINE_MIN_AGE=.*/TIMELINE_MIN_AGE="1800"/' /etc/snapper/configs/var
  fi
fi

# grub-btrfs : générer le menu qui inclut les snapshots
if command -v update-grub >/dev/null 2>&1; then
  update-grub || true
fi

echo "[OK] Snapper + grub-btrfs ready."
