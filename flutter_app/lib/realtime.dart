import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api.dart';
import 'config.dart';

/// Serverdan kelgan jonli hodisa: order:new, order:update, order:assigned, money, notification, cargo:new, cargo:update, stats
class RtEvent {
  final String type;
  final Map<String, dynamic> data;
  const RtEvent(this.type, this.data);
}

/// Jonli hodisalar oqimi (Server-Sent Events).
/// Server buyurtma, pul tushishi, bildirishnoma kabi o'zgarishlarni darhol yuboradi, ekranlar joyida yangilanadi.
/// Aloqa uzilsa, o'zi qayta ulanadi (2, 5, 10, 20, 30 soniyadan keyin).
class Realtime {
  Realtime._();
  static final Realtime instance = Realtime._();

  final _ctrl = StreamController<RtEvent>.broadcast();
  Stream<RtEvent> get events => _ctrl.stream;

  http.Client? _client;
  StreamSubscription<String>? _sub;
  Timer? _retry;
  bool _running = false;
  int _attempt = 0;
  int _generation = 0; // eski ulanishning kechikkan javoblarini e'tiborsiz qoldirish uchun

  /// Hozir server bilan jonli aloqa bormi
  bool connected = false;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  void stop() {
    _running = false;
    _generation++;
    _retry?.cancel();
    _sub?.cancel();
    _client?.close();
    _client = null;
    connected = false;
  }

  /// Sessiya o'zgarganda (sotuvchi yoki kuryer kirdi/chiqdi) yangi kanallarga ulanish uchun
  void restart() {
    stop();
    start();
  }

  Future<void> _connect() async {
    // Veb-brauzerda http javobi bo'laklab kelmaydi; u yerda davriy so'rovlar ishlaydi
    if (!_running || kIsWeb || !realtimeEnabled) return;
    final gen = ++_generation;
    _sub?.cancel();
    _client?.close();
    final client = _client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse('$apiBase/api/events'))..headers.addAll(Api.instance.authHeaders);
      final res = await client.send(req);
      if (gen != _generation) return;
      if (res.statusCode != 200) throw Exception('SSE ${res.statusCode}');
      connected = true;
      _attempt = 0;
      var event = '';
      var data = StringBuffer();
      _sub = res.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) {
          if (line.isEmpty) {
            if (data.isNotEmpty) {
              try {
                final j = jsonDecode(data.toString());
                if (j is Map) {
                  final d = j['data'];
                  _ctrl.add(RtEvent((j['type'] ?? event).toString(), d is Map ? d.cast<String, dynamic>() : const {}));
                }
              } catch (_) {}
            }
            event = '';
            data = StringBuffer();
          } else if (line.startsWith('event:')) {
            event = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            data.write(line.substring(5).trim());
          }
        },
        onDone: () => _scheduleRetry(gen),
        onError: (_) => _scheduleRetry(gen),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry(gen);
    }
  }

  void _scheduleRetry(int gen) {
    if (gen != _generation) return;
    connected = false;
    if (!_running) return;
    _retry?.cancel();
    const delays = [2, 5, 10, 20, 30];
    final secs = delays[_attempt.clamp(0, delays.length - 1)];
    _attempt++;
    _retry = Timer(Duration(seconds: secs), _connect);
  }
}
