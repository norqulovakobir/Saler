import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'models.dart';
import 'notify.dart';
import 'realtime.dart';

class CartItem {
  final Product product;
  int qty;
  CartItem(this.product, this.qty);
}

/// Xaridor uchun ilova ichida saqlanadigan bildirishnoma.
/// Serverdagi sotuvchi xabarnomalaridan alohida: telefon shu ilovaga kelgan
/// yangi mahsulot va boshqa jonli hodisalarni keyin ham ko'rsatib bera oladi.
class AppNotice {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  bool read;

  AppNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'read': read,
      };

  factory AppNotice.fromJson(Map<String, dynamic> json) => AppNotice(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        read: json['read'] == true,
      );
}

/// Ilova holati: mavzu, savatcha, sevimlilar, sotuvchi do'koni
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  ThemeMode themeMode = ThemeMode.system;
  final List<CartItem> cart = [];
  final Map<String, Product> favs = {};
  Shop? sellerShop; // sotuvchi sifatida kirilgan do'kon
  Courier? courier; // kuryer sifatida kirilgan akkaunt
  Shop? chatShop; // chat ochiladigan do'kon
  int newOrders = 0;
  int unread = 0;

  /// Xaridor ko'radigan lokal bildirishnomalar. Oxirgi 60 tasi telefonda
  /// saqlanadi, shu bois qo'ng'iroqcha bosilganda yo'qolib ketmaydi.
  final List<AppNotice> notices = [];
  int get noticeUnread => notices.where((notice) => !notice.read).length;

  /// Tanishtiruv (til tanlash va bannerlar) ko'rilganmi: faqat birinchi kirishda ko'rsatiladi
  bool onboarded = false;

  Future<void> setOnboarded() async {
    onboarded = true;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('onboarded', true);
  }

  /// Rol tanlangan (xaridor, sotuvchi, kuryer, yuk tashuvchi): tanishtiruvdan keyin bir marta so'raladi
  bool rolePicked = false;

  Future<void> setRolePicked() async {
    rolePicked = true;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('rolePicked', true);
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    onboarded = p.getBool('onboarded') ?? false;
    rolePicked = p.getBool('rolePicked') ?? false;
    themeMode = ThemeMode.values[p.getInt('theme') ?? 0];
    L10n.lang = AppLang
        .values[(p.getInt('lang') ?? 0).clamp(0, AppLang.values.length - 1)];
    for (final s in p.getStringList('favs') ?? const []) {
      final pr = Product.fromJson(jsonDecode(s));
      favs[pr.id] = pr;
    }
    for (final s in p.getStringList('cart') ?? const []) {
      final j = jsonDecode(s);
      cart.add(CartItem(Product.fromJson(j['p']), j['q']));
    }
    notices.clear();
    for (final s in p.getStringList('notices') ?? const []) {
      try {
        notices.add(AppNotice.fromJson(
            Map<String, dynamic>.from(jsonDecode(s) as Map)));
      } catch (_) {}
    }
    try {
      final me = await Api.instance.get('/api/me');
      if (me['user'] is Map) await Api.instance.saveUser(me['user']);
      if (me['shop'] != null) sellerShop = Shop.fromJson(me['shop']);
      if (me['courier'] != null) courier = Courier.fromJson(me['courier']);
    } catch (_) {}
    notifyListeners();
  }

  /// Hisobga kirgandan yoki chiqqandan keyin foydalanuvchi, do'kon va kuryer ma'lumotini qayta oladi
  Future<void> reloadMe() async {
    try {
      final me = await Api.instance.get('/api/me');
      if (me['user'] is Map) await Api.instance.saveUser(me['user']);
      sellerShop = me['shop'] != null ? Shop.fromJson(me['shop']) : null;
      courier = me['courier'] != null ? Courier.fromJson(me['courier']) : null;
    } catch (_) {}
    notifyListeners();
  }

  /// Tashqaridan holat o'zgarganda ekranlarni yangilash
  void refresh() => notifyListeners();

  /// Ilova tili (xaridor: tepadagi tugma, sotuvchi: profil)
  Future<void> setLang(AppLang l) async {
    L10n.lang = l;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt('lang', l.index);
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt('theme', m.index);
  }

  Future<void> _saveFavs() async =>
      (await SharedPreferences.getInstance()).setStringList(
          'favs', favs.values.map((p) => jsonEncode(p.toJson())).toList());
  Future<void> _saveCart() async =>
      (await SharedPreferences.getInstance()).setStringList(
          'cart',
          cart
              .map((c) => jsonEncode({'p': c.product.toJson(), 'q': c.qty}))
              .toList());
  Future<void> _saveNotices() async =>
      (await SharedPreferences.getInstance()).setStringList('notices',
          notices.map((notice) => jsonEncode(notice.toJson())).toList());

  void _recordNotice(String title, String body, {String? id}) {
    final noticeId = id?.isNotEmpty == true
        ? id!
        : 'local_${DateTime.now().microsecondsSinceEpoch}';
    final existing = notices.indexWhere((notice) => notice.id == noticeId);
    if (existing >= 0) notices.removeAt(existing);
    notices.insert(
        0,
        AppNotice(
            id: noticeId,
            title: title.trim().isEmpty ? 'Rydex' : title.trim(),
            body: body.trim(),
            createdAt: DateTime.now()));
    if (notices.length > 60) notices.removeRange(60, notices.length);
    unawaited(_saveNotices());
  }

  void markNoticesRead() {
    if (notices.every((notice) => notice.read)) return;
    for (final notice in notices) {
      notice.read = true;
    }
    unawaited(_saveNotices());
    notifyListeners();
  }

  void clearNotices() {
    if (notices.isEmpty) return;
    notices.clear();
    unawaited(_saveNotices());
    notifyListeners();
  }

  bool isFav(String id) => favs.containsKey(id);
  void toggleFav(Product p) {
    favs.containsKey(p.id) ? favs.remove(p.id) : favs[p.id] = p;
    notifyListeners();
    _saveFavs();
  }

  int get cartCount => cart.fold(0, (s, c) => s + c.qty);
  int get cartTotal => cart.fold(0, (s, c) => s + c.product.price * c.qty);

  /// Boshqa do'kon mahsuloti bo'lsa false qaytaradi (tasdiqlash kerak)
  bool addToCart(Product p, {bool force = false}) {
    if (cart.isNotEmpty && cart.first.product.shopId != p.shopId) {
      if (!force) return false;
      cart.clear();
    }
    final it = cart.where((c) => c.product.id == p.id).firstOrNull;
    it != null ? it.qty = (it.qty + 1).clamp(1, 50) : cart.add(CartItem(p, 1));
    notifyListeners();
    _saveCart();
    return true;
  }

  void changeQty(CartItem it, int d) {
    it.qty += d;
    if (it.qty <= 0) cart.remove(it);
    notifyListeners();
    _saveCart();
  }

  void clearCart() {
    cart.clear();
    notifyListeners();
    _saveCart();
  }

  /// Jonli hodisalar: har yangi hodisada oshadi, ekranlar shu o'zgarganda joyida qayta yuklanadi
  int liveVersion = 0;
  RtEvent? lastEvent;
  StreamSubscription<RtEvent>? _live;

  void startLive() {
    _live ??= Realtime.instance.events.listen(_onLive);
    Realtime.instance.start();
  }

  void _onLive(RtEvent e) {
    if (e.type == 'hello') return;
    lastEvent = e;
    liveVersion++;
    if (e.type == 'notification') {
      _lastNotifId = e.data['id']?.toString() ?? _lastNotifId;
      final title = e.data['title']?.toString() ?? '';
      final text = e.data['text']?.toString() ?? '';
      _recordNotice(title, text, id: _lastNotifId);
      unawaited(Notify.instance.show(title, text));
    } else if (e.type == 'product:new') {
      final title = "${e.data['shopName'] ?? "Do'kon"}: yangi mahsulot";
      final text = e.data['name']?.toString() ?? '';
      _recordNotice(title, text, id: e.data['id']?.toString());
      unawaited(Notify.instance.show(title, text));
    }
    if (sellerShop != null) refreshBadges();
    notifyListeners();
  }

  Timer? _poll;
  int? _lastNewOrders; // bildirishnoma uchun oldingi qiymat
  String? _lastNotifId;

  /// Sotuvchi rejimida har 20 soniyada yangi buyurtmalarni tekshiradi
  void startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => refreshBadges());
    refreshBadges();
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
    _lastNewOrders = null;
  }

  Future<void> refreshBadges() async {
    if (sellerShop == null) return;
    try {
      final b = await Api.instance.get('/api/seller/badges');
      newOrders = b['newOrders'] ?? 0;
      unread = b['unread'] ?? 0;
      // Yangi buyurtma paydo bo'ldi — qurilmaga bildirishnoma
      // Jonli aloqa bo'lsa bildirishnoma hodisa bilan allaqachon kelgan, takrorlanmaydi
      if (_lastNewOrders != null &&
          newOrders > _lastNewOrders! &&
          !Realtime.instance.connected) {
        await _notifyNewOrder();
      }
      _lastNewOrders = newOrders;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _notifyNewOrder() async {
    try {
      final list =
          (await Api.instance.get('/api/seller/notifications')) as List;
      final n = list
          .cast<Map<String, dynamic>>()
          .where((x) => x['type'] == 'order')
          .firstOrNull;
      if (n == null || n['id'] == _lastNotifId) return;
      _lastNotifId = n['id'];
      await Notify.instance
          .show(n['title'] ?? 'Yangi buyurtma', n['text'] ?? '');
    } catch (_) {
      await Notify.instance
          .show('Yangi buyurtma', "Do'koningizga yangi buyurtma tushdi");
    }
  }
}
