import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'api.dart';

/// Qurilma bildirishnomalari (Android/iOS). Web'da ilova ichidagi banner ishlatiladi.
class Notify {
  Notify._();
  static final Notify instance = Notify._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _id = 0;

  /// Ilova ichida ko'rsatish uchun (banner) — RootShell ulaydi
  void Function(String title, String body)? onInApp;

  Future<void> init() async {
    if (kIsWeb) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true);
      await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      // Rejalashtirilgan eslatma uchun mahalliy vaqt zonasi kerak
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Tashkent'));
      _ready = true;
    } catch (e) {
      debugPrint('Bildirishnoma init xatosi: $e');
    }
  }

  Future<void> show(String title, String body) async {
    onInApp?.call(title, body);
    if (!_ready) return;
    const android =
        AndroidNotificationDetails('orders', 'Buyurtmalar', channelDescription: 'Yangi buyurtmalar haqida bildirishnoma', importance: Importance.max, priority: Priority.high, playSound: true);
    const ios = DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: true);
    await _plugin.show(_id++, title, body, const NotificationDetails(android: android, iOS: ios));
  }

  /// Firebase push: token olinadi va serverga bog'lanadi. Server shu token
  /// orqali ilova yopiq bo'lsa ham xabar yubora oladi — lokal bildirishnoma
  /// buni qila olmaydi, u faqat qurilmada rejalashtiriladi.
  ///
  /// google-services.json qo'yilmagan bo'lsa Firebase ishga tushmaydi:
  /// xato yutiladi va ilova lokal bildirishnomalar bilan ishlayveradi.
  String? _pushToken;
  bool _pushStarted = false;

  Future<void> startPush() async {
    if (kIsWeb || _pushStarted) return;
    _pushStarted = true;
    try {
      await Firebase.initializeApp();
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(alert: true, badge: true, sound: true);
      await _bindToken(await fm.getToken());
      // Token vaqti-vaqti bilan yangilanadi — eskisi ishlamay qoladi
      fm.onTokenRefresh.listen(_bindToken);
      // Ilova ochiq turganda FCM o'zi bildirishnoma ko'rsatmaydi
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) show(n.title ?? 'Rydex', n.body ?? '');
      });
    } catch (e) {
      debugPrint('Push ishga tushmadi: $e');
    }
  }

  Future<void> _bindToken(String? token) async {
    if (token == null || token.isEmpty) return;
    _pushToken = token;
    try {
      await Api.instance.post('/api/push/register', {'token': token, 'platform': 'android'});
    } catch (e) {
      debugPrint('Push token yuborilmadi: $e');
    }
  }

  /// Chiqishda: bu qurilmaga endi xabar yuborilmasin
  Future<void> stopPush() async {
    final token = _pushToken;
    if (token == null) return;
    try {
      await Api.instance.post('/api/push/unregister', {'token': token});
    } catch (_) {}
  }

  /// Offline eslatmasining doimiy id'si — qayta rejalashtirilsa eskisi almashadi
  static const _nudgeId = 900001;

  /// Kuryer/yuk tashuvchi offline bo'lganda qo'yiladigan eslatma.
  ///
  /// Server ham shunga o'xshash turtki yuboradi, lekin u faqat push
  /// sozlangan bo'lsa ishlaydi. Bu esa qurilmaning o'zida rejalashtiriladi:
  /// Firebase bo'lmasa ham, internet bo'lmasa ham vaqti kelganda chiqadi.
  Future<void> scheduleOfflineNudge({Duration after = const Duration(hours: 3)}) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_nudgeId);
      const android = AndroidNotificationDetails('online_nudge', 'Onlayn eslatmasi',
          channelDescription: "Onlayn bo'lishni eslatuvchi xabar",
          importance: Importance.defaultImportance, priority: Priority.defaultPriority);
      const ios = DarwinNotificationDetails(presentAlert: true, presentSound: false);
      await _plugin.zonedSchedule(
        _nudgeId,
        'Bugun buyurtmalar ko\'p',
        "Onlayn bo'ling — xaridorlar sizni xaritada ko'rishsin va buyurtma berishsin.",
        tz.TZDateTime.now(tz.local).add(after),
        const NotificationDetails(android: android, iOS: ios),
        // Aniq vaqt talab qilinmaydi: aniq alarm uchun Android 12+ da
        // alohida ruxsat so'rash kerak bo'lardi, bu esa ortiqcha.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Eslatma rejalashtirilmadi: $e');
    }
  }

  /// Onlayn bo'lgan zahoti eslatma bekor qilinadi
  Future<void> cancelOfflineNudge() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_nudgeId);
    } catch (_) {}
  }
}
