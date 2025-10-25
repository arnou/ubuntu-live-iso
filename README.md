# Ubuntu Live ISO – Build local (Packer + Ansible)

## Sommaire

1. [Présentation](#présentation)
2. [Prérequis](#prérequis-ubuntudebian)
3. [Variables Packer](#variables-packer)
4. [Compilation de l’ISO](#compilation-de-liso)
5. [Tests rapides avec QEMU](#tests-rapides-avec-qemu)
6. [Télécharger la dernière ISO CI](#télécharger-la-dernière-iso-ci)
7. [Feuille de route](#feuille-de-route)
8. [Snapshots automatiques Btrfs](#-snapshots-automatiques-btrfs)

---

## Présentation

Recettes Packer + Ansible pour construire une image Ubuntu Live personnalisée. Les builds sont exécutables localement et via CI, avec génération d’une ISO hybride (BIOS/UEFI) nommée `output/ubuntu-live-custom.iso`.

### Points clés

* Compatible Ubuntu 22.04, 24.04+ **et** 25.10 (détection automatique du `.squashfs`).
* Publication automatique de l’ISO via GitHub Actions (`Build ISO`).
* Menu **Ansible** disponible dès le premier login (voir `overlay/etc/ansible/`).

---

## Prérequis (Ubuntu/Debian)

### Installer Packer et les outils ISO

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

### Installer Ansible

```bash
sudo apt-get install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt-get install -y ansible
```

---

## Variables Packer

Le fichier `variables.auto.pkrvars.hcl` est **chargé automatiquement** (par défaut, Ubuntu Server 25.10 + SHA256 officiel).

Pour utiliser un ISO local :

```hcl
ubuntu_iso_url = "file:///chemin/vers/ubuntu.iso"
```

---

## Compilation de l’ISO

```bash
packer fmt .
packer validate .
packer init .
packer build .
```

L’ISO générée est disponible dans `output/ubuntu-live-custom.iso`.

---

## Tests rapides avec QEMU

Créer d’abord un disque virtuel (ex. 30 Go en qcow2) :

```bash
qemu-img create -f qcow2 disk.qcow2 30G
```

Lancer ensuite la machine virtuelle :

```bash
qemu-system-x86_64 -m 4096 -smp 2 -enable-kvm \
  -cdrom output/ubuntu-live-custom.iso -netdev user,id=n1 -device virtio-net,netdev=n1 \
  -monitor stdio -boot d \
  -drive file=disk.qcow2,if=virtio,format=qcow2
```

---

## Télécharger la dernière ISO CI

Le workflow GitHub Actions `Build ISO` (branche `main`) publie automatiquement une archive via **nightly.link** :

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

L’ISO est fournie dans une archive ZIP (format standard des artefacts GitHub Actions).

---

## Feuille de route

* Préparer les recettes Ansible pour intégrer les outils suivants (par usage) :
  * **Kubernetes & conteneurs** : kubectl, k9s, Docker.
  * **Runtimes & IDE** : SDKMAN!, IntelliJ IDEA, VSCodium.
  * **Bases de données** : psql.
  * **Terminal & accès distant** : Kitty, TigerVNC.
  * **Virtualisation** : QEMU.
  * **Sécurité** : antivirus (solution à déterminer).
  * **Outils divers** : Winboat (à préciser / documenter).
* Ajouter une déclinaison avec les environnements de bureau **KDE Plasma**, **GNOME**, **Xfce** et **Hyprland**.

---

# 📸 Snapshots automatiques Btrfs

## 🔍 Présentation

L’image Ubuntu custom configure automatiquement **Snapper** et **grub-btrfs** lors du premier démarrage du système installé.

* **Snapper** crée des snapshots Btrfs avant/après les mises à jour ou à intervalles réguliers.
* **btrfsmaintenance** nettoie et équilibre automatiquement le système de fichiers.
* **grub-btrfs** rend les snapshots accessibles depuis GRUB pour revenir à un état antérieur.

---

## ⚙️ Structure des sous-volumes

Le partitionnement automatique configure les sous-volumes suivants :

| Point de montage | Sous-volume | Description |
|------------------|-------------|-------------|
| `/`              | `@`         | Racine du système (snapshots visibles dans GRUB) |
| `/home`          | `@home`     | Données utilisateurs |
| `/var`           | `@var`      | Journaux, bases et caches |
| `/.snapshots`    | `@snapshots`| Stockage des snapshots système |

Les snapshots `/home` et `/var` sont également gérés par Snapper, mais **non affichés dans GRUB** (restauration manuelle uniquement).

---

## 🛠️ Services activés

| Service | Rôle |
|---------|------|
| `snapper-timeline.timer` | Crée automatiquement des snapshots à intervalles réguliers |
| `snapper-cleanup.timer` | Supprime les anciens snapshots selon la politique définie |
| `btrfsmaintenance-refresh.timer` | Planifie les tâches d’entretien (scrub, balance) |
| `btrfsmaintenance-balance.timer` | Rééquilibre automatiquement les blocs |
| `firstboot-snapper-setup.service` | Exécute la configuration initiale au premier boot |

---

## 📦 Localisation

| Élément | Chemin |
|---------|--------|
| Script d’initialisation | `/usr/local/sbin/firstboot-snapper-setup.sh` |
| Log d’exécution | `/var/log/firstboot-snapper-setup.log` |
| Configurations Snapper | `/etc/snapper/configs/{root,home,var}` |
| Snapshots | `/.snapshots/`, `/home/.snapshots/`, `/var/.snapshots/` |

---

## 🔄 Commandes utiles

### 📋 Lister les snapshots

```bash
sudo snapper -c root list
sudo snapper -c home list
sudo snapper -c var list
```
