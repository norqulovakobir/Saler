#!/usr/bin/env bash
# Oracle Cloud'dagi Ubuntu 24.04 serveriga Saler backendini o'rnatadi:
# PostgreSQL 18, Node.js 24, Caddy (avtomatik HTTPS), systemd xizmati, kunlik zaxira.
# deploy.sh uni o'zi ishga tushiradi. Qayta ishga tushirish xavfsiz: parollar va ma'lumotlar saqlanib qoladi.
set -euo pipefail

: "${DOMAIN:?DOMAIN berilmagan}"
if [[ $EUID -ne 0 ]]; then
  echo "sudo bilan ishga tushiring"
  exit 1
fi

UPLOAD="$(getent passwd "${SUDO_USER:-ubuntu}" | cut -d: -f6)/saler-upload"
APP_DIR=/opt/saler
ENV_FILE=/etc/saler.env
BACKUP_DIR=/var/backups/saler
PG_VERSION=18
NODE_MAJOR=24
export DEBIAN_FRONTEND=noninteractive
cd /tmp

step() { printf '\n==> %s\n' "$*"; }

if [[ ! -d "$UPLOAD/server" ]]; then
  echo "$UPLOAD/server topilmadi. Bu skriptni deploy.sh orqali ishga tushiring."
  exit 1
fi

step "Paket manbalari"
apt-get update -y
apt-get install -y curl ca-certificates gnupg rsync openssl debian-keyring debian-archive-keyring apt-transport-https
install -d /etc/apt/keyrings /usr/share/postgresql-common/pgdg
# shellcheck source=/dev/null
. /etc/os-release

if [[ ! -f /etc/apt/sources.list.d/pgdg.list ]]; then
  curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc
  echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list
fi
if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
fi
if [[ ! -f /etc/apt/sources.list.d/caddy-stable.list ]]; then
  curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
  chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list
fi

step "PostgreSQL $PG_VERSION, Node.js $NODE_MAJOR, Caddy o'rnatilmoqda"
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
apt-get update -y
apt-get install -y "postgresql-$PG_VERSION" nodejs caddy iptables-persistent

step "Ilova foydalanuvchisi va kod"
id saler >/dev/null 2>&1 || useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin saler
mkdir -p "$APP_DIR/server"
rsync -a --delete --exclude node_modules "$UPLOAD/server/" "$APP_DIR/server/"
chown -R saler:saler "$APP_DIR"
sudo -u saler -H bash -c "cd '$APP_DIR/server' && npm ci --omit=dev --no-audit --no-fund"

step "Baza"
systemctl enable --now postgresql
NEW_ADMIN_PASS=""
if [[ ! -f "$ENV_FILE" ]]; then
  DB_PASS="$(openssl rand -hex 24)"
  NEW_ADMIN_PASS="$(openssl rand -hex 12)"
  if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='saler'" | grep -q 1; then
    sudo -u postgres psql -v ON_ERROR_STOP=1 -qc "ALTER ROLE saler WITH LOGIN PASSWORD '$DB_PASS'"
  else
    sudo -u postgres psql -v ON_ERROR_STOP=1 -qc "CREATE ROLE saler WITH LOGIN PASSWORD '$DB_PASS'"
  fi
  (
    umask 077
    cat > "$ENV_FILE" <<ENV
NODE_ENV=production
PORT=3000
DATABASE_URL=postgres://saler:${DB_PASS}@127.0.0.1:5432/saler
ADMIN_PASSWORD=${NEW_ADMIN_PASS}
# AI yordamchi uchun kalitni shu yerga yozing, keyin: sudo systemctl restart saler
GEMINI_API_KEY=
GEMINI_MODEL=gemini-3.6-flash
ENV
  )
fi
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='saler'" | grep -q 1; then
  sudo -u postgres createdb -O saler saler
fi

step "Saler xizmati (systemd)"
cat > /etc/systemd/system/saler.service <<'UNIT'
[Unit]
Description=Saler AI server
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
User=saler
Group=saler
WorkingDirectory=/opt/saler/server
EnvironmentFile=/etc/saler.env
ExecStart=/usr/bin/node src/server.js
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable saler >/dev/null 2>&1
systemctl restart saler

ok=""
for _ in $(seq 1 30); do
  if curl -fsS --max-time 3 http://127.0.0.1:3000/health >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done
if [[ -z "$ok" ]]; then
  echo "Server ishga tushmadi. Oxirgi loglar:"
  journalctl -u saler -n 40 --no-pager
  exit 1
fi
echo "Server ishlayapti."

step "Firewall: 80 va 443 portlari"
for port in 80 443; do
  if ! iptables -C INPUT -p tcp --dport "$port" -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null; then
    iptables -I INPUT 1 -p tcp --dport "$port" -m conntrack --ctstate NEW -j ACCEPT
  fi
done
netfilter-persistent save >/dev/null 2>&1

step "HTTPS (Caddy): $DOMAIN"
cat > /etc/caddy/Caddyfile <<CADDY
$DOMAIN {
	encode zstd gzip
	reverse_proxy 127.0.0.1:3000
}
CADDY
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy

step "Kunlik zaxira"
mkdir -p "$BACKUP_DIR"
chown postgres:postgres "$BACKUP_DIR"
cat > /etc/cron.d/saler-backup <<'CRON'
# Har kuni Toshkent vaqti bilan 03:30 da (22:30 UTC) baza zaxirasi. 14 kundan eskilari o'chiriladi.
30 22 * * * postgres pg_dump -Fc saler -f /var/backups/saler/saler-$(date +\%F).dump && find /var/backups/saler -name 'saler-*.dump' -mtime +14 -delete
CRON
chmod 644 /etc/cron.d/saler-backup

step "Tayyor"
echo "Manzil:      https://$DOMAIN"
echo "Sozlamalar:  $ENV_FILE  (ko'rish: sudo cat $ENV_FILE)"
if [[ -n "$NEW_ADMIN_PASS" ]]; then
  echo "Admin panel paroli: $NEW_ADMIN_PASS   <- saqlab qo'ying"
fi
