# Deploy (va "ishlamadi" bo'lsa nima qilish)

Loyiha ikki joyda turadi:

| Qayerda | Nima | Manzil |
|---|---|---|
| **Cloudflare** | Backend: Worker + D1 (baza) + R2 (rasmlar) + Brevo (email kodlari) | `https://saler-api.akobirnorqulov104.workers.dev` |
| **Render** | `saler-admin` — admin panel (Next.js) | `https://saler-admin.onrender.com` |
| **Render** | `saler-web` — Flutter ilovaning web versiyasi (Static Site) | `https://saler-web.onrender.com` |

Render'dagi ikkala servis ham backend sifatida Worker'ga ulanadi. Render'da
hech qanday baza yoki server yo'q.

## 1. Backend'ni chiqarish (Cloudflare Worker)

```bash
cd cloudflare-worker
npx wrangler login          # bir marta
npx wrangler deploy
```

Bindinglar `wrangler.jsonc` da yozilgan va deploy paytida ro'yxat chiqadi:

| Binding | Resurs | Nima uchun |
|---|---|---|
| `DB` | D1 `saler-db` | Butun baza. Bepul chegara: 5 GB, kuniga 5 mln o'qish / 100k yozish |
| `MEDIA` | R2 `saler-media` | Barcha rasmlar. Bepul chegara: 10 GB |
| `WEB_BASE` | o'zgaruvchi | Ulashish havolalari (`/p/<id>`, `/s/<id>`) shu manzilga o'tkazadi |

Rasm faqat R2 ga yoziladi. `MEDIA` binding yo'qolsa yuklash `503 Rasm ombori
ulanmagan` qaytaradi — bu ataylab: avval bunday holatda rasm jimgina bazaga
yozilardi va nosozlik ko'rinmasdan D1 ni to'ldirardi.

### Sirlar (kodda emas, `wrangler secret`)

```bash
npx wrangler secret put ADMIN_PASSWORD     # admin panelga kirish paroli
npx wrangler secret put BREVO_API_KEY      # tasdiqlash kodlarini yuborish
npx wrangler secret list                   # nima o'rnatilganini ko'rish
```

### Sxema

```bash
npx wrangler d1 execute saler-db --remote --file src/schema.sql
```

Fayl `CREATE TABLE IF NOT EXISTS` dan iborat — qayta ishga tushirilsa mavjud
ma'lumot o'chmaydi.

## 2. Tekshirish

```
https://saler-api.akobirnorqulov104.workers.dev/api/health
```

Kutilgan javob:

```json
{"ok":true,"service":"Rydex API","database":true,"email":true,
 "emailSender":true,"admin":true,"media":{"store":"r2"}}
```

| Maydon | `false` yoki boshqacha bo'lsa |
|---|---|
| `database` | `DB` binding ulanmagan — `wrangler.jsonc` ni tekshiring |
| `media.store` `"off"` | `MEDIA` binding yo'q, rasm yuklash ishlamaydi |
| `email` | `BREVO_API_KEY` yoki `BREVO_SENDER_EMAIL` qo'yilmagan — hech kim ro'yxatdan o'ta olmaydi |
| `admin` | `ADMIN_PASSWORD` qo'yilmagan — admin panelga kirib bo'lmaydi |

Loglarni jonli ko'rish: `npx wrangler tail`.

## 3. Render (admin va web)

Blueprint: Render Dashboard → **New → Blueprint** → shu repo → `render.yaml`
o'qiladi va ikkala servis yaratiladi. Qo'lda kiritiladigan env yo'q — ikkalasida
ham backend manzili `render.yaml` ichida yozilgan.

**Admin panel "Server bilan aloqa yo'q" desa:** `saler-admin` → Environment →
`NEXT_PUBLIC_API_URL` Worker manziliga to'g'ri ko'rsatayotganini tekshiring.
Bu qiymat **build vaqtida** kodga yoziladi — o'zgartirgach
`Manual Deploy → Clear build cache & deploy` qilish shart.

**`saler-web` build'i tushmayapti:** Flutter SDK yuklab olinadi, build 5–8
daqiqa. Bepul rejada xotira yetmasligi mumkin — bunday holda `saler-web` ni
o'chirib, mobil ilovani APK sifatida tarqating.

## 4. APK yig'ish

APK backend manzilini build vaqtida oladi:

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

`flutter_app/env.json`:

```json
{
  "API_BASE": "https://saler-api.akobirnorqulov104.workers.dev",
  "REALTIME_ENABLED": false,
  "BOT_USERNAME": "saler_ai_bot"
}
```

- `API_BASE` oxirida `/` bo'lmasin.
- `--dart-define-from-file` ni unutib qo'ysangiz ham ilova ishlaydi: release
  build `lib/config.dart` dagi `prodApiBase` ga tushadi (u ham Worker manzili).
- `REALTIME_ENABLED` `false`: Worker uzoq SSE oqimini ushlab turolmaydi,
  o'rniga davriy yangilanish ishlatiladi.
- Debug (`flutter run`) da standart manzil emulyator uchun `http://10.0.2.2:3000`.

## 5. AI provayderi

AI yordamchi Worker ichida qoidaga asoslangan (`src/ai.js` yo'q — kalit talab
qilinmaydi). Tashqi model ulansa, kaliti `wrangler secret` orqali beriladi,
hech qachon kodga yozilmaydi.

## 6. Limitlarni kuzatish

| Nima | Qayerda | Bepul chegara |
|---|---|---|
| D1 hajmi va kunlik so'rovlar | Cloudflare Dashboard → Workers & Pages → D1 → `saler-db` | 5 GB, 5 mln o'qish / 100k yozish kuniga |
| R2 hajmi | Cloudflare Dashboard → R2 → `saler-media` | 10 GB |
| Email | Brevo paneli | kuniga 300 ta |

Kunlik **yozish** limiti (100k) hajmdan oldin tugashi mumkin: har mahsulot
ko'rish, reels hodisasi va qidiruv bazaga yozadi.
