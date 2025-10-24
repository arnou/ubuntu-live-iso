#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

# Ensure universe/multiverse repositories are enabled.
# Ubuntu Server installers ship with only main enabled by default, so packages
# like ansible (and dependencies such as sshpass/python3-paramiko pulled in by
# the PPA) are otherwise missing, which is what the previous CI failure showed.
component_configured() {
  local component="$1" file word_boundary

  word_boundary="(^|[^A-Za-z0-9+_.-])${component}([^A-Za-z0-9+_.-]|$)"

  if [ -f /etc/apt/sources.list ] && \
    grep -Eq "^[[:space:]]*[^#].*${word_boundary}" /etc/apt/sources.list; then
    return 0
  fi

  shopt -s nullglob
  for file in /etc/apt/sources.list.d/*.list; do
    if grep -Eq "^[[:space:]]*[^#].*${word_boundary}" "${file}"; then
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob

  if python3 - "$component" <<'PY'
import re
import sys
from pathlib import Path

component = sys.argv[1].lower()
pattern = re.compile(r'^\s*components?:.*\b' + re.escape(component) + r'\b', re.I | re.M)

for path in Path('/etc/apt/sources.list.d').glob('*.sources'):
    try:
        text = path.read_text()
    except FileNotFoundError:
        continue

    # Merge continuation lines and drop comments so that multi-line values are
    # easier to match using the regex above.
    text = re.sub(r'\n[ \t]+', ' ', text)
    cleaned_lines = []
    for line in text.splitlines():
        cleaned_lines.append(line.split('#', 1)[0])
    cleaned = '\n'.join(cleaned_lines)

    if pattern.search(cleaned):
        sys.exit(0)

sys.exit(1)
PY
  then
    return 0
  fi

  return 1
}

missing_components=()
for component in universe multiverse; do
  if ! component_configured "${component}"; then
    missing_components+=("${component}")
  fi
done

if ((${#missing_components[@]})); then
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  fi
  CODENAME="${CODENAME:-$(lsb_release -cs 2>/dev/null || true)}"
  if [ -n "${CODENAME}" ]; then
    {
      echo "# Added by chroot-customize.sh to provide universe/multiverse packages"
      for component in "${missing_components[@]}"; do
        echo "deb http://archive.ubuntu.com/ubuntu ${CODENAME} ${component}"
        echo "deb http://archive.ubuntu.com/ubuntu ${CODENAME}-updates ${component}"
      done
    } >/etc/apt/sources.list.d/universe-multiverse.list
  fi
else
  rm -f /etc/apt/sources.list.d/universe-multiverse.list
fi

apt-get update

# Install software-properties-common so add-apt-repository is available, then
# enable the Ansible PPA to get the latest ansible meta package even on interim
# releases where the main archive may lag behind.
apt-get install -y --no-install-recommends software-properties-common
if ! add-apt-repository --yes --update ppa:ansible/ansible; then
  echo "Warning: unable to enable ppa:ansible/ansible; continuing without it" >&2
  apt-get update
fi

PACKAGES=(
  ansible
  git
  whiptail
  vim
  htop
  network-manager
  net-tools
  iw
  wpasupplicant
  ca-certificates
  locales
  console-setup
  keyboard-configuration
)

apt-get install -y --no-install-recommends "${PACKAGES[@]}"

locale-gen fr_FR.UTF-8
update-locale LANG=fr_FR.UTF-8

# Fix privileges for sudo / sudo-rs
if [ -x /usr/bin/sudo-rs ]; then
    chown root:root /usr/bin/sudo-rs || true
    chmod 4755 /usr/bin/sudo-rs || true
fi
if [ -x /usr/bin/sudo ]; then
    chown root:root /usr/bin/sudo || true
    chmod 4755 /usr/bin/sudo || true
fi


# Activer le service first-boot pour motd installé (optionnel)
if systemctl list-unit-files | grep -q '^firstboot-custom.service'; then
  systemctl enable firstboot-custom.service || true
fi

# Nettoyage
apt-get clean
rm -rf /var/lib/apt/lists/*
