#!/usr/bin/env bash
# Fix DNS on Live/Autoinstall if systemd-resolved stub (127.0.0.53) is broken
# Idempotent, logs to /var/log/fix-dns.log

set -Eeuo pipefail

LOG="/var/log/fix-dns.log"
exec >>"$LOG" 2>&1
echo "[fix-dns] $(date -Is) start"

# Helper: quick DNS check
check_dns() {
  getent hosts archive.ubuntu.com >/dev/null 2>&1 && return 0
  getent hosts google.com >/dev/null 2>&1 && return 0
  return 1
}

# If DNS already works, do nothing
if check_dns; then
  echo "[fix-dns] DNS already OK"
  exit 0
fi

# Try to use systemd-resolved if present
if systemctl is-active --quiet systemd-resolved; then
  echo "[fix-dns] systemd-resolved is active, trying to rewire resolv.conf"
  if [ -f /run/systemd/resolve/resolv.conf ]; then
    ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf || true
  elif [ -f /run/systemd/resolve/stub-resolv.conf ]; then
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true
  fi
  systemctl restart systemd-resolved || true
  sleep 1
  if check_dns; then
    echo "[fix-dns] DNS fixed via systemd-resolved"
    exit 0
  else
    echo "[fix-dns] systemd-resolved path failed, will fallback to direct nameservers"
  fi
else
  echo "[fix-dns] systemd-resolved inactive"
fi

# Final fallback: write direct resolv.conf with public resolvers
echo "[fix-dns] Writing direct resolv.conf with 1.1.1.1 + 8.8.8.8"
rm -f /etc/resolv.conf
cat >/etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:2 attempts:2
EOF

# Re-check
if check_dns; then
  echo "[fix-dns] DNS fixed via direct resolv.conf"
  exit 0
else
  echo "[fix-dns] DNS still failing after fallback"
  exit 1
fi
