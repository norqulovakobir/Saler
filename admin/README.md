# Saler AI — Admin panel

Next.js 15 (App Router, JavaScript) + Tailwind v4 + Recharts. Ma'lumotlar `bot/` serveridagi `/api/admin/*` dan olinadi.

Dizayn: monoxrom (oq / qora), Inter shrifti. Mavzu yon paneldagi tugma bilan almashtiriladi, tanlov brauzerda saqlanadi; birinchi ochilishda tizim mavzusi olinadi.

## Bo'limlar

| Sahifa | Nima ko'rsatadi |
|---|---|
| Bosh sahifa | Tushum, buyurtma, do'kon, mahsulot, foydalanuvchi, ko'rish, o'rtacha chek, kuryer — haftalik o'sish bilan; tushum grafigi, holatlar donut, oxirgi buyurtmalar |
| Analitika | Oylik buyurtma/tushum, soat va hafta kunlari, top do'konlar/mahsulotlar/xaridorlar, narx va do'kon hajmi taqsimoti |
| Do'konlar | Qidiruv, mahsulot/ko'rish/buyurtma/tushum; do'kon sahifasida statistika, mahsulotlarni yashirish/o'chirish, buyurtma holatini o'zgartirish, do'konni o'chirish |
| Mahsulotlar | Qidiruv, faol/yashirin filtri, saralash, rasm ko'rish, yashirish/o'chirish |
| Buyurtmalar | Holat, sana oralig'i, qidiruv; holatni o'zgartirish (30 s da avto-yangilanadi) |
| Foydalanuvchilar | Rol (xaridor/sotuvchi), manba (Telegram/ilova), buyurtma va xarid summasi |
| Kuryerlar | Onlayn holati, transport, yetkazganlar, joylashuv |
| Tizim | Uptime, xotira, baza hajmi, bot, sozlamalar, server logi |

## Ishga tushirish

1. `bot/.env` ga admin parolini yozing:
   ```
   ADMIN_PASSWORD=kuchli_parol
   ```
   va bot serverini qayta ishga tushiring.
2. `admin/.env.local` da API manzili (standart `http://localhost:3000`):
   ```
   NEXT_PUBLIC_API_URL=http://localhost:3000
   ```
3. Paketlar va ishga tushirish:
   ```
   cd admin
   npm install
   npm run dev      # http://localhost:3100
   ```
   Ishlab chiqarish: `npm run build && npm start`.

## Xavfsizlik

- Kirish faqat `ADMIN_PASSWORD` bilan; token 7 kun amal qiladi va bazada saqlanmaydi (HMAC imzo).
- Noto'g'ri parolga javob 400 ms kechiktiriladi.
- Panelni internetga chiqarsangiz, HTTPS va uzun parol ishlating.

## Deploy

`next.config.mjs` da `output: 'standalone'` — Vercel, Render yoki Docker'da ishlaydi. Deploy'da `NEXT_PUBLIC_API_URL` ni bot serverining ochiq manziliga qo'ying.
