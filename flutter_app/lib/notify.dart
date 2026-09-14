import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
}
