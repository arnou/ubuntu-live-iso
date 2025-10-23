packer {
  required_version = ">= 1.10.0"
  required_plugins {
    ubuntu-live-custom = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/null"
    }
  }
}

variable "ubuntu_iso_url" {
  type = string
}

variable "ubuntu_iso_sha256" {
  type = string
}

variable "work_dir" {
  type    = string
  default = "work"
}

variable "output_iso" {
  type    = string
  default = "output/ubuntu-live-custom.iso"
}

variable "volume_label" {
  type    = string
  default = "Ubuntu-Custom"
}

source "ubuntu-live-custom" "iso" {
  communicator = "none"
}

build {
  sources = ["source.ubuntu-live-custom.iso"]

  provisioner "shell-local" {
    script = "${path.root}/scripts/build-custom-iso.sh"
    environment_vars = [
      "UBUNTU_ISO_URL=${var.ubuntu_iso_url}",
      "UBUNTU_ISO_SHA256=${var.ubuntu_iso_sha256}",
      "WORK_DIR=${var.work_dir}",
      "OUTPUT_ISO=${var.output_iso}",
      "VOLUME_LABEL=${var.volume_label}",
      "REPO_ROOT=${path.root}",
    ]
  }

  post-processor "shell-local" {
    inline = ["echo 'ISO disponible: ${var.output_iso}'"]
  }
}
