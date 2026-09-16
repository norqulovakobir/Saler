import 'dart:async';
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  final bool rejected;

  /// Server javobi: xato tegishli maydon ('field'), tasdiqlash kodi holati, test rejimidagi kod
  final Map<String, dynamic> data;
  ApiException(this.message, this.status, {this.rejected = false, this.data = const {}});
  String? get field => data['field']?.toString();
  @override
  String toString() => message;
}

/// Server bilan ishlash. Birinchi ishga tushganda mehmon akkaunt (token) oladi.
class Api {
  Api._();
  static final Api instance = Api._();

  String? _token;
  int? userId;
  String userName = 'Xaridor';

  /// Ro'yxatdan o'tgan xaridor hisobi (ilovadan foydalanish uchun majburiy)
  bool registered = false;
  String? phone;
  String firstName = '';
  String lastName = '';
  String? email;
  String? telegram;

  /// Server hisob talab qilganda (403 needAuth) chaqiriladi: ilova kirish ekraniga qaytadi
  void Function()? onNeedAuth;

  Future<void> saveUser(Map u) async {
    userId = (u['id'] as num?)?.toInt() ?? userId;
    userName = (u['name'] ?? userName).toString();
    phone = u['phone']?.toString();
    firstName = (u['firstName'] ?? '').toString();
    lastName = (u['lastName'] ?? '').toString();
    email = u['email']?.toString();
    telegram = u['telegram']?.toString();
    registered = u['registered'] == true;
    final prefs = await SharedPreferences.getInstance();
    if (userId != null) await prefs.setInt('userId', userId!);
    await prefs.setString('userName', userName);
  }

  /// Hisobdan chiqish: server sessiyasi o'chiriladi va yangi mehmon sessiyasi olinadi
  Future<void> logout() async {
    try {
      await post('/api/auth/logout');
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('userId');
    await prefs.remove('userName');
    _token = null;
    userId = null;
    userName = 'Xaridor';
    registered = false;
    phone = null;
    firstName = '';
    lastName = '';
    email = null;
    telegram = null;
    clearCache();
    await _guest(prefs);
  }

  /// Kirish xabarnomasi uchun: qaysi qurilma va ilovadan, qayerdan kirilgani
  String _device = '';
  String _app = 'Rydex $appVersion';
  String? _location;

  Future<void> _loadClientInfo() async {
    try {
      final info = DeviceInfoPlugin();
      if (kIsWeb) {
        final w = await info.webBrowserInfo;
        _device = '${w.browserName.name} brauzer';
        _app = 'Rydex $appVersion (veb)';
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final a = await info.androidInfo;
        _device = '${a.manufacturer} ${a.model} · Android ${a.version.release}';
        _app = 'Rydex $appVersion (Android ilova)';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final i = await info.iosInfo;
        _device = '${i.model} · iOS ${i.systemVersion}';
        _app = 'Rydex $appVersion (iOS ilova)';
      }
    } catch (_) {}
  }

  /// Oxirgi ma'lum joylashuv. Ruxsat so'ralmaydi: faqat ilgari berilgan bo'lsa olinadi
  Future<void> refreshLocation() async {
    if (kIsWeb) return;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return;
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) _location = '${pos.latitude.toStringAsFixed(5)},${pos.longitude.toStringAsFixed(5)}';
    } catch (_) {}
  }

  /// HTTP sarlavhasi faqat ASCII belgilarni qabul qiladi: "·" kabi belgilar so'rovni buzadi
  static String _hv(String s) => s.replaceAll('·', '-').replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();

  Future<void> init() async {
    await _loadClientInfo();
    unawaited(refreshLocation());
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    userId = prefs.getInt('userId');
    userName = prefs.getString('userName') ?? 'Xaridor';
    if (_token == null) await _guest(prefs);
  }

  Future<void> _guest(SharedPreferences prefs) async {
    final r = await http.post(Uri.parse('$apiBase/api/auth/guest'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'name': userName}));
    if (r.statusCode != 200) throw ApiException('Serverga ulanib bo\'lmadi', r.statusCode);
    final j = jsonDecode(r.body);
    _token = j['token'];
    userId = j['user']['id'];
    await prefs.setString('token', _token!);
    await prefs.setInt('userId', userId!);
  }

  Map<String, String> get authHeaders => _headers;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
        if (_device.isNotEmpty) 'X-Device': _hv(_device),
        'X-App': _hv(_app),
      };

  String photoUrl(String ref) => '$apiBase/api/photo/${Uri.encodeComponent(ref)}';

  /// Tanlangan rasmni JSON/base64 emas, to'g'ridan-to'g'ri binary so'rovda
  /// yuboradi. Bu mobil internet trafikini va Worker/D1 yuklamasini kamaytiradi.
  /// Eski backend hali `/media/upload` ni tanimasa, mavjud oqim buzilmasligi
  /// uchun vaqtincha data URI qaytariladi.
  Future<String> uploadImage(Uint8List bytes, {String mime = 'image/jpeg', bool retried = false}) async {
    if (bytes.isEmpty) throw ApiException("Rasm bo'sh", 400);
    if (bytes.lengthInBytes > 4 * 1024 * 1024) {
      throw ApiException("Rasm 4 MB dan katta bo'lmasin", 413);
    }
    final imageMime = _normaliseImageMime(mime);
    final uri = Uri.parse('$apiBase/api/media/upload');
    final headers = {..._headers, 'Content-Type': imageMime};
    late http.Response response;
    try {
      response = await http.post(uri, headers: headers, body: bytes);
    } on Exception {
      throw ApiException("Rasmni serverga yuborib bo'lmadi", 0);
    }
    if (response.statusCode == 401 && !retried) {
      await _guest(await SharedPreferences.getInstance());
      return uploadImage(bytes, mime: imageMime, retried: true);
    }
    if (response.statusCode == 404 || response.statusCode == 405 || response.statusCode == 501) {
      return 'data:$imageMime;base64,${base64Encode(bytes)}';
    }
    dynamic data;
    try {
      data = response.body.isEmpty ? {} : jsonDecode(response.body);
    } catch (_) {
      data = {};
    }
    if (response.statusCode >= 400) {
      final message = data is Map ? (data['error'] ?? 'Xato ${response.statusCode}').toString() : 'Xato ${response.statusCode}';
      throw ApiException(message, response.statusCode, data: data is Map ? Map<String, dynamic>.from(data) : const {});
    }
    final ref = data is Map ? data['ref']?.toString().trim() : null;
    if (ref == null || ref.isEmpty) throw ApiException("Rasm manzili olinmadi", response.statusCode);
    return ref;
  }

  static String imageMimeForPath(String path) {
    final normalized = path.toLowerCase().split('?').first;
    if (normalized.endsWith('.png')) return 'image/png';
    if (normalized.endsWith('.webp')) return 'image/webp';
    if (normalized.endsWith('.avif')) return 'image/avif';
    if (normalized.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  static String _normaliseImageMime(String value) {
    switch (value.toLowerCase().split(';').first.trim()) {
      case 'image/png':
      case 'image/webp':
      case 'image/avif':
      case 'image/gif':
      case 'image/jpg':
      case 'image/jpeg':
        return value.toLowerCase().split(';').first.trim();
      default:
        return 'image/jpeg';
    }
  }

  /// GET javoblari keshi: sahifaga qayta kirganda darhol ko'rsatiladi, fonda yangilanadi
  final Map<String, dynamic> _cache = {};
  dynamic cached(String path) => _cache[path];
  void clearCache() => _cache.clear();

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final uri = Uri.parse('$apiBase$path');
    late http.Response r;
    final b = body == null ? null : jsonEncode(body);
    // Joylashuv faqat hisobga kirish so'rovida yuboriladi (xavfsizlik xabarnomasi uchun)
    if (path.endsWith('/login')) await refreshLocation();
    final h = {..._headers, if (path.endsWith('/login') && _location != null) 'X-Location': _location!};
    switch (method) {
      case 'GET':
        r = await http.get(uri, headers: h);
      case 'POST':
        r = await http.post(uri, headers: h, body: b);
      case 'PUT':
        r = await http.put(uri, headers: h, body: b);
      case 'PATCH':
        r = await http.patch(uri, headers: h, body: b);
      case 'DELETE':
        r = await http.delete(uri, headers: h);
    }
    // Token eskirgan bo'lsa — yangi mehmon akkaunt
    if (r.statusCode == 401 && path != '/api/auth/guest') {
      await _guest(await SharedPreferences.getInstance());
      return _send(method, path, body: body);
    }
    dynamic data;
    try {
      data = r.body.isEmpty ? {} : jsonDecode(r.body);
    } catch (_) {
      data = {};
    }
    if (r.statusCode == 403 && data is Map && data['needAuth'] == true) {
      registered = false;
      onNeedAuth?.call();
    }
    if (r.statusCode >= 400) {
      final msg = data is Map ? (data['error'] ?? 'Xato ${r.statusCode}') : 'Xato ${r.statusCode}';
      throw ApiException(msg, r.statusCode,
          rejected: data is Map && data['rejected'] == true, data: data is Map ? Map<String, dynamic>.from(data) : const {});
    }
    if (method == 'GET') {
      _cache[path] = data;
    } else if (!path.startsWith('/api/products/') || !path.endsWith('/view')) {
      _cache.clear(); // o'zgartirishdan keyin eski ma'lumot ko'rinmasin
    }
    return data;
  }

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? {});
  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);
}
