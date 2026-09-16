# EmailJS: tasdiqlash kodlarini yuborish

Ro'yxatdan o'tish (sotuvchi, kuryer, yuk tashuvchi), xaridor buyurtmasi va parolni tiklashda
emailga 6 xonali kod yuboriladi. Kod EmailJS orqali ketadi.

## 1. Kerakli 4 ta qiymat

| Env o'zgaruvchi | Qayerdan olinadi |
| --- | --- |
| `EMAILJS_SERVICE_ID` | Email Services > xizmat kartasidagi ID (masalan `service_xsy4cnv`) |
| `EMAILJS_TEMPLATE_ID` | Email Templates > shablon ID (masalan `template_j95i924`) |
| `EMAILJS_PUBLIC_KEY` | Account > General > Public Key |
| `EMAILJS_PRIVATE_KEY` | Account > General (yoki Security) > Private Key |

Server ular bilan `https://api.emailjs.com/api/v1.0/email/send` ga so'rov yuboradi.

## 2. Account > Security sozlamasi

EmailJS odatda faqat brauzerdan yuborishga ruxsat beradi. Server yuborishi uchun:

- **"Allow EmailJS API for non-browser applications"** — yoqilgan bo'lsin.
- API talab qilsa, `EMAILJS_PRIVATE_KEY` to'ldirilgan bo'lishi kerak (u `accessToken` sifatida yuboriladi).

## 3. Shablon (Email Template)

Shablon sozlamalarida:

- **To Email**: `{{to_email}}`
- **From Name**: Saler AI
- **Subject**: `Saler AI · tasdiqlash kodi {{code}}`

Matn namunasi:

```
Assalomu alaykum, {{to_name}}!

{{purpose}} uchun tasdiqlash kodi: {{code}}

Kod {{time}} davomida amal qiladi. Agar bu siz bo'lmasangiz, xatni e'tiborsiz qoldiring.

Saler AI
```

Server yuboradigan barcha o'zgaruvchilar: `to_email`, `email`, `to_name`, `name`, `code`,
`passcode`, `purpose`, `time`, `app_name`.

## 4. Kalitlarni qo'yish

Lokal ishlashda `server/.env` fayliga yozing:

```
EMAILJS_SERVICE_ID=service_xsy4cnv
EMAILJS_TEMPLATE_ID=template_j95i924
EMAILJS_PUBLIC_KEY=...
EMAILJS_PRIVATE_KEY=...
```

Render'da: Dashboard > saler-server > Environment > shu 4 ta qiymatni qo'shing
(`render.yaml` da ular `sync: false` bilan turibdi) va `NODE_ENV=production` bo'lsin.

## 5. Test rejimi

`EMAILJS_PUBLIC_KEY` bo'lmasa va `NODE_ENV` ishlab chiqarish bo'lmasa, server email yubormaydi:
kod server logida `[TEST] ... tasdiqlash kodi: 123456` ko'rinishida chiqadi va ilovada kod
maydoni ustida "Test rejimi" yozuvi bilan avtomatik to'ldiriladi. Bu emulyatorda sinash uchun.

`NODE_ENV=production` bo'lsa, kod hech qachon javobda qaytmaydi: kalitlar bo'lmasa
"Email xizmati hali sozlanmagan" xatosi chiqadi.

## 6. Tekshirish

Admin panel > Tizim sahifasida **Email (EmailJS)** kartasi holatni ko'rsatadi:
"Ulangan", "Test rejimi" yoki "Sozlanmagan".

## 7. Cheklovlar

- Kod 10 daqiqa amal qiladi, 5 marta xato kiritilsa bekor bo'ladi.
- Qayta yuborish: 60 soniyada bir marta, bir emailga soatiga 6 martagacha.
- Bazada kodning o'zi emas, SHA-256 xeshi saqlanadi (`email_codes` jadvali).
