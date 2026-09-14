# Saler AI — Flutter ilova

Saler AI mobil ilovasi (Android/iOS). `server/` papkasidagi mustaqil backendga ulanadi.

## Ishga tushirish

1. Flutter SDK o'rnating: https://docs.flutter.dev/get-started/install
2. `lib/config.dart` faylida serverning ochiq HTTPS manzilini yozing:
   ```dart
   const apiBase = 'https://sizning-server.uz';
   ```
3. Terminalda:
   ```
   cd flutter_app
   flutter create . --platforms=android,ios   # android/ va ios/ papkalarini yaratadi (bir marta)
   flutter pub get
   flutter run
   ```

## Bildirishnomalar

Sotuvchi ilovaga kirgan bo'lsa, ilova har 20 soniyada yangi buyurtmalarni tekshiradi va
qurilmaga bildirishnoma chiqaradi (Android 13+ da birinchi ochilishda ruxsat so'raydi).
Ilova to'liq yopilganda ham kelishi uchun Firebase Cloud Messaging (FCM) ulash kerak —
`google-services.json` bo'lsa qo'shib beriladi.

## Android uchun ruxsatlar

`flutter create` dan keyin `android/app/src/main/AndroidManifest.xml` ga qo'shing:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

## iOS uchun

`ios/Runner/Info.plist` ga:
```xml
<key>NSLocationWhenInUseUsageDescription</key><string>Do'konlarni xaritada ko'rsatish uchun</string>
<key>NSPhotoLibraryUsageDescription</key><string>Mahsulot rasmini yuklash uchun</string>
<key>NSCameraUsageDescription</key><string>Mahsulot rasmini olish uchun</string>
```

## Tuzilishi

- `lib/main.dart` — ilova, mavzu (yorug'/qorong'i), navigatsiya
- `lib/config.dart` — server manzili
- `lib/api.dart` — server bilan ishlash (mehmon token, so'rovlar)
- `lib/models.dart` — Do'kon, Mahsulot, Buyurtma modellari
- `lib/state.dart` — savatcha, sevimlilar, joriy foydalanuvchi
- `lib/screens/` — ekranlar (xaridor va sotuvchi)

Kirish: ilova birinchi ochilganda serverdan mehmon akkaunt (token) oladi — Telegram shart emas.
Sotuvchi bo'limiga login/parol bilan kiriladi (bot orqali ro'yxatdan o'tilgan do'kon).

## Sozlash (env.json)

```bash
cp env.example.json env.json      # API_BASE ni server manziliga o'zgartiring
flutter pub get
flutter run --dart-define-from-file=env.json
flutter build apk --dart-define-from-file=env.json
```

- Emulyator + lokal bot: `"API_BASE": "http://10.0.2.2:3000"`
- Haqiqiy telefon: Render'dagi server manzili, masalan `https://saler-server.onrender.com`
