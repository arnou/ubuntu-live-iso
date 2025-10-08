# ubuntu-live-iso (Packer + Ansible recipes)

Ce dépôt construit une ISO Ubuntu Live personnalisée et propose un menu de recettes Ansible au premier login de l'OS installé.

## Build local
```bash
# Dépôt HashiCorp
sudo apt-get update
sudo apt-get install -y wget gpg lsb-release
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | \
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
sudo apt-get install -y packer xorriso squashfs-tools rsync wget genisoimage isolinux syslinux-utils git ca-certificates
packer init .
# Éditez variables.pkr.hcl (URL + SHA256)
packer build -var-file=variables.pkr.hcl .
```

ISO en sortie: `output/ubuntu-custom.iso`

## GitHub Actions
À chaque push sur main / PR, l'ISO est construite et publiée en artefact.
