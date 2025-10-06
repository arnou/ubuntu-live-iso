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

mkdir -p "${WORK_DIR}" "${MNT}" "${EXTRACT}" "${OUTDIR}"

log "Téléchargement ISO: ${UBUNTU_ISO_URL}"
if [ ! -f "${ISO_DL}" ]; then
  wget -O "${ISO_DL}" "${UBUNTU_ISO_URL}"
fi

log "Vérification SHA256"
echo "${UBUNTU_ISO_SHA256}  ${ISO_DL}" | sha256sum -c -

log "Montage ISO"
sudo mount -o loop "${ISO_DL}" "${MNT}"

log "Extraction ISO (sans squashfs)"
rsync -a --delete --exclude=/casper/filesystem.squashfs "${MNT}/" "${EXTRACT}/"

log "Extraction squashfs"
unsquashfs -d "${EDIT}" "${MNT}/casper/filesystem.squashfs"

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

# ---- Manifest & squashfs
log "Mise à jour filesystem.manifest"
sudo chroot "${EDIT}" dpkg-query -W --showformat='${Package} ${Version}\n' | sudo tee "${EXTRACT}/casper/filesystem.manifest" >/dev/null
sed 's/ubiquity.*//' "${EXTRACT}/casper/filesystem.manifest" | sed '/^$/d' | sudo tee "${EXTRACT}/casper/filesystem.manifest-desktop" >/dev/null

log "Reconstruction squashfs"
sudo mksquashfs "${EDIT}" "${EXTRACT}/casper/filesystem.squashfs" -comp xz -b 1048576

log "Taille filesystem"
printf $(sudo du -sx --block-size=1 "${EDIT}" | cut -f1) | sudo tee "${EXTRACT}/casper/filesystem.size" >/dev/null

# ---- Reconstruction ISO hybride (BIOS+UEFI)
log "Reconstruction ISO hybride avec xorriso"
pushd "${EXTRACT}" >/dev/null

ISOHYBRID_MBR="isolinux/isohdpfx.bin"
[ -f "${ISOHYBRID_MBR}" ] || ISOHYBRID_MBR="boot/grub/i386-pc/boot_hybrid.img"

if [ ! -f "isolinux/isolinux.bin" ]; then
  log "isolinux/isolinux.bin introuvable — votre ISO source ne l’emploie peut-être pas."
fi
if [ ! -f "boot/grub/efi.img" ]; then
  log "boot/grub/efi.img introuvable — UEFI pourrait ne pas booter."
fi

sudo xorriso -as mkisofs   -r -V "${VOLUME_LABEL}"   -o "../$(basename "${OUTPUT_ISO}")"   -J -l -cache-inodes   ${ISOHYBRID_MBR:+-isohybrid-mbr ${ISOHYBRID_MBR}}   -b isolinux/isolinux.bin     -c isolinux/boot.cat     -no-emul-boot -boot-load-size 4 -boot-info-table   -eltorito-alt-boot     -e boot/grub/efi.img     -no-emul-boot   -isohybrid-gpt-basdat -isohybrid-apm-hfsplus   .

popd >/dev/null

mv "${WORK_DIR}/extract/$(basename "${OUTPUT_ISO}")" "${OUTPUT_ISO}"

log "Terminé. ISO générée: ${OUTPUT_ISO}"
