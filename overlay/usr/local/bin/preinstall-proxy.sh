#!/usr/bin/env bash
# Pré-configure un proxy HTTP/HTTPS AVANT le démarrage de Subiquity.
# - Détection "best effort" du réseau CNIEG (heuristiques)
# - Invite interactive (laisser vide pour ignorer)
# - Propagation à /etc/environment et APT (99proxy)
# - Exporte http_proxy/https_proxy pour le processus courant (visible par Subiquity/curtin)
set -Eeuo pipefail

CONFIG="/etc/environment"
APTCONF="/etc/apt/apt.conf.d/99proxy"
CLOUDCFG="/etc/cloud/cloud.cfg.d/99-proxy.cfg"
LOG="/var/log/preinstall-proxy.log"

exec >>"$LOG" 2>&1
echo "[preinstall-proxy] $(date -Is) start"

# -------- Heuristiques CNIEG (adapte si besoin) --------
is_cnieg() {
  # 1) Passerelle ou routes privées usuelles (ex: 10.200.0.0/16)
  if ip route | grep -Eq '(^default .* via 10\.200\.| 10\.200\.)'; then
    echo "[detect] default route or route in 10.200.0.0/16" ; return 0
  fi
  # 2) Adresse IP locale dans une plage interne CNIEG (ajoute/édite)
  if ip -4 addr show | grep -Eq 'inet 10\.200\.|inet 172\.20\.'; then
    echo "[detect] local IP in known CNIEG ranges" ; return 0
  fi
  # 3) DNS ou domaine comportant 'cnieg'
  if grep -qi 'cnieg' /etc/resolv.conf 2>/dev/null; then
    echo "[detect] resolv.conf mentions cnieg" ; return 0
  fi
  # 4) Résolveurs internes connus (exemple : 10.200.0.53)
  if grep -Eq 'nameserver[[:space:]]+10\.200\.' /etc/resolv.conf 2>/dev/null; then
    echo "[detect] internal nameserver 10.200.x.x" ; return 0
  fi
  return 1
}

default_proxy_for_cnieg() {
  # RENSEIGNE ici l’URL proxy officielle CNIEG si connue :
  # ex: echo "http://proxy.cnieg.fr:8080"
  echo "http://proxy.cnieg.fr:8080"
}

apply_proxy() {
  local px="$1"
  local no="localhost,127.0.0.1,::1,.local,.lan,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.cnieg.fr"
  echo "[apply] setting proxy to $px"

  # /etc/environment (pour tout le monde)
  sed -i '/^http_proxy=/d;/^https_proxy=/d;/^ftp_proxy=/d;/^no_proxy=/d' "$CONFIG" 2>/dev/null || true
  {
    echo "http_proxy=\"$px\""
    echo "https_proxy=\"$px\""
    echo "ftp_proxy=\"$px\""
    echo "no_proxy=\"$no\""
  } >> "$CONFIG"

  # APT
  cat >"$APTCONF" <<EOFAPT
Acquire::http::Proxy "$px";
Acquire::https::Proxy "$px";
EOFAPT

  # Cloud-init (pour que curtin/target en hérite au besoin)
  mkdir -p "$(dirname "$CLOUDCFG")"
  cat > "$CLOUDCFG" <<EOFCLOUD
# cloud-init proxy (propagé pendant l'install)
apt:
  proxy: "$px"
EOFCLOUD

  # Export immédiat pour le shell courant / Subiquity
  export http_proxy="$px"
  export https_proxy="$px"
  export ftp_proxy="$px"
  export no_proxy="$no"
}

# Si déjà configuré, ne rien refaire (idempotent)
if grep -qE '^http_proxy=' "$CONFIG" 2>/dev/null; then
  echo "[preinstall-proxy] proxy already present in $CONFIG, skipping"
  exit 0
fi

auto=""
if is_cnieg; then
  auto="$(default_proxy_for_cnieg)"
  echo "[preinstall-proxy] CNIEG heuristics matched → default proxy: $auto"
fi

# Affichage console (si accessible)
if [ -t 0 ] && [ -t 1 ]; then
  echo
  echo "=== Configuration proxy (optionnelle) ==="
  echo "Entrez une URL de proxy (ex: http://proxy.cnieg.fr:8080)"
  [ -n "$auto" ] && echo "(laisser vide pour utiliser la valeur détectée : $auto)"
  echo "(laisser vide pour ne pas utiliser de proxy)"
  echo
  read -rp "Proxy HTTP/HTTPS : " input || true
  if [ -z "${input:-}" ] && [ -n "$auto" ]; then
    input="$auto"
  fi
else
  # Pas de TTY : si auto détecté, on applique ; sinon on sort.
  input="${auto:-}"
fi

if [ -n "${input:-}" ]; then
  apply_proxy "$input"
  echo "[preinstall-proxy] proxy configured: $input"
else
  echo "[preinstall-proxy] no proxy configured"
fi

echo "[preinstall-proxy] done."
