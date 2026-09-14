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

Repo ildizidagi `render.yaml` Blueprint: `saler-db` (Postgres), `saler-server`, `saler-admin`.
Dashboard -> New -> Blueprint -> repo tanlang. Keyin `saler-server` Environment'da `ANTHROPIC_API_KEY` kiriting (ixtiyoriy).
`ADMIN_PASSWORD` avtomatik yaratiladi, qiymatini Environment bo'limidan ko'ring.

## Muhit o'zgaruvchilari

| Nomi | Majburiy | Izoh |
|---|---|---|
| `DATABASE_URL` | ha | Postgres connection string |
| `PORT` | yo'q | Render o'zi beradi |
| `ADMIN_PASSWORD` | ha | Admin panel paroli |
| `ANTHROPIC_API_KEY` | yo'q | AI yordamchi, do'kon chati, maslahatlar |
| `AI_MODEL` | yo'q | Standart `claude-opus-5` |

## Tuzilishi

- `src/server.js` — Express, `/api/photo/:ref`, `/api/report/:key`, xato ishlovchi
- `src/db.js` — Postgres ulanish va sxema
- `src/api.js` — auth (mehmon token), katalog, buyurtma, AI chat, sotuvchi paneli, analitika
- `src/courier.js` — kuryer/yuk tashuvchi, yaqin kuryerlar, yuk buyurtmalari, OSRM marshrut proksi
- `src/admin.js` — admin panel API
- `src/ai.js` — Anthropic SDK orqali AI javoblar (kalit bo'lmasa fallback)

## Eslatmalar

- Rasmlar Postgres'da (`photos` jadvali) saqlanadi, tashqi storage kerak emas.
- Kuryer biriktirish avtomatik: yangi buyurtma do'konga eng yaqin onlayn kuryerga beriladi, rad etsa keyingisiga.
- Render free Postgres 30 kundan keyin o'chadi — keyin Neon/Supabase (bepul) manzilini `DATABASE_URL` ga qo'ying.
