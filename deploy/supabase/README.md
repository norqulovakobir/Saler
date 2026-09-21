# Saler: baza va rasmlarni Supabase'ga ulash

Server Render'da qoladi. Baza va rasmlar Supabase'ga ko'chadi.
Flutter ilova va admin panelda hech narsa o'zgarmaydi: ular avvalgidek Render'dagi serverga ulanadi.

| Supabase bepul rejasi | |
|---|---|
| Baza | 500 MB |
| Rasmlar (Storage) | 1 GB |
| Bank kartasi | kerak emas |
| Muddat | cheksiz |
| To'xtab qolish | 7 kun bazaga so'rov kelmasa (8-qadamda yechimi bor) |

Rasmlar bazaga emas, Storage'ga yoziladi. Shuning uchun 500 MB faqat matnli ma'lumotlarga ishlatiladi va uzoq vaqt yetadi.

---

## 1. Hisob ochish

https://supabase.com → **Start your project** → GitHub yoki email bilan kiring.

## 2. Loyiha yaratish

**New project** tugmasini bosing:

| Maydon | Qiymat |
|---|---|
| Name | `saler` |
| Database Password | **Generate a password** → nusxalab saqlang. Faqat harf va raqamdan iborat bo'lsin. |
| Region | Render'dagi serveringizga eng yaqini (pastga qarang) |

- **Region.** Render → **saler-server → Settings → Region** ni ko'ring. Oregon bo'lsa **West US (Oregon)**, Frankfurt bo'lsa **Central EU (Frankfurt)** ni tanlang. Server va baza yaqin bo'lsa, ilova tez ishlaydi.
- **Enable Data API** belgisi ko'rinsa, o'chirib qo'ying. Server bazaga to'g'ridan-to'g'ri ulanadi, Data API kerak emas.

**Create new project** → 1–2 daqiqa kuting.

## 3. Uchta qiymatni nusxalash

| Nima | Qayerdan | Ko'rinishi |
|---|---|---|
| **Baza manzili** | Tepadagi **Connect** → **Connection String** → Method: **Session pooler** | `postgresql://postgres.abcd:[YOUR-PASSWORD]@aws-0-eu-central-1.pooler.supabase.com:5432/postgres` |
| **Project URL** | **Project Settings → Data API** | `https://abcd.supabase.co` |
| **Secret key** | **Project Settings → API Keys → Secret keys** | `sb_secret_...` |

- Baza manzilidagi `[YOUR-PASSWORD]` o'rniga 2-qadamdagi parolni qo'ying, kvadrat qavslarsiz.
- **Direct connection** manzilini olmang. U faqat IPv6 orqali ishlaydi, Render esa IPv4 ishlatadi.
- Secret key o'rniga eski **service_role** kalit ham ishlaydi.
- Secret key maxfiy. Uni hech kimga bermang, Flutter ilovaga ham qo'ymang.

Menyu nomlari Supabase yangilanishi bilan biroz farq qilishi mumkin.

## 4. Render'dagi ma'lumotlarni ko'chirish

Render'da do'kon, mahsulot yoki buyurtmalar bo'lsa, ularni ko'chiring. Yangi boshlayotgan bo'lsangiz, bu qadamni o'tkazib yuboring.

1. Render → **saler-db → Connect → External Database URL** ni nusxalang.
2. Mac terminalida:

```bash
cd ~/Desktop/Saler-main
bash deploy/supabase/migrate-from-render.sh
```

Skript to'rtta qiymat so'raydi: Render manzili va 3-qadamdagi uchta qiymat. Maxfiy qiymatlar yozilayotganda ekranda ko'rinmaydi.
Oxirida har bir jadvaldagi yozuvlar soni chiqadi. Rasmlar to'g'ridan-to'g'ri Storage'ga yoziladi.

Skriptga `pg_dump` kerak. Yo'q bo'lsa: `brew install postgresql@18`.

## 5. Render serverini Supabase'ga ulash

> **Blueprint ishlatsangiz:** avval yangilangan `render.yaml` ni GitHub'ga yuklang.
> Aks holda Render `DATABASE_URL` ni eski Render bazasiga qaytarib qo'yadi.

Render → **saler-server → Environment**:

| Kalit | Qiymat |
|---|---|
| `DATABASE_URL` | Session pooler manzili, parol bilan |
| `SUPABASE_URL` | Project URL |
| `SUPABASE_SECRET_KEY` | `sb_secret_...` |
| `GROQ_API_KEY` | Groq kaliti, AI chatlar uchun |

**Save, rebuild, and deploy**. **Logs** bo'limida shu qator chiqishi kerak:

```
Rasmlar Supabase Storage'da: "photos" bucket yaratildi
```

## 6. Tekshirish

1. Brauzerda oching: `https://saler-server.onrender.com/health/db`. Javob `{"ok":true,"db":true}` bo'lishi kerak.
2. Ilovada sotuvchi sifatida rasm bilan mahsulot qo'shing. Supabase → **Storage → photos** da yangi fayl paydo bo'ladi.
3. Eski mahsulotlarning rasmlari ham ochilishini tekshiring.

## 7. Eski Render bazasini o'chirish

Hammasi ishlayotganiga ishonch hosil qilgach: Render → **saler-db → Settings → Delete Database**.

## 8. Loyiha to'xtab qolmasligi uchun

Supabase bepul loyihasiga 7 kun bazaga so'rov kelmasa, u pauza qilinadi. Ilovadan har kuni foydalanilsa, bu muammo emas.
Foydalanuvchilar hali kam bo'lsa, kuniga bir marta avtomatik so'rov yuborib turing:

1. https://cron-job.org da bepul hisob oching.
2. **Create cronjob**: URL `https://saler-server.onrender.com/health/db`, jadval **Every day**.

Pauza bo'lib qolsa: Supabase Dashboard → loyihangiz → **Restore project**.

---

## Joy tugay boshlasa

**Supabase → Organization → Usage** bo'limida baza va Storage hajmini kuzating.
Limitga yaqinlashsa, Supabase Pro rejasiga o'ting yoki Oracle variantiga ko'ching: [`deploy/oracle/README.md`](../oracle/README.md).

## Muammolar

| Xato | Sababi va yechimi |
|---|---|
| `password authentication failed` | Parol noto'g'ri yoki `[YOUR-PASSWORD]` almashtirilmagan. |
| `Tenant or user not found` | Manzil noto'g'ri nusxalangan. Foydalanuvchi `postgres.<loyiha-id>` ko'rinishida bo'lishi kerak. |
| `ENETUNREACH` yoki IPv6 manzilga ulanish xatosi | Direct connection olingan. **Session pooler** manzilini oling. |
| Logda `Supabase Storage: ... 401` yoki `403` | `SUPABASE_SECRET_KEY` noto'g'ri. Publishable key emas, secret key kerak. |
| Rasmlar ochilmaydi | Supabase → **Storage → photos** bucket **Public** bo'lishi kerak. |
| Logda `DB migratsiya xatosi` | `DATABASE_URL` ni tekshiring. Supabase loyihasi pauzada bo'lmasin. |
