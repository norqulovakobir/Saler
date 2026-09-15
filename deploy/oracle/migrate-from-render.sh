#!/usr/bin/env bash
# Render'dagi eski bazadagi barcha ma'lumotlarni Oracle serveridagi bazaga ko'chiradi.
# Serverda ishga tushiriladi:
#   sudo bash ~/saler-upload/migrate-from-render.sh 'RENDER_EXTERNAL_DATABASE_URL'
# Diqqat: Oracle'dagi joriy baza almashtiriladi. Undan oldin zaxira nusxa olinadi.
set -euo pipefail

SRC="${1:-}"
if [[ -z "$SRC" ]]; then
  echo "Foydalanish: sudo bash ~/saler-upload/migrate-from-render.sh 'postgres://...render.com/...'"
  exit 1
fi
if [[ $EUID -ne 0 ]]; then
  echo "sudo bilan ishga tushiring"
  exit 1
fi

cd /tmp
BACKUP_DIR=/var/backups/saler
STAMP="$(date +%F-%H%M)"
mkdir -p "$BACKUP_DIR"
chown postgres:postgres "$BACKUP_DIR"

echo "==> Render bazasidan nusxa olinmoqda"
sudo -u postgres pg_dump "$SRC" -Fc --no-owner --no-acl -f "$BACKUP_DIR/render-$STAMP.dump"

echo "==> Oracle'dagi joriy bazadan zaxira olinmoqda"
sudo -u postgres pg_dump -Fc saler -f "$BACKUP_DIR/before-migrate-$STAMP.dump"

echo "==> Baza almashtirilmoqda"
systemctl stop saler
sudo -u postgres dropdb --if-exists saler
sudo -u postgres createdb -O saler saler
if ! sudo -u postgres pg_restore --no-owner --no-acl --role=saler -d saler "$BACKUP_DIR/render-$STAMP.dump"; then
  echo "(pg_restore ogohlantirish berdi, natijani quyida tekshiring)"
fi
systemctl start saler

echo "==> Natija"
for t in shops products orders couriers users photos; do
  n="$(sudo -u postgres psql -d saler -tAc "SELECT count(*) FROM $t" 2>/dev/null || echo "jadval yo'q")"
  printf '  %-10s %s\n' "$t" "$n"
done
echo "Ko'chirish tugadi. Eski nusxa: $BACKUP_DIR/before-migrate-$STAMP.dump"
