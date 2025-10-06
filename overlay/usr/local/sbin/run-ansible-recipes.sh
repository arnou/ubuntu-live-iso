#!/usr/bin/env bash
set -Eeuo pipefail

MARKER="/var/lib/ansible-recipes/first-login.done"
CONF="/etc/ansible/recipes.conf"
LIST="/etc/ansible/recipes.list"
LOG="/var/log/ansible-recipes.log"

exec >>"$LOG" 2>&1

[ -d /run/casper ] && exit 0
[[ $- != *i* ]] && exit 0
[ -f "$MARKER" ] && exit 0

if [ -f "$CONF" ]; then . "$CONF"; else
  echo "[ERR] $CONF introuvable"; exit 1
fi

command -v whiptail >/dev/null || { echo "[ERR] whiptail manquant"; exit 1; }
command -v ansible-pull >/dev/null || { echo "[ERR] ansible manquant"; exit 1; }
command -v git >/dev/null || { echo "[ERR] git manquant"; exit 1; }

sec=${NETWORK_WAIT:-0}
while (( sec > 0 )); do
  ping -c1 -W1 8.8.8.8 >/dev/null 2>&1 && break
  sleep 1; sec=$((sec-1))
endone

mkdir -p "$(dirname "$MARKER")" "$WORKDIR"

mapfile -t lines < <(grep -vE '^\s*#|^\s*$' "$LIST" || true)
if [ ${#lines[@]} -eq 0 ]; then
  touch "$MARKER"; exit 0
fi

CHECKLIST=()
declare -A REC
i=0
for l in "${lines[@]}"; do
  IFS='|' read -r id label playbook tags xvars <<<"$l"
  REC["$i,id"]="$id"
  REC["$i,label"]="$label"
  REC["$i,playbook"]="$playbook"
  REC["$i,tags"]="$tags"
  REC["$i,xvars"]="$xvars"
  CHECKLIST+=("$i" "$label" "off")
  i=$((i+1))
done

CHOICES=$(whiptail --title "Personnalisation Ansible" --checklist   "Sélectionnez les recettes à appliquer (Espace pour cocher, Entrée pour valider):"   20 90 12   "${CHECKLIST[@]}" 3>&1 1>&2 2>&3) || {
    touch "$MARKER"; exit 0; }

if [ -z "${REPO_URL:-}" ]; then
  echo "[ERR] REPO_URL non défini dans $CONF"; exit 1
fi
if [ -d "$WORKDIR/repo/.git" ]; then
  git -C "$WORKDIR/repo" fetch --all --prune
  git -C "$WORKDIR/repo" checkout "$BRANCH"
  git -C "$WORKDIR/repo" reset --hard "origin/$BRANCH"
else
  git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$WORKDIR/repo"
fi

if [ -f "$WORKDIR/repo/requirements.yml" ]; then
  ansible-galaxy install -r "$WORKDIR/repo/requirements.yml"
fi

EV_GLOBAL=()
[ -n "${EXTRA_VARS:-}" ] && [ -f "$EXTRA_VARS" ] && EV_GLOBAL=(--extra-vars "@$EXTRA_VARS")

STATUS=0
for idx in $CHOICES; do
  key=$(echo "$idx" | tr -d '"')
  id="${REC[$key,id]}"
  playbook="${REC[$key,playbook]}"
  tags="${REC[$key,tags]}"
  xvars="${REC[$key,xvars]}"

  CMD=(ansible-pull
    --directory "$WORKDIR/repo"
    --checkout "$BRANCH"
    --url "$REPO_URL"
    --inventory "$INVENTORY"
    "$playbook"
  )
  [ -n "$tags" ] && CMD+=(--tags "$tags")
  [ ${#EV_GLOBAL[@]} -gt 0 ] && CMD+=("${EV_GLOBAL[@]}")
  [ -n "$xvars" ] && [ -f "$xvars" ] && CMD+=(--extra-vars "@$xvars")

  echo "[RUN] ($id) ${CMD[*]}"
  if ! "${CMD[@]}"; then
    echo "[ERR] Recette '$id' en échec"
    STATUS=1
  else
    echo "[OK] Recette '$id' terminée"
  fi
done

touch "$MARKER"

if [ $STATUS -ne 0 ]; then
  whiptail --title "Ansible" --msgbox "Certaines recettes ont échoué. Consultez $LOG" 10 80
else
  whiptail --title "Ansible" --msgbox "Personnalisation terminée avec succès." 10 60
fi

exit $STATUS
