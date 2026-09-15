#!/usr/bin/env bash
# Saler serverini Oracle Cloud serveriga yuklaydi va ishga tushiradi.
# Mac'da, loyiha papkasidan ishga tushiriladi:
#   bash deploy/oracle/deploy.sh <SERVER_IP> [domen]
# Domen berilmasa, bepul <ip>.sslip.io manzili ishlatiladi (HTTPS avtomatik).
# Kodni yangilash uchun ham shu buyruqni qayta ishga tushiring.
set -euo pipefail

IP="${1:-}"
if [[ -z "$IP" ]]; then
  echo "Foydalanish: bash deploy/oracle/deploy.sh <SERVER_IP> [domen]"
  exit 1
fi
DOMAIN="${2:-${IP//./-}.sslip.io}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/oracle_saler}"
SSH_USER="${SSH_USER:-ubuntu}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
TARGET="$SSH_USER@$IP"

if [[ ! -f "$SSH_KEY" ]]; then
  echo "SSH kalit topilmadi: $SSH_KEY"
  echo "Avval yarating: ssh-keygen -t ed25519 -f ~/.ssh/oracle_saler -N \"\""
  exit 1
fi

echo "==> Serverga ulanish: $TARGET"
ssh "${SSH_OPTS[@]}" "$TARGET" "mkdir -p ~/saler-upload"

echo "==> Fayllar yuklanmoqda"
rsync -az --delete -e "ssh ${SSH_OPTS[*]}" \
  --exclude node_modules --exclude .env \
  "$ROOT/server/" "$TARGET:saler-upload/server/"
rsync -az -e "ssh ${SSH_OPTS[*]}" \
  "$ROOT/deploy/oracle/setup.sh" "$ROOT/deploy/oracle/migrate-from-render.sh" \
  "$TARGET:saler-upload/"

echo "==> Server sozlanmoqda (birinchi marta 5-10 daqiqa ketadi)"
# DOMAIN ataylab Mac tomonida qo'yiladi
# shellcheck disable=SC2029
ssh "${SSH_OPTS[@]}" "$TARGET" "sudo DOMAIN='$DOMAIN' bash ~/saler-upload/setup.sh"

echo "==> HTTPS tekshirilmoqda: https://$DOMAIN/health"
for _ in $(seq 1 24); do
  if curl -fsS --max-time 10 "https://$DOMAIN/health" >/dev/null 2>&1; then
    echo
    echo "TAYYOR. API manzili: https://$DOMAIN"
    echo "Flutter ilovada flutter_app/env.json ichidagi API_BASE ni shu manzilga almashtiring."
    exit 0
  fi
  sleep 5
done
echo
echo "Server ishlayapti, lekin https://$DOMAIN hali ochilmadi."
echo "Oracle Security List'da 80 va 443 portlari ochiqligini tekshiring (qo'llanmadagi 5-qadam)."
exit 1
