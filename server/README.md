# Saler AI server

Mustaqil backend: Express + Postgres. Telegram botga bog'liq emas.
Flutter ilova (`/api/*`) va admin panel (`/api/admin/*`) shu serverga ulanadi.

## Lokal ishga tushirish

```bash
docker run -d --name saler-pg -e POSTGRES_PASSWORD=saler -e POSTGRES_DB=saler -p 5433:5432 postgres:16-alpine
cd server && npm install
cp .env.example .env   # yoki o'zgaruvchilarni terminalda bering
DATABASE_URL=postgres://postgres:saler@localhost:5433/saler ADMIN_PASSWORD=admin npm start
```

Jadval(lar) birinchi ishga tushishda avtomatik yaratiladi (`src/db.js` -> `migrate()`).

## Render

Repo ildizidagi `render.yaml` Blueprint: `saler-server`, `saler-admin`. Baza va rasmlar Supabase'da.
Dashboard -> New -> Blueprint -> repo tanlang. Keyin `saler-server` Environment'da `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_SECRET_KEY` va ixtiyoriy `GEMINI_API_KEY` kiriting.
`ADMIN_PASSWORD` avtomatik yaratiladi, qiymatini Environment bo'limidan ko'ring.

## Supabase (bepul baza va rasmlar)

Bazani va rasmlarni Supabase'ga ulash, Render'dan ma'lumot ko'chirish: [`deploy/supabase/README.md`](../deploy/supabase/README.md).

## Oracle Cloud (bepul, doim yoniq)

Baza, server va HTTPS'ni bitta bepul Oracle serveriga o'rnatish: [`deploy/oracle/README.md`](../deploy/oracle/README.md).

## Muhit o'zgaruvchilari

| Nomi | Majburiy | Izoh |
|---|---|---|
| `DATABASE_URL` | ha | Postgres connection string |
| `PORT` | yo'q | Render o'zi beradi |
| `ADMIN_PASSWORD` | ha | Admin panel paroli |
| `GEMINI_API_KEY` | yo'q | Google Gemini: AI yordamchi, do'kon chati, maslahatlar |
| `GEMINI_MODEL` | yo'q | Standart `gemini-3.6-flash` |
| `GEMINI_FALLBACK_MODEL` | yo'q | Asosiy model band bo'lsa ishlatiladi, standart `gemini-3.5-flash` |
| `ANTHROPIC_API_KEY` | yo'q | Gemini kaliti bo'lmasa Claude ishlatiladi |
| `AI_MODEL` | yo'q | Claude modeli, standart `claude-opus-5` |
| `SUPABASE_URL` | yo'q | Berilsa, rasmlar Supabase Storage'ga yoziladi |
| `SUPABASE_SECRET_KEY` | yo'q | Supabase secret key (`sb_secret_...`) |
| `SUPABASE_BUCKET` | yo'q | Standart `photos` |

## Tuzilishi

- `src/server.js` — Express, `/api/photo/:ref`, `/api/report/:key`, xato ishlovchi
- `src/db.js` — Postgres ulanish va sxema
- `src/api.js` — auth (mehmon token), katalog, buyurtma, AI chat, sotuvchi paneli, analitika
- `src/courier.js` — kuryer/yuk tashuvchi, yaqin kuryerlar, yuk buyurtmalari, OSRM marshrut proksi
- `src/admin.js` — admin panel API
- `src/ai.js` — Google Gemini (yoki Claude) orqali AI javoblar (kalit bo'lmasa fallback)

## Eslatmalar

- Rasmlar `SUPABASE_URL` berilsa Supabase Storage'da, berilmasa Postgres'dagi `photos` jadvalida saqlanadi. Eski rasmlarni ko'chirish: `node scripts/move-photos.js`.
- `/health/db` bazaga haqiqiy so'rov yuboradi. Supabase bepul loyihasi to'xtab qolmasligi uchun kuniga bir marta chaqirish mumkin.
- Kuryer biriktirish avtomatik: yangi buyurtma do'konga eng yaqin onlayn kuryerga beriladi, rad etsa keyingisiga.
- Supabase'da jadvallar uchun RLS avtomatik yoqiladi, shuning uchun Data API orqali ma'lumot ochilib qolmaydi.
