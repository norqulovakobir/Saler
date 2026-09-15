# Saler serverini Oracle Cloud'ga o'rnatish

Natijada bitta bepul Oracle serverida hammasi ishlaydi: PostgreSQL bazasi, Node server, HTTPS va kunlik zaxira.
Server doim yoniq turadi, Render'dagidek uxlab qolmaydi. Diskda 150 GB joy bo'ladi.

Siz qiladigan ish: Oracle saytida hisob va server yaratish (1–5 qadamlar).
Qolganini bitta buyruq o'zi qiladi (6-qadam).

---

## 1. Oracle hisobini ochish

1. https://signup.cloud.oracle.com saytiga kiring.
2. Mamlakat, ism va email kiriting. Emailga kelgan havola orqali tasdiqlang.
3. Parol va **Home Region** tanlang.
   - Home Region keyin **o'zgarmaydi**. Bepul server faqat shu regionda yaratiladi.
   - O'zbekistonga yaqinlari: **Germany Central (Frankfurt)**, **UAE East (Dubai)**, **Saudi Arabia West (Jeddah)**.
   - Frankfurt ko'p band bo'ladi. Server yaratishda "Out of capacity" chiqsa, 4-qadamdagi maslahatni ko'ring.
4. Telefon raqam va bank kartasini kiriting.
   - Xalqaro **Visa yoki Mastercard** kerak. Uzcard va Humo qabul qilinmaydi.
   - Karta faqat tekshirish uchun. Bepul limitdan oshmasangiz, pul yechilmaydi.
5. Hisob tayyor bo'lishini kuting. Odatda bir necha daqiqa, ba'zan bir necha soat.

## 2. Tasodifiy xarajatdan himoya

Oracle Console'da:

1. **☰ Menu → Billing & Cost Management → Budgets → Create Budget**
2. Name: `saler-limit`, Budget Amount: `1` (USD)
3. Alert rule: Threshold `100` %, email manzilingizni yozing → **Create**

Endi 1 dollarlik xarajat bo'lsa ham email keladi.

**Ixtiyoriy, lekin tavsiya:** **Billing → Upgrade and Manage Payment → Pay As You Go** ga o'ting.
Bepul limitlar saqlanib qoladi. Oracle kam ishlatilayotgan bepul serverni qaytarib olish xavfi kamayadi.

## 3. SSH kalit yaratish (Mac terminalida)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/oracle_saler -N ""
pbcopy < ~/.ssh/oracle_saler.pub
```

Ikkinchi buyruq ochiq kalitni buferga nusxalaydi. 4-qadamda kerak bo'ladi.

## 4. Server yaratish

**☰ Menu → Compute → Instances → Create instance**

| Maydon | Qiymat |
|---|---|
| Name | `saler` |
| Image | **Change image → Ubuntu → Canonical Ubuntu 24.04** ("Minimal" emas) |
| Shape | **Change shape → Virtual machine → Ampere → VM.Standard.A1.Flex** |
| Number of OCPUs | `2` |
| Amount of memory (GB) | `12` |
| Networking | **Create new virtual cloud network** va **Create new public subnet** |
| Assign a public IPv4 address | **Yes** |
| Add SSH keys | **Paste public keys** → Cmd+V |
| Boot volume | **Specify a custom boot volume size** → `150` GB |

**Create** tugmasini bosing. Holati **RUNNING** bo'lgach, **Public IP address** ni nusxalang. Masalan: `141.147.10.20`.

> **"Out of capacity for shape VM.Standard.A1.Flex"** chiqsa: boshqa **Availability domain** (AD-2, AD-3) tanlab ko'ring
> yoki bir necha soatdan keyin qayta urinib ko'ring. Bu Oracle'da tez-tez uchraydi, xato sizda emas.

## 5. 80 va 443 portlarini ochish

1. Instance sahifasida **Primary VNIC** bo'limidagi **Subnet** havolasini bosing.
2. **Security Lists** → **Default Security List for ...** → **Add Ingress Rules**
3. To'ldiring:
   - Source CIDR: `0.0.0.0/0`
   - IP Protocol: `TCP`
   - Destination Port Range: `80,443`
4. **Add Ingress Rules**

3000 va 5432 portlarini **ochmang**. Baza faqat server ichidan ishlatiladi.

## 6. Hammasini o'rnatish (bitta buyruq)

Mac terminalida, IP o'rniga o'zingiznikini yozing:

```bash
cd ~/Desktop/Saler-main
bash deploy/oracle/deploy.sh 141.147.10.20
```

Birinchi marta 5–10 daqiqa ketadi. Oxirida quyidagilar chiqadi:

- **API manzili**, masalan `https://141-147-10-20.sslip.io`
- **Admin panel paroli**. Uni saqlab qo'ying, faqat bir marta ko'rsatiladi.

O'z domeningiz bo'lsa, DNS'da serverning IP'siga **A** yozuv yarating va domenni qo'shib bering:

```bash
bash deploy/oracle/deploy.sh 141.147.10.20 api.saler.uz
```

## 7. AI kalitini qo'shish

```bash
ssh -i ~/.ssh/oracle_saler ubuntu@141.147.10.20
sudo nano /etc/saler.env
```

`GEMINI_API_KEY=` qatoriga Gemini kalitini yozing. **Ctrl+O**, **Enter**, **Ctrl+X** bilan saqlang. Keyin:

```bash
sudo systemctl restart saler
```

## 8. Render'dagi ma'lumotlarni ko'chirish

Render'da do'konlar, mahsulotlar va buyurtmalar bo'lsa, ularni ko'chiring. Render bepul bazasi 30 kunda o'chishini unutmang.

1. Render Dashboard → **saler-db** → **Connect** → **External Database URL** ni nusxalang.
2. Serverda ishga tushiring:

```bash
ssh -i ~/.ssh/oracle_saler ubuntu@141.147.10.20
sudo bash ~/saler-upload/migrate-from-render.sh 'BU_YERGA_RENDER_URL'
```

Oxirida har bir jadvaldagi yozuvlar soni chiqadi.

## 9. Ilova va admin panelni yangi serverga ulash

1. **Flutter ilova:** `flutter_app/env.json` faylida:
   ```json
   "API_BASE": "https://141-147-10-20.sslip.io"
   ```
2. **Admin panel (Render'da):** **saler-admin → Environment** → `NEXT_PUBLIC_API_URL` ga yangi manzilni yozing → **Save, rebuild, and deploy**.
3. Hammasi ishlayotganini tekshirgach, Render'dagi **saler-server** va **saler-db** ni o'chirishingiz mumkin.

---

## Kundalik ishlar

| Nima | Buyruq |
|---|---|
| Kodni yangilash | `bash deploy/oracle/deploy.sh 141.147.10.20` (Mac'da) |
| Serverga kirish | `ssh -i ~/.ssh/oracle_saler ubuntu@141.147.10.20` |
| Jonli loglar | `sudo journalctl -u saler -f` |
| Qayta ishga tushirish | `sudo systemctl restart saler` |
| Admin parolini ko'rish | `sudo grep ADMIN_PASSWORD /etc/saler.env` |
| Baza hajmi | `sudo -u postgres psql -d saler -c "SELECT pg_size_pretty(pg_database_size('saler'))"` |
| Disk joyi | `df -h /` |

**Zaxira nusxalar** har kuni `/var/backups/saler` papkasiga yoziladi, 14 kun saqlanadi.
Ular shu serverning o'zida turadi. Vaqti-vaqti bilan Mac'ga yuklab oling:

```bash
scp -i ~/.ssh/oracle_saler 'ubuntu@141.147.10.20:/var/backups/saler/*.dump' ~/Desktop/
```

## Muammolar

| Belgi | Nima qilish kerak |
|---|---|
| `ssh: connect ... Operation timed out` | Public IP to'g'rimi tekshiring. Instance holati RUNNING bo'lsin. |
| `Permission denied (publickey)` | 4-qadamda boshqa kalit qo'yilgan. Instance'ni qayta yarating yoki kalitni Console'dan qo'shing. |
| deploy.sh "https hali ochilmadi" deydi | 5-qadamni tekshiring. Serverda: `sudo journalctl -u caddy -n 50` |
| "Server ishga tushmadi" | Serverda: `sudo journalctl -u saler -n 50` |
| Ko'chirishda `connection refused` yoki `timeout` | Render → saler-db → **Networking/Access Control** da tashqi ulanishga ruxsat bering. |
| Oracle serverni "idle" deb to'xtatdi | 2-qadamdagi Pay As You Go'ga o'ting va serverni qayta yoqing. |
