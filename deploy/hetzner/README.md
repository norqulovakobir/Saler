# Saler AI — Hetzner Cloud + PostgreSQL

Bu variant PostgreSQL, PgBouncer, Node API, HTTPS va lokal zaxirani bitta Ubuntu 24.04 serverda ishga tushiradi. U **bepul emas**: Hetzner tarifini buyurtma berishdan oldin o'z dashboardidan tekshiring. Boshlanishida xarajat bo'lmasin desangiz, Cloudflare Worker + D1 bilan boshlang; Hetzner trafik va ma'lumot ko'payganda foydali.

## 1. Hetzner'da tayyorgarlik

1. Hetzner Cloud'da project va Ubuntu 24.04 server yarating.
2. Kamida 2 vCPU va 4 GB RAM tanlang; PostgreSQL va API bitta serverda ishlaydi.
3. Mac'da SSH kalit yarating:

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/hetzner_saler -N ""
   ```

   Ochiq kalitni (`~/.ssh/hetzner_saler.pub`) server yaratishdagi SSH keys bo'limiga qo'shing.
4. Hetzner Cloud Firewall'da faqat quyidagilarni oching:
   - TCP `22` — imkon bo'lsa faqat o'zingizning IP manzilingizdan;
   - TCP `80` va `443` — hammaga.

`3000`, `5432` va `6432` portlarini ochmang: API, PostgreSQL va PgBouncer faqat server ichida tinglaydi.

## 2. Bir buyruq bilan o'rnatish

```bash
cd ~/Desktop/Saler-main
bash deploy/hetzner/deploy.sh SERVER_IP
```

Ixtiyoriy domen bo'lsa:

```bash
bash deploy/hetzner/deploy.sh SERVER_IP api.saler.uz
```

Domeningiz DNS'ida server IP'siga `A` yozuvi bo'lishi kerak. Domen bermasangiz, skript vaqtinchalik `sslip.io` manzilidan foydalanadi.

Skript quyidagilarni yaratadi:

- PostgreSQL (`127.0.0.1:5432`);
- PgBouncer transaction pool (`127.0.0.1:6432`);
- API uchun 6 ta maksimal Node pool connection;
- Caddy avtomatik HTTPS;
- systemd restart/graceful shutdown;
- 14 kunlik lokal PostgreSQL backup.

## 3. Ilovani ulash

`flutter_app/env.json` ichida API manzilini almashtiring:

```json
{
  "API_BASE": "https://api.saler.uz",
  "REALTIME_ENABLED": false
}
```

Admin panel deploy qilinayotgan joyda `NEXT_PUBLIC_API_URL` ham shu API manzili bo'lishi kerak.

## Kundalik boshqaruv

```bash
# Jonli loglar
ssh -i ~/.ssh/hetzner_saler root@SERVER_IP 'journalctl -u saler -f'

# API restart
ssh -i ~/.ssh/hetzner_saler root@SERVER_IP 'systemctl restart saler'

# Pool va servis holati
ssh -i ~/.ssh/hetzner_saler root@SERVER_IP 'systemctl status saler pgbouncer postgresql --no-pager'

# Backup ro'yxati
ssh -i ~/.ssh/hetzner_saler root@SERVER_IP 'ls -lh /var/backups/saler'
```

Kod yangilanishi uchun aynan `deploy.sh` buyrug'ini qayta ishga tushiring. `/etc/saler.env` saqlanadi; undagi parollar va API kalitlar o'chirilmaydi.
