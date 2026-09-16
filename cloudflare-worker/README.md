# Saler AI — Cloudflare Worker + D1 + R2

Bu papka eski `server/` kodidan mustaqil, Cloudflare uchun tayyor backenddir.
Eski Express/PostgreSQL server o'zgartirilmagan.

## Deploy

```bash
cd cloudflare-worker
npm install
npm run db:migrate
npm run deploy
```

Worker sozlamalarida quyidagilar bo'lishi kerak:

- `DB` — `saler-db` D1 binding (konfiguratsiyada bor)
- `BREVO_API_KEY` — **Secret** (siz allaqachon qo'shgansiz)
- `BREVO_SENDER_EMAIL` — oddiy Variable, tasdiqlangan jo'natuvchi emaili
- `BREVO_SENDER_NAME` — oddiy Variable, masalan `Saler AI`
- `ADMIN_PASSWORD` — **Secret**, admin panelga kirish uchun o'zingiz tanlaydigan kuchli parol

Har yangi Worker versiyasidan oldin bazani ham yangilang:

```bash
npm run db:migrate
npm run deploy
```

`db:migrate` mavjud ma'lumotni o'chirmaydi; faqat yo'q jadval va indekslarni qo'shadi.

## Flutter ilovani ulash

Sinash/build qilishda API manzilini bering:

```bash
flutter run --dart-define=API_BASE=https://saler-api.akobirnorqulov104.workers.dev
```

Yoki `flutter_app/env.json` ichida quyidagini ishlating:

```json
{
  "API_BASE": "https://saler-api.akobirnorqulov104.workers.dev",
  "REALTIME_ENABLED": false
}
```

## Admin panelni ulash

`admin/` ilovasini build/deploy qilayotganda `NEXT_PUBLIC_API_URL` qiymatini Worker manziliga bering:

```bash
NEXT_PUBLIC_API_URL=https://saler-api.akobirnorqulov104.workers.dev npm run build
```

So'ng admin panel loginida Worker'dagi `ADMIN_PASSWORD` Secret qiymatini ishlating.

## Rasmlar: R2 oqimi

Flutter ilova rasmlarni base64 JSON o'rniga to'g'ridan-to'g'ri `/api/media/upload` ga yuboradi. Bu mobil trafikni qisqartiradi, D1 javoblarini kichraytiradi va bitta rasm qayta ochilganda edge cache ishlaydi.

Hozirgi fallback holatda R2 ulanmagan bo'lsa, rasm D1 ga faqat **900 KB** gacha yoziladi. Bu ishlaydi, lekin ko'p foydalanuvchi uchun R2 ni yoqish kerak.

R2 ni bir marta ulang:

1. Cloudflare Dashboard → **R2 Object Storage** → **Enable R2** ni bosing.
2. **Create bucket** → nomi `saler-media`.
3. **Workers & Pages** → `saler-api` → **Settings** → **Bindings** → **Add** → **R2 bucket**:
   - Variable name: `MEDIA`
   - Bucket: `saler-media`
4. Keyingi kod deployidan oldin `wrangler.jsonc` ga quyidagini qo'shing:

   ```jsonc
   "r2_buckets": [
     { "binding": "MEDIA", "bucket_name": "saler-media" }
   ]
   ```

Shundan keyin yangi rasmlar R2 ga (4 MB gacha) yoziladi; eski D1 rasmlar esa ishlashda davom etadi. Worker har kuni faqat eski guest metadata'sini tozalaydi — R2 fayllari uchun dashboardda lifecycle qoidasini o'zingiz alohida belgilashingiz mumkin.
