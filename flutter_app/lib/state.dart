import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'models.dart';
import 'notify.dart';

class CartItem {
  final Product product;
  int qty;
  CartItem(this.product, this.qty);
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

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[p.getInt('theme') ?? 0];
    L10n.lang = AppLang.values[(p.getInt('lang') ?? 0).clamp(0, AppLang.values.length - 1)];
    for (final s in p.getStringList('favs') ?? const []) {
      final pr = Product.fromJson(jsonDecode(s));
      favs[pr.id] = pr;
    }
    for (final s in p.getStringList('cart') ?? const []) {
      final j = jsonDecode(s);
      cart.add(CartItem(Product.fromJson(j['p']), j['q']));
    }
    try {
      final me = await Api.instance.get('/api/me');
      if (me['shop'] != null) sellerShop = Shop.fromJson(me['shop']);
      if (me['courier'] != null) courier = Courier.fromJson(me['courier']);
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

  Future<void> _saveFavs() async => (await SharedPreferences.getInstance()).setStringList('favs', favs.values.map((p) => jsonEncode(p.toJson())).toList());
  Future<void> _saveCart() async => (await SharedPreferences.getInstance()).setStringList('cart', cart.map((c) => jsonEncode({'p': c.product.toJson(), 'q': c.qty})).toList());

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
      if (_lastNewOrders != null && newOrders > _lastNewOrders!) await _notifyNewOrder();
      _lastNewOrders = newOrders;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _notifyNewOrder() async {
    try {
      final list = (await Api.instance.get('/api/seller/notifications')) as List;
      final n = list.cast<Map<String, dynamic>>().where((x) => x['type'] == 'order').firstOrNull;
      if (n == null || n['id'] == _lastNotifId) return;
      _lastNotifId = n['id'];
      await Notify.instance.show(n['title'] ?? 'Yangi buyurtma', n['text'] ?? '');
    } catch (_) {
      await Notify.instance.show('Yangi buyurtma', "Do'koningizga yangi buyurtma tushdi");
    }
  }
}
