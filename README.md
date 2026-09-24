# Rydex

| Papka | Nima | Sozlama |
|---|---|---|
| `flutter_app/` | Android/iOS mobil ilova (Flutter) | `flutter_app/env.json` (namuna `env.example.json`) |
| `admin/` | Admin panel (Next.js) | `admin/.env.local` (namuna `admin/.env.example`) |
| `design/` | Dizayn maketlari | — |

## Tez boshlash

```bash
# Mobil ilova
cd flutter_app && cp env.example.json env.json && flutter run --dart-define-from-file=env.json

# Admin panel
cd admin && cp .env.example .env.local && npm install && npm run dev
```

Ildizdagi qisqa buyruqlar: `npm run admin`, `npm run admin:build`, `npm run admin:start`.
