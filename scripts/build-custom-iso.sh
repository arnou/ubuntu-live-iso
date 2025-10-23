#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

: "${UBUNTU_ISO_URL:?}"
: "${UBUNTU_ISO_SHA256:?}"
: "${WORK_DIR:=work}"
: "${OUTPUT_ISO:=output/ubuntu-custom.iso}"
: "${VOLUME_LABEL:=Ubuntu-Custom}"
: "${REPO_ROOT:?}"

need wget
need sha256sum
need rsync
need unsquashfs
need mksquashfs
need xorriso
need sed
need awk
need sudo

ISO_DL="${WORK_DIR}/ubuntu.iso"
MNT="${WORK_DIR}/mnt"
EXTRACT="${WORK_DIR}/extract"
EDIT="${WORK_DIR}/edit"
OUTDIR="$(dirname "${OUTPUT_ISO}")"

mkdir -p "${WORK_DIR}" "${OUTDIR}"

if mountpoint -q "${MNT}"; then
  sudo umount "${MNT}" || true
fi

sudo rm -rf "${MNT}" "${EXTRACT}" "${EDIT}"
mkdir -p "${MNT}" "${EXTRACT}" "${EDIT}"
sudo chown -R "$(id -u):$(id -g)" "${WORK_DIR}" "${OUTDIR}" 2>/dev/null || true

log "Téléchargement ISO: ${UBUNTU_ISO_URL}"
if [ ! -f "${ISO_DL}" ]; then
  wget -nv -O "${ISO_DL}" "${UBUNTU_ISO_URL}"
fi

log "Vérification SHA256"
echo "${UBUNTU_ISO_SHA256}  ${ISO_DL}" | sha256sum -c -

log "Montage ISO"
sudo mount -o loop "${ISO_DL}" "${MNT}"

# --- Copier l'ISO pour modification locale
log "Extraction ISO (tous les fichiers)"
sudo rsync -a --delete "${MNT}/" "${EXTRACT}/"
sudo chown -R "$(id -u):$(id -g)" "${EXTRACT}"

# --- Détecter le SquashFS à modifier (priorité non-*live*, sinon le plus volumineux)
CASPER_DIR="${MNT}/casper"
if [ ! -d "${CASPER_DIR}" ]; then
  echo "[ERR] ${CASPER_DIR} introuvable dans l'ISO"; ls -la "${MNT}" || true; sudo umount "${MNT}"; exit 1
fi

mapfile -t ALL_SQUASHFS < <(find "${CASPER_DIR}" -maxdepth 1 -type f -name '*.squashfs' | sort || true)
if [ ${#ALL_SQUASHFS[@]} -eq 0 ]; then
  echo "[ERR] Aucun .squashfs trouvé dans ${CASPER_DIR}"; ls -la "${CASPER_DIR}" || true; sudo umount "${MNT}"; exit 1
fi

CANDIDATES=()
for f in "${ALL_SQUASHFS[@]}"; do
  [[ "${f}" == *live* ]] && continue
  CANDIDATES+=("${f}")
done
# Si rien sans 'live', on prend la liste complète
if [ ${#CANDIDATES[@]} -eq 0 ]; then
  CANDIDATES=("${ALL_SQUASHFS[@]}")
fi

SQUASHFS_SRC=""
MAX=0
for f in "${CANDIDATES[@]}"; do
  sz=$(stat -c '%s' "$f" 2>/dev/null || stat -f '%z' "$f" 2>/dev/null || echo 0)
  if [ "$sz" -gt "$MAX" ]; then
    MAX="$sz"; SQUASHFS_SRC="$f"
  fi

done
if [ -z "${SQUASHFS_SRC}" ]; then
  echo "[ERR] Impossible de sélectionner un .squashfs"; sudo umount "${MNT}"; exit 1
fi
BASE="$(basename "${SQUASHFS_SRC}" .squashfs)"
echo "[INFO] SquashFS choisi: ${SQUASHFS_SRC} (base=${BASE})"

# --- Décompression du SquashFS sélectionné ---
log "Extraction squashfs -> ${EDIT}"
sudo rm -rf "${EDIT}"
mkdir -p "${EDIT}"
sudo unsquashfs -d "${EDIT}" "${SQUASHFS_SRC}"
sudo chown -R "$(id -u):$(id -g)" "${EDIT}"

log "Démontage ISO"
sudo umount "${MNT}"

# ---- Superposition overlay -> rootfs
if [ -d "${REPO_ROOT}/overlay" ]; then
  log "Copie overlay/ -> EDIT"
  rsync -a "${REPO_ROOT}/overlay/" "${EDIT}/"
fi

# ---- Préparation chroot
log "Préparation chroot"
sudo mount --bind /dev  "${EDIT}/dev"
sudo mount -t proc none "${EDIT}/proc"
sudo mount -t sysfs none "${EDIT}/sys"
sudo mount -t devpts none "${EDIT}/dev/pts"

# Copie script de customisation chroot
sudo install -m 0755 "${SCRIPT_DIR}/chroot-customize.sh" "${EDIT}/root/chroot-customize.sh"

log "Exécution chroot-customize.sh dans le chroot"
sudo chroot "${EDIT}" /bin/bash -c "
  set -Eeuo pipefail
  export DEBIAN_FRONTEND=noninteractive
  /root/chroot-customize.sh
"

# ---- Nettoyage chroot
log "Nettoyage chroot"
sudo chroot "${EDIT}" /bin/bash -c "
  umount /proc || true
  umount /sys  || true
  umount /dev/pts || true
" || true
sudo umount "${EDIT}/dev" || true

# ---- Manifest(s) & squashfs
if [ -f "${EXTRACT}/casper/${BASE}.manifest" ]; then
  log "Mise à jour casper/${BASE}.manifest"
  sudo chroot "${EDIT}" dpkg-query -W --showformat='${Package} ${Version}\n' | sudo tee "${EXTRACT}/casper/${BASE}.manifest" >/dev/null
elif [ -f "${EXTRACT}/casper/filesystem.manifest" ]; then
  log "Mise à jour casper/filesystem.manifest"
  sudo chroot "${EDIT}" dpkg-query -W --showformat='${Package} ${Version}\n' | sudo tee "${EXTRACT}/casper/filesystem.manifest" >/dev/null
  if [ -f "${EXTRACT}/casper/filesystem.manifest-desktop" ]; then
    sed 's/ubiquity.*//' "${EXTRACT}/casper/filesystem.manifest" | sed '/^$/d' | sudo tee "${EXTRACT}/casper/filesystem.manifest-desktop" >/dev/null
  fi
else
  log "Aucun manifest reconnu à mettre à jour (ok pour certaines variantes 24.04)"
fi

log "Reconstruction squashfs -> casper/${BASE}.squashfs"
sudo rm -f "${EXTRACT}/casper/${BASE}.squashfs"
sudo mksquashfs "${EDIT}" "${EXTRACT}/casper/${BASE}.squashfs" -comp xz -b 1048576

log "Taille filesystem -> casper/${BASE}.size"
printf '%s' "$(sudo du -sx --block-size=1 "${EDIT}" | cut -f1)" | sudo tee "${EXTRACT}/casper/${BASE}.size" >/dev/null

# ---- Reconstruction ISO hybride (BIOS+UEFI) : détecter isolinux vs GRUB
log "Reconstruction ISO hybride avec xorriso"
pushd "${EXTRACT}" >/dev/null

BIOS_OPTS=""
EFI_OPTS=""
ISOHYBRID_MBR=""

if [ -f "isolinux/isolinux.bin" ]; then
  BIOS_OPTS="-b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table"
  if [ -f "isolinux/isohdpfx.bin" ]; then
    ISOHYBRID_MBR="isolinux/isohdpfx.bin"
  fi
elif [ -f "boot/grub/i386-pc/eltorito.img" ]; then
  BIOS_OPTS="-b boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table"
  if [ -f "boot/grub/i386-pc/boot_hybrid.img" ]; then
    ISOHYBRID_MBR="boot/grub/i386-pc/boot_hybrid.img"
  fi
fi

if [ -f "boot/grub/efi.img" ]; then
  EFI_OPTS="-eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot"
elif [ -f "efi.img" ]; then
  EFI_OPTS="-eltorito-alt-boot -e efi.img -no-emul-boot"
fi

if [ -z "$BIOS_OPTS" ] && [ -z "$EFI_OPTS" ]; then
  echo "[ERR] Aucun chargeur BIOS/UEFI détecté."
  popd >/dev/null
  exit 1
fi

CMD=(xorriso -as mkisofs -r -V "${VOLUME_LABEL}" -o "../$(basename "${OUTPUT_ISO}")" -J -l -cache-inodes)
if [ -n "${ISOHYBRID_MBR}" ]; then
  CMD+=(-isohybrid-mbr "${ISOHYBRID_MBR}")
fi
if [ -n "${BIOS_OPTS}" ]; then
  # shellcheck disable=SC2206
  CMD+=(${BIOS_OPTS})
fi
if [ -n "${EFI_OPTS}" ]; then
  # shellcheck disable=SC2206
  CMD+=(${EFI_OPTS})
fi
CMD+=(-isohybrid-gpt-basdat -isohybrid-apm-hfsplus .)

sudo "${CMD[@]}"
popd >/dev/null

sudo mv "${WORK_DIR}/extract/$(basename "${OUTPUT_ISO}")" "${OUTPUT_ISO}"
sudo chown "$(id -u):$(id -g)" "${OUTPUT_ISO}"

log "Terminé. ISO générée: ${OUTPUT_ISO}"
