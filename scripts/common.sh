#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf "[%(%F %T)T] %s\n" -1 "$*" >&2; }

need() {
  command -v "$1" >/dev/null 2>&1 || {
    log "Outil manquant: $1"
    exit 2
  }
}
