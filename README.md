# Saler AI

Uchta mustaqil qism, har birining o'z sozlama fayli bor:

| Papka | Nima | Sozlama |
|---|---|---|
| `bot/` | Telegram bot + API server (Node.js, MongoDB, Groq) | `bot/.env` (namuna `bot/.env.example`) |
| `mini_app/` | Telegram Mini App — statik frontend | `mini_app/config.js` (namuna `config.example.js`) |
| `flutter_app/` | Android/iOS mobil ilova (Flutter) | `flutter_app/env.json` (namuna `env.example.json`) |
| `design/` | Dizayn maketlari | — |

## Tez boshlash

```bash
# 1. Bot + API
cd bot && cp .env.example .env && npm install && npm start

# 2. Mini App — bot bilan birga http://localhost:3000 da ochiladi,
#    yoki alohida: cd mini_app && npm start

# 3. Mobil ilova
cd flutter_app && cp env.example.json env.json && flutter run --dart-define-from-file=env.json
```

Ildizdagi qisqa buyruqlar: `npm run bot`, `npm run bot:dev`, `npm run bot:tunnel`, `npm run mini_app`.
