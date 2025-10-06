#!/usr/bin/env bash
set -Eeuo pipefail

[ -d /run/casper ] && exit 0

cat >/etc/motd <<'EOF'
Bienvenue sur l’Ubuntu installé personnalisé 🎯
(ceci n'est pas la session Live)
EOF

systemctl disable firstboot-custom.service || true
