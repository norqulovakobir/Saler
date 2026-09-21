#!/usr/bin/env bash
# Ubuntu 24.04 Hetzner Cloud VM uchun Saler API:
# PostgreSQL + PgBouncer + Node.js + Caddy + systemd + lokal backup.
# Bu skript deploy.sh tomonidan serverga yuklangandan keyin root sifatida ishlaydi.
set -euo pipefail

: "${DOMAIN:?DOMAIN berilmagan}"
if [[ ${EUID} -ne 0 ]]; then
  echo "Skript root yoki sudo bilan ishga tushishi kerak"
  exit 1
fi

DEPLOY_USER="${SUDO_USER:-root}"
DEPLOY_HOME="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
UPLOAD_DIR="$DEPLOY_HOME/saler-upload"
APP_DIR=/opt/saler
ENV_FILE=/etc/saler.env
BACKUP_DIR=/var/backups/saler
export DEBIAN_FRONTEND=noninteractive

step() { printf '\n==> %s\n' "$*"; }

if [[ ! -d "$UPLOAD_DIR/server" ]]; then
  echo "$UPLOAD_DIR/server topilmadi. deploy/hetzner/deploy.sh dan foydalaning."
  exit 1
fi

step "Tizim paketlari"
apt-get update -y
apt-get install -y ca-certificates curl gnupg rsync openssl postgresql postgresql-contrib pgbouncer caddy ufw unattended-upgrades

if ! command -v node >/dev/null 2>&1 || [[ "$(node -p 'process.versions.node.split(".")[0]')" -lt 20 ]]; then
  step "Node.js 22"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

step "PostgreSQL faqat lokal tarmoqda"
systemctl enable --now postgresql
sudo -u postgres psql -v ON_ERROR_STOP=1 -qc "ALTER SYSTEM SET listen_addresses = '127.0.0.1'"
systemctl restart postgresql

step "Saler foydalanuvchisi va kod"
id saler >/dev/null 2>&1 || useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin saler
install -d -o saler -g saler "$APP_DIR/server"
rsync -a --delete --exclude node_modules --exclude .env "$UPLOAD_DIR/server/" "$APP_DIR/server/"
chown -R saler:saler "$APP_DIR"
sudo -u saler -H bash -c "cd '$APP_DIR/server' && npm ci --omit=dev --no-audit --no-fund"

step "PostgreSQL va PgBouncer"
if [[ ! -f "$ENV_FILE" ]]; then
  DB_PASS="$(openssl rand -hex 24)"
  ADMIN_PASS="$(openssl rand -hex 16)"
  umask 077
  cat > "$ENV_FILE" <<ENV
NODE_ENV=production
PORT=3000
DATABASE_URL=postgres://saler:${DB_PASS}@127.0.0.1:6432/saler
DATABASE_SSL=false
DB_POOL_MAX=6
DB_POOL_IDLE_MS=30000
DB_CONNECT_TIMEOUT_MS=5000
DB_QUERY_TIMEOUT_MS=25000
DB_STATEMENT_TIMEOUT_MS=20000
DB_POOL_MAX_USES=7500
ADMIN_PASSWORD=${ADMIN_PASS}
PGBOUNCER_PASSWORD=${DB_PASS}
# AI kalitlari ixtiyoriy:
GROQ_API_KEY=
GROQ_MODEL=openai/gpt-oss-120b
ENV
fi

DB_PASS="$(sed -n 's/^PGBOUNCER_PASSWORD=//p' "$ENV_FILE" | head -n 1)"
if [[ -z "$DB_PASS" ]]; then
  echo "$ENV_FILE ichida PGBOUNCER_PASSWORD topilmadi"
  exit 1
fi
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='saler'" | grep -q 1; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 -qc "ALTER ROLE saler WITH LOGIN PASSWORD '$DB_PASS'"
else
  sudo -u postgres psql -v ON_ERROR_STOP=1 -qc "CREATE ROLE saler WITH LOGIN PASSWORD '$DB_PASS'"
fi
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='saler'" | grep -q 1; then
  sudo -u postgres createdb -O saler saler
fi

PGBOUNCER_USER="$(id -un pgbouncer 2>/dev/null || printf postgres)"
PGBOUNCER_GROUP="$(id -gn "$PGBOUNCER_USER")"
install -d -o "$PGBOUNCER_USER" -g "$PGBOUNCER_GROUP" -m 0750 /var/log/pgbouncer
cat > /etc/pgbouncer/pgbouncer.ini <<PGB
[databases]
saler = host=127.0.0.1 port=5432 dbname=saler user=saler password=${DB_PASS}

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = plain
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 300
default_pool_size = 12
reserve_pool_size = 4
reserve_pool_timeout = 3
server_idle_timeout = 60
server_reset_query = DISCARD ALL
ignore_startup_parameters = extra_float_digits
admin_users = saler
logfile = /var/log/pgbouncer/pgbouncer.log
pidfile = /run/postgresql/pgbouncer.pid
PGB
printf '"saler" "%s"\n' "$DB_PASS" > /etc/pgbouncer/userlist.txt
chown -R "$PGBOUNCER_USER":"$PGBOUNCER_GROUP" /etc/pgbouncer
chmod 0640 /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/userlist.txt
systemctl enable pgbouncer >/dev/null 2>&1
systemctl restart pgbouncer

chown root:saler "$ENV_FILE"
chmod 0640 "$ENV_FILE"

step "systemd xizmati"
cat > /etc/systemd/system/saler.service <<'UNIT'
[Unit]
Description=Saler AI API
After=network-online.target postgresql.service pgbouncer.service
Wants=network-online.target

[Service]
Type=simple
User=saler
Group=saler
WorkingDirectory=/opt/saler/server
EnvironmentFile=/etc/saler.env
ExecStart=/usr/bin/node src/server.js
Restart=always
RestartSec=3
TimeoutStopSec=20
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/opt/saler
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable saler >/dev/null 2>&1
systemctl restart saler

for _ in $(seq 1 30); do
  if curl -fsS --max-time 3 http://127.0.0.1:3000/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if ! curl -fsS --max-time 3 http://127.0.0.1:3000/health >/dev/null; then
  journalctl -u saler -n 80 --no-pager
  exit 1
fi

step "HTTPS va firewall"
cat > /etc/caddy/Caddyfile <<CADDY
${DOMAIN} {
    encode zstd gzip
    reverse_proxy 127.0.0.1:3000
}
CADDY
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

step "Kunlik PostgreSQL zaxirasi"
install -d -o postgres -g postgres -m 0750 "$BACKUP_DIR"
cat > /etc/cron.d/saler-backup <<'CRON'
# Har kuni 03:30 UTC. 14 kundan eskilari o'chiriladi.
30 3 * * * postgres pg_dump -Fc saler -f /var/backups/saler/saler-$(date +\%F).dump && find /var/backups/saler -name 'saler-*.dump' -mtime +14 -delete
CRON
chmod 0644 /etc/cron.d/saler-backup

echo "Tayyor: https://${DOMAIN}"
echo "API health: https://${DOMAIN}/health"
