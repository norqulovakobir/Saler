import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../anim.dart';
import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shops_screen.dart';

/// "Sizga yaqin" bo'limi.
///
/// Joylashuvga ruxsat berilgan bo'lsa — yaqin-atrofdagi eng yaxshi do'kon va
/// mahsulotlar ko'rsatiladi. Ruxsat berilmagan bo'lsa — bitta taklif kartochkasi
/// turadi; foydalanuvchi o'zi bosmaguncha ruxsat so'ralmaydi.
///
/// Saralash serverda (`/api/nearby`): masofa sifat bilan birga hisoblanadi,
/// shuning uchun yonginangizdagi bo'sh do'kon ro'yxatni egallab olmaydi.
class NearbySection extends StatefulWidget {
  const NearbySection({super.key});
  @override
  State<NearbySection> createState() => _NearbySectionState();
}

class _NearbyData {
  final List<Shop> shops;
  final List<Product> products;
  final Map<String, double> distance; // id -> km
  const _NearbyData(this.shops, this.products, this.distance);
  bool get isEmpty => shops.isEmpty && products.isEmpty;
}

enum _Stage { checking, needPermission, loading, ready, failed }

class _NearbySectionState extends State<NearbySection> {
  _Stage stage = _Stage.checking;
  _NearbyData? data;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Ilova ochilganda ruxsat so'ralmaydi — faqat avval berilgani tekshiriladi
  Future<void> _start() async {
    final granted = await _hasPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => stage = _Stage.needPermission);
      return;
    }
    await _load();
  }

  Future<bool> _hasPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Foydalanuvchi tugmani bosganda ruxsat so'raladi
  Future<void> _ask() async {
    setState(() => stage = _Stage.loading);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}
    if (!mounted) return;
    if (!await _hasPermission()) {
      if (mounted) setState(() => stage = _Stage.needPermission);
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => stage = _Stage.loading);
    try {
      // Tez javob uchun avval oxirgi ma'lum joy, u yo'q bo'lsa aniqlanadi
      Position? pos = kIsWeb ? null : await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));
      final raw = await Api.instance.get('/api/nearby?lat=${pos.latitude}&lon=${pos.longitude}');
      final shops = <Shop>[];
      final products = <Product>[];
      final distance = <String, double>{};
      for (final item in (raw['shops'] as List? ?? const [])) {
        final map = Map<String, dynamic>.from(item as Map);
        final shop = Shop.fromJson(map);
        shops.add(shop);
        distance[shop.id] = (map['distanceKm'] as num?)?.toDouble() ?? 0;
      }
      for (final item in (raw['products'] as List? ?? const [])) {
        final map = Map<String, dynamic>.from(item as Map);
        final product = Product.fromJson(map);
        products.add(product);
        distance[product.id] = (map['distanceKm'] as num?)?.toDouble() ?? 0;
      }
      if (!mounted) return;
      setState(() {
        data = _NearbyData(shops, products, distance);
        stage = _Stage.ready;
      });
    } catch (_) {
      if (mounted) setState(() => stage = _Stage.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (stage) {
      case _Stage.checking:
        return const SizedBox.shrink();
      case _Stage.needPermission:
        return AppearIn(child: _AskCard(onTap: _ask));
      case _Stage.loading:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(child: RydexLoader(size: 64, showLogo: false, color: context.p.accent)),
        );
      case _Stage.failed:
        return const SizedBox.shrink();
      case _Stage.ready:
        final d = data;
        if (d == null || d.isEmpty) return _EmptyNearby(onRetry: _load);
        return _NearbyList(data: d);
    }
  }
}

/// Ruxsat so'rash kartochkasi — bosilmaguncha hech narsa so'ralmaydi
class _AskCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AskCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.accentSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.accent.withValues(alpha: .45)),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.near_me_rounded, color: p.onAccent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Yoningizdagi do\'konlar'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -.3)),
              const SizedBox(height: 2),
              Text(tr('Joylashuvga ruxsat bersangiz, eng yaqin va eng yaxshi takliflarni ko\'rsatamiz'),
                  style: TextStyle(fontSize: 12.5, color: p.accentText, fontWeight: FontWeight.w600, height: 1.3)),
            ]),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
            child: Text(tr('Ruxsat')),
          ),
        ]),
      ),
    );
  }
}

class _EmptyNearby extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyNearby({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.border)),
        child: Row(children: [
          Icon(Icons.explore_off_outlined, color: p.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(tr("Atrofingizda hali do'kon yo'q — pastdagi ro'yxatdan tanlang"),
                style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600)),
          ),
          IconButton(onPressed: onRetry, icon: Icon(Icons.refresh_rounded, size: 20, color: p.muted)),
        ]),
      ),
    );
  }
}

/// Topilgan natijalar: avval mahsulotlar (gorizontal), keyin do'konlar
class _NearbyList extends StatelessWidget {
  final _NearbyData data;
  const _NearbyList({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(tr('Sizga yaqin')),
      if (data.products.isNotEmpty)
        SizedBox(
          // Kartochka balandligi: 10 (padding) + 130 (kvadrat rasm: 150-20)
          // + 10 + 17.5 (nom) + 6 + 30 (narx/tugma qatori) + 10 = ~214.
          // Avvalgi 208 shu sabab 5px ga toshib ketardi.
          height: 216,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: data.products.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final product = data.products[i];
              return SizedBox(
                width: 150,
                child: _DistanceBadge(
                  km: data.distance[product.id],
                  child: ProductCard(product, onTap: () => openProduct(context, product, null)),
                ),
              );
            },
          ),
        ),
      if (data.shops.isNotEmpty) ...[
        const SizedBox(height: 14),
        SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: data.shops.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _NearShopTile(shop: data.shops[i], km: data.distance[data.shops[i].id]),
          ),
        ),
      ],
      const SizedBox(height: 4),
    ]);
  }
}

/// Kartochka burchagidagi masofa belgisi
class _DistanceBadge extends StatelessWidget {
  final Widget child;
  final double? km;
  const _DistanceBadge({required this.child, this.km});

  @override
  Widget build(BuildContext context) {
    if (km == null) return child;
    final p = context.p;
    return Stack(children: [
      child,
      Positioned(
        left: 8,
        top: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: p.dark.withValues(alpha: .82), borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.near_me_rounded, size: 11, color: p.onDark),
            const SizedBox(width: 4),
            Text(fmtKm(km!), style: TextStyle(color: p.onDark, fontSize: 11, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    ]);
  }
}

class _NearShopTile extends StatelessWidget {
  final Shop shop;
  final double? km;
  const _NearShopTile({required this.shop, this.km});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(shop.id))),
        child: Container(
          width: 210,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: softShadow(context, y: 5, blur: 16, a: .04)),
          child: Row(children: [
            ShopAvatar(shop, size: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shop.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: -.2)),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(Icons.near_me_rounded, size: 12, color: p.accentText),
                  const SizedBox(width: 4),
                  Text(fmtKm(km ?? shop.distanceKm ?? 0),
                      style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Icon(Icons.inventory_2_outlined, size: 12, color: p.muted),
                  const SizedBox(width: 3),
                  Text('${shop.productCount}', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 0.4 km, 2.3 km, 12 km — masofani qisqa ko'rsatadi
String fmtKm(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  if (km < 10) return '${km.toStringAsFixed(1)} km';
  return '${km.round()} km';
}
