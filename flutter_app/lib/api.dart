import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  final bool rejected;
  ApiException(this.message, this.status, {this.rejected = false});
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

  Future<void> init() async {
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

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  String photoUrl(String ref) => '$apiBase/api/photo/${Uri.encodeComponent(ref)}';

  /// GET javoblari keshi: sahifaga qayta kirganda darhol ko'rsatiladi, fonda yangilanadi
  final Map<String, dynamic> _cache = {};
  dynamic cached(String path) => _cache[path];
  void clearCache() => _cache.clear();

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final uri = Uri.parse('$apiBase$path');
    late http.Response r;
    final b = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        r = await http.get(uri, headers: _headers);
      case 'POST':
        r = await http.post(uri, headers: _headers, body: b);
      case 'PUT':
        r = await http.put(uri, headers: _headers, body: b);
      case 'PATCH':
        r = await http.patch(uri, headers: _headers, body: b);
      case 'DELETE':
        r = await http.delete(uri, headers: _headers);
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
    if (r.statusCode >= 400) {
      final msg = data is Map ? (data['error'] ?? 'Xato ${r.statusCode}') : 'Xato ${r.statusCode}';
      throw ApiException(msg, r.statusCode, rejected: data is Map && data['rejected'] == true);
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
