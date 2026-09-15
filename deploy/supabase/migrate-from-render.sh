#!/usr/bin/env bash
# Render'dagi eski bazani Supabase'ga ko'chiradi. Mac'da, loyiha papkasidan ishga tushiriladi:
#   bash deploy/supabase/migrate-from-render.sh
# Jadvallar Supabase bazasiga, rasmlar esa Supabase Storage'ga yoziladi.
# Manzil va kalitlar so'raladi (yoki oldindan o'zgaruvchi sifatida berish mumkin):
#   RENDER_DATABASE_URL, SUPABASE_DATABASE_URL, SUPABASE_URL, SUPABASE_SECRET_KEY
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for d in /opt/homebrew/opt/postgresql@18/bin /opt/homebrew/opt/postgresql@17/bin /usr/local/opt/postgresql@18/bin; do
  [[ -x "$d/pg_dump" ]] && PATH="$d:$PATH" && break
done
if ! command -v pg_dump >/dev/null || ! command -v node >/dev/null; then
  echo "pg_dump va node kerak. O'rnatish: brew install postgresql@18 node"
  exit 1
fi

ask() { # ask VAR "savol" [secret]
  local var="$1" prompt="$2" val="${!1:-}"
  while [[ -z "$val" ]]; do
    if [[ "${3:-}" == secret ]]; then read -rsp "$prompt: " val; echo; else read -rp "$prompt: " val; fi
  done
  printf -v "$var" '%s' "$val"
  export "${var?}"
}
ask RENDER_DATABASE_URL "Render External Database URL"
ask SUPABASE_DATABASE_URL "Supabase Session pooler manzili (postgresql://postgres.xxx:PAROL@...pooler.supabase.com:5432/postgres)" secret
ask SUPABASE_URL "Supabase Project URL (https://xxx.supabase.co)"
ask SUPABASE_SECRET_KEY "Supabase secret key (sb_secret_...)" secret

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> 1/3 Render bazasidan nusxa olinmoqda (rasmlarsiz)"
pg_dump "$RENDER_DATABASE_URL" -Fc --no-owner --no-acl --exclude-table-data=photos -f "$TMP/render.dump"

echo "==> 2/3 Supabase bazasiga yozilmoqda"
if ! pg_restore --clean --if-exists --no-owner --no-acl -d "$SUPABASE_DATABASE_URL" "$TMP/render.dump"; then
  echo "   (pg_restore ogohlantirish berdi, natijani quyida tekshiring)"
fi

echo "==> 3/3 Rasmlar Supabase Storage'ga ko'chirilmoqda"
rsync -a --exclude node_modules "$ROOT/server/" "$TMP/server/"
(cd "$TMP/server" && npm ci --omit=dev --no-audit --no-fund --silent)
(cd "$TMP/server" && SOURCE_DATABASE_URL="$RENDER_DATABASE_URL" node scripts/move-photos.js)

echo "==> Natija (Supabase bazasi)"
for t in shops products orders couriers users; do
  printf '  %-10s %s\n' "$t" "$(psql "$SUPABASE_DATABASE_URL" -tAc "SELECT count(*) FROM $t" 2>/dev/null || echo "jadval yo'q")"
done
echo "Tayyor. Endi Render'dagi saler-server sozlamalarini Supabase'ga almashtiring (qo'llanmadagi 5-qadam)."
