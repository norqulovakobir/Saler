import 'package:flutter/foundation.dart';

/// Ilova sozlamalari. Qiymatlar `env.json` dan olinadi:
///   flutter run --dart-define-from-file=env.json
///   flutter build apk --dart-define-from-file=env.json
/// Namuna: env.example.json. env.json git'ga kirmaydi.

/// Ishlayotgan server manzili (Render Blueprint dagi `saler-server`).
/// Oxirida `/` bo'lmasin.
const prodApiBase = 'https://saler-server.onrender.com';

const _apiBaseOverride = String.fromEnvironment('API_BASE');

/// API manzili. `--dart-define-from-file=env.json` berilsa — o'sha manzil.
/// Berilmasa: release (APK) uchun ishlaydigan server, debug uchun lokal server.
/// Shu fallback bo'lmasa, env'siz yig'ilgan APK haqiqiy telefonda `10.0.2.2` ga
/// urinib, doim "server ishlamayapti" ko'rsatardi.
/// Debug'da manzil platformaga qarab: brauzerda `localhost`, Android
/// emulyatorida esa `10.0.2.2` (emulyator uchun host shu manzilda ko'rinadi).
final apiBase = _apiBaseOverride.isNotEmpty
    ? _apiBaseOverride.replaceAll(RegExp(r'/+$'), '')
    : kReleaseMode
        ? prodApiBase
        : (kIsWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000');

/// Doimiy SSE oqimi. Bepul tariflarda so'rov limitini tejash uchun o'chirilishi
/// mumkin — sotuvchi buyurtma belgisi davriy yangilanish orqali ham keladi.
const realtimeEnabled = bool.fromEnvironment('REALTIME_ENABLED', defaultValue: true);

/// Ilova versiyasi (kirish xabarnomasida ko'rinadi)
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

/// Bot username (@ belgisisiz) — Telegram havolalari uchun.
const botUsername = String.fromEnvironment('BOT_USERNAME', defaultValue: 'saler_ai_bot');
