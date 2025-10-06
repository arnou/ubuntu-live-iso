# ubuntu-live-iso (Packer + Ansible recipes)

Ce dépôt construit une ISO Ubuntu Live personnalisée et propose un menu de recettes Ansible au premier login de l'OS installé.

## Build local
```bash
sudo apt-get update
sudo apt-get install -y packer xorriso squashfs-tools rsync wget genisoimage isolinux syslinux-utils git ca-certificates
packer init .
# Éditez variables.pkr.hcl (URL + SHA256)
packer build -var-file=variables.pkr.hcl .
```

ISO en sortie: `output/ubuntu-custom.iso`

## GitHub Actions
À chaque push sur main / PR, l'ISO est construite et publiée en artefact.
