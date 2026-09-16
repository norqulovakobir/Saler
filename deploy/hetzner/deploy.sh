#!/usr/bin/env bash
# Mac'da loyiha ildizidan:
# bash deploy/hetzner/deploy.sh <SERVER_IP> [api.example.com]
set -euo pipefail

IP="${1:-}"
if [[ -z "$IP" ]]; then
  echo "Foydalanish: bash deploy/hetzner/deploy.sh <SERVER_IP> [domen]"
  exit 1
fi
DOMAIN="${2:-${IP//./-}.sslip.io}"
if [[ ! "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "Domen noto'g'ri"
  exit 1
fi

SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/hetzner_saler}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="${SSH_USER}@${IP}"
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)

if [[ ! -f "$SSH_KEY" ]]; then
  echo "SSH kalit topilmadi: $SSH_KEY"
  echo "Yarating: ssh-keygen -t ed25519 -f $SSH_KEY -N \"\""
  exit 1
fi

echo "==> Serverga ulanish: $TARGET"
ssh "${SSH_OPTS[@]}" "$TARGET" 'mkdir -p ~/saler-upload'

echo "==> Server kodi yuklanmoqda"
rsync -az --delete -e "ssh ${SSH_OPTS[*]}" --exclude node_modules --exclude .env \
  "$ROOT/server/" "$TARGET:saler-upload/server/"
rsync -az -e "ssh ${SSH_OPTS[*]}" "$ROOT/deploy/hetzner/setup.sh" "$TARGET:saler-upload/setup.sh"

echo "==> Server sozlanmoqda"
ssh "${SSH_OPTS[@]}" "$TARGET" "if [ \"\$(id -u)\" -eq 0 ]; then DOMAIN='$DOMAIN' bash ~/saler-upload/setup.sh; else sudo DOMAIN='$DOMAIN' bash ~/saler-upload/setup.sh; fi"

echo "==> HTTPS tekshirilyapti"
for _ in $(seq 1 24); do
  if curl -fsS --max-time 10 "https://${DOMAIN}/health" >/dev/null 2>&1; then
    echo "TAYYOR. API manzili: https://${DOMAIN}"
    exit 0
  fi
  sleep 5
done

echo "API lokal serverda ishladi, lekin HTTPS hali tekshirilmadi. Hetzner firewall va DNS ni tekshiring."
exit 1
