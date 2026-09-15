/// Ilova sozlamalari. Qiymatlar `env.json` dan olinadi:
///   flutter run --dart-define-from-file=env.json
///   flutter build apk --dart-define-from-file=env.json
/// Namuna: env.example.json. env.json git'ga kirmaydi.
///
/// API_BASE — bot serverining manzili (oxirida / bo'lmasin).
/// Emulyatorda lokal server: http://10.0.2.2:3000, haqiqiy telefonda tunnel HTTPS manzili.
const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:3000');

/// Ilova versiyasi (kirish xabarnomasida ko'rinadi)
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

/// Bot username (@ belgisisiz) — Telegram havolalari uchun.
const botUsername = String.fromEnvironment('BOT_USERNAME', defaultValue: 'saler_ai_bot');
