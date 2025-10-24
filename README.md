# Build local – Ubuntu Live ISO (Packer + Ansible recipes)

## 1) Prérequis (Ubuntu/Debian)

Installer Packer via le dépôt HashiCorp + outils ISO :
```bash
sudo apt-get update
sudo apt-get install -y wget gpg lsb-release
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | \
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
sudo apt-get install -y packer xorriso squashfs-tools rsync wget \
  genisoimage isolinux syslinux-utils git ca-certificates
packer version
```

Installer Ansible depuis le PPA officiel recommandé :
```bash
sudo apt-get install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt-get install -y ansible
```

## 2) Variables ISO

Le fichier `variables.auto.pkrvars.hcl` est **chargé automatiquement** (par défaut Ubuntu Server 25.10 + SHA256 officiel).
Pour un ISO local : `ubuntu_iso_url = "file:///chemin/vers/ubuntu.iso"`.

## 3) Build local

```bash
packer fmt .
packer validate .
packer init .
packer build .
```

ISO générée : `output/ubuntu-live-custom.iso`.

## 4) Test rapide (QEMU)

```bash
qemu-system-x86_64 -m 4096 -smp 2 -enable-kvm \
  -cdrom output/ubuntu-live-custom.iso \
  -boot d
```

## 5) Notes

* Compatible 22.04 **et** 24.04+ (détection automatique du `.squashfs`).
* Reconstruction ISO hybride (BIOS/UEFI) via isolinux **ou** GRUB selon l’ISO source.
* À chaque push sur main / PR, l'ISO est construite et publiée en artefact CI.
* L’artefact CI exporte `output/ubuntu-live-custom.iso` (nom aligné avec le projet et le préfixe Packer).
* Menu **Ansible** proposé au **premier login** après installation (voir `overlay/etc/ansible/`).

## 6) Téléchargement de la dernière ISO CI

La dernière ISO générée par le workflow `Build ISO` (branche `main`) est disponible via **nightly.link** :

```
https://nightly.link/arnou/ubuntu-live-iso/workflows/build-iso/main/ubuntu-live-custom.zip
```

### Téléchargement automatisé

```bash
curl -L -o ubuntu-live-custom.zip \
  https://nightly.link/arnou/ubuntu-live-iso/workflows/build-iso/main/ubuntu-live-custom.zip
unzip ubuntu-live-custom.zip
ls -lh ubuntu-live-custom.iso
```

Le fichier ISO est empaqueté dans une archive ZIP (format standard des artefacts GitHub Actions).

