# Render'ga chiqarish (va "ishlamadi" bo'lsa nima qilish)

> **Backend qayerda:** ishlayotgan backend — **Cloudflare Worker**
> (`cloudflare-worker/`, manzil `https://saler-api.akobirnorqulov104.workers.dev`):
> baza **D1**, rasmlar **R2**, tasdiqlash kodi **Brevo** orqali ketadi.
> `saler-web` va `saler-admin` shu Worker'ga ulanadi.
> Quyidagi `saler-server` (Express + Postgres + EmailJS) — **eski** stack;
> u hali o'chirilmagan, lekin ilova undan foydalanmaydi. Worker'ni deploy
> qilish va uning kalitlari `cloudflare-worker/README.md` da yozilgan.

Blueprint: Render Dashboard → **New → Blueprint** → shu repo → `render.yaml` o'qiladi va 3 ta servis yaratiladi:

| Servis | Nima | Manzil |
|---|---|---|
| `saler-server` | Eski backend (Express + Postgres) — ishlatilmaydi | `https://saler-server.onrender.com` |
| `saler-admin` | Admin panel (Next.js) → Worker'ga ulanadi | `https://saler-admin.onrender.com` |
| `saler-web` | Flutter ilovaning web versiyasi (Static Site) → Worker'ga ulanadi | `https://saler-web.onrender.com` |

## 1. Majburiy env o'zgaruvchilar (`saler-server` → Environment)

`sync: false` deb belgilangan qiymatlarni Render **o'zi to'ldirmaydi** — qo'lda kiritish shart:

| Kalit | Qayerdan olinadi | Bo'lmasa nima bo'ladi |
|---|---|---|
| `DATABASE_URL` | Supabase → Connect → **Session pooler** manzili | Server ishga tushadi, lekin barcha `/api/...` so'rovlar `503` qaytaradi |
| `SUPABASE_URL` | Supabase → Project Settings → Data API → Project URL | Rasmlar Postgres'da saqlanadi (bepul bazani tez to'ldiradi) |
| `SUPABASE_SECRET_KEY` | Supabase → API Keys → Secret key (`sb_secret_...`) | yuqoridagi bilan bir xil |
| `GROQ_API_KEY` | console.groq.com/keys | AI yordamchi, AI sotuvchi va maslahatlar o'chiq bo'ladi |
| `ANTHROPIC_API_KEY` | console.anthropic.com | Groq bo'lmasa ishlatiladi (ixtiyoriy) |
| `EMAILJS_*` | dashboard.emailjs.com | Ro'yxatdan o'tish kodi yuborilmaydi → hech kim ro'yxatdan o'ta olmaydi |

`ADMIN_PASSWORD` avtomatik generatsiya qilinadi — uni Render → `saler-server` → Environment bo'limidan ko'chirib oling,
admin panelga shu parol bilan kiriladi.

## 2. Tekshirish

Deploy tugagach brauzerda oching:

```
https://saler-server.onrender.com/health      -> {"ok":true,"db":"ready"}
https://saler-server.onrender.com/health/db   -> {"ok":true,"db":true,"migrated":true}
```

- `"db":"off"` — `DATABASE_URL` umuman berilmagan (1-bo'limga qarang).
- `"db":"starting"` — migratsiya hali ketyapti, 10–20 soniya kuting.
- `"db":"error"` — Render → `saler-server` → **Logs** bo'limida aniq sabab yozilgan bo'ladi.

## 3. Tez-tez uchraydigan xatolar

**"Server bazaga ulanmadi" / `/health` da `db: "error"`**
`DATABASE_URL` yo'q yoki noto'g'ri. Supabase'da **Session pooler** (`...pooler.supabase.com:5432`) manzilini oling,
Direct connection emas — Render'dan direct connection IPv6 orqali ishlamaydi.

**Supabase bazasi to'xtab qolgan**
Bepul Supabase loyihasi 7 kun so'rovsiz qolsa pauza qilinadi. Supabase panelida **Resume** bosing.
Oldini olish uchun kuniga bir marta `/health/db` ga so'rov yuboring (masalan cron-job.org orqali).

**Admin panel "Server bilan aloqa yo'q" deydi**
`saler-admin` → Environment → `NEXT_PUBLIC_API_URL` server manziliga to'g'ri ko'rsatayotganini tekshiring.
Bu qiymat **build vaqtida** kodga yoziladi — o'zgartirgach `Manual Deploy → Clear build cache & deploy` qilish shart.

**Birinchi so'rov 30–60 soniya ketadi**
Render bepul rejasida servis 15 daqiqa tinch tursa uxlab qoladi. Bu xato emas — birinchi so'rov uni uyg'otadi.

**`saler-web` build'i tushmayapti**
Flutter SDK yuklab olinadi, build 5–8 daqiqa. Bepul rejada xotira yetmasligi mumkin —
bunday holda `saler-web` ni o'chirib, mobil ilovani APK sifatida tarqating.

## 4. APK yig'ish (ilova serverni topishi uchun)

APK serverga **qaysi manzilga** ulanishini build vaqtida oladi. Shuning uchun yig'ishda
`env.json` ni berish kerak:

```bash
cd flutter_app

# Tarqatish uchun (tavsiya): har bir protsessor turiga alohida, ~20 MB
flutter build apk --release --split-per-abi --dart-define-from-file=env.json
# natija: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   (21.8 MB)
#         build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk (19.5 MB)

# Yoki bitta universal APK (hamma qurilmaga mos, lekin ~60 MB)
flutter build apk --release --dart-define-from-file=env.json
```

Zamonaviy telefonlarning deyarli hammasi **arm64-v8a** — odamlarga shuni bering.
Universal APK uch xil protsessor kodini birga tashigani uchun uch barobar og'ir.

`flutter_app/env.json`:

```json
{
  "API_BASE": "https://saler-server.onrender.com",
  "REALTIME_ENABLED": true,
  "BOT_USERNAME": "saler_ai_bot"
}
```

- `API_BASE` oxirida `/` bo'lmasin.
- `--dart-define-from-file` ni **unutib qo'ysangiz ham** ilova ishlaydi: release build
  `lib/config.dart` dagi `prodApiBase` ga tushadi. Serveringiz manzili boshqa bo'lsa,
  o'sha doimiyni ham yangilang.
- Debug (`flutter run`) da esa standart manzil emulyator uchun `http://10.0.2.2:3000`.

**"Serverga ulanib bo'lmadi" deb chiqsa**, avval brauzerda
`https://saler-server.onrender.com/health` ni oching — javobdagi `db` va `error`
maydonlari aniq sababni aytadi (1-bo'limga qarang).

## 5. Mahalliy sinov (Render'ga chiqarishdan oldin)

```bash
# Postgres
docker run -d --name saler-pg -e POSTGRES_PASSWORD=saler -e POSTGRES_DB=saler -p 55432:5432 postgres:16-alpine

# Backend
cd server && npm ci
DATABASE_URL="postgres://postgres:saler@127.0.0.1:55432/saler" ADMIN_PASSWORD=admin npm start

# Admin panel (boshqa terminalda)
cd admin && npm ci && npm run dev     # http://localhost:3100
```

## 6. AI provayderi

Server kalitlarni shu tartibda tekshiradi: `GROQ_API_KEY` → `ANTHROPIC_API_KEY`.
Birinchi topilgani ishlatiladi.

| Kalit | Standart |
|---|---|
| `GROQ_MODEL` | `openai/gpt-oss-120b` |
| `GROQ_FALLBACK_MODEL` | `openai/gpt-oss-20b` — asosiy model 429/500/503 bersa ishlatiladi |

Groq kaliti: console.groq.com/keys → Render → `saler-server` → Environment → `GROQ_API_KEY`.
**Kalitni hech qachon kodga yozmang** — u git tarixiga tushadi va ommaga ochiq bo'lib qoladi.
Lokal sinov uchun `server/.env` faylidan foydalaning (u `.gitignore` da).

Qaysi provayder va model ishlayotganini admin panel → **Tizim** sahifasida ko'rish mumkin.
Hech bir kalit berilmasa AI o'chadi, qolgan hamma narsa (katalog, buyurtma, kuryer) ishlayveradi.
