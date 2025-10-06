#!/usr/bin/env bash
# Lance le menu Ansible au premier login interactif (hors session Live)
case "$-" in *i*) : ;; *) return ;; esac
[ -d /run/casper ] && return
[ -z "$PS1" ] && return
if [ ! -f /var/lib/ansible-recipes/first-login.done ]; then
  /usr/local/sbin/run-ansible-recipes.sh || true
fi
