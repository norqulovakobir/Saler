import 'package:flutter/material.dart';

import 'anim.dart';
import 'api.dart';
import 'l10n.dart';
import 'models.dart';
import 'screens/shops_screen.dart';
import 'state.dart';
import 'theme.dart';

/// Ulashilgan havola bilan kirish.
///
/// Havola `https://.../p/<mahsulot>` yoki `https://.../s/<do'kon>` ko'rinishida
/// bo'ladi. Web versiyada bu manzil to'g'ridan to'g'ri ochiladi: ilova
/// tanishtiruv va rol tanlashni o'tkazib yuborib, darhol kerakli sahifani
/// ko'rsatadi — odam havolani bosganida nima ulashilganini ko'rishi shart.
/// U yerdan savatga qo'shish va buyurtma berish odatdagidek ishlaydi.
class DeepLink {
  /// Turi: `p` (mahsulot) yoki `s` (do'kon)
  final String kind;
  final String id;
  const DeepLink(this.kind, this.id);

  bool get isProduct => kind == 'p';

  /// Ochilish manzilidan olingan havola. Ilova ishga tushganda bir marta
  /// o'qiladi, sahifa yopilgandan keyin `null` ga tushiriladi.
  static DeepLink? pending = parse(Uri.base);

  /// `/p/<id>`, `/s/<id>` yoki `?p=<id>` ko'rinishlarini tushunadi
  static DeepLink? parse(Uri uri) {
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.length >= 2 && (seg[0] == 'p' || seg[0] == 's') && seg[1].isNotEmpty) {
      return DeepLink(seg[0], Uri.decodeComponent(seg[1]));
    }
    for (final k in ['p', 's']) {
      final v = uri.queryParameters[k];
      if (v != null && v.isNotEmpty) return DeepLink(k, v);
    }
    return null;
  }
}

/// Havola bo'yicha ochilgan sahifa: ma'lumot yuklanguncha brend ekrani,
/// keyin mahsulot yoki do'kon sahifasi.
class SharedEntry extends StatefulWidget {
  final DeepLink link;

  /// Sahifa yopilganda ilovaning odatdagi oqimiga qaytish
  final VoidCallback onClose;
  const SharedEntry({super.key, required this.link, required this.onClose});

  @override
  State<SharedEntry> createState() => _SharedEntryState();
}

class _SharedEntryState extends State<SharedEntry> {
  late final Future<Widget> _page = _load();

  Future<Widget> _load() async {
    // Havola bilan kirgan odam ham xaridor sifatida ishlashi kerak:
    // tanishtiruv va rol tanlash qayta so'ralmaydi.
    await AppState.instance.setOnboarded();
    await AppState.instance.setRolePicked();
    if (widget.link.isProduct) {
      final data = await Api.instance.get('/api/products/${Uri.encodeComponent(widget.link.id)}');
      final product = Product.fromJson(Map<String, dynamic>.from(data['product'] as Map));
      final shop = data['shop'] is Map ? Shop.fromJson(Map<String, dynamic>.from(data['shop'] as Map)) : null;
      return ProductScreen(product, shop);
    }
    return ShopScreen(widget.link.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _page,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: brandBg(context),
            body: Center(child: RydexLoader(size: 132, color: context.p.accent)),
          );
        }
        if (snap.hasError) return _NotFound(onClose: widget.onClose, product: widget.link.isProduct);
        // Sahifa yopilganda (orqaga) ilovaning bosh ekraniga o'tiladi
        return _PopToApp(onClose: widget.onClose, child: snap.data!);
      },
    );
  }
}

/// Ulashilgan sahifadan orqaga bosilganda ilova ichiga kiradi, brauzerdan chiqmaydi
class _PopToApp extends StatelessWidget {
  final Widget child;
  final VoidCallback onClose;
  const _PopToApp({required this.child, required this.onClose});

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onClose();
        },
        child: child,
      );
}

class _NotFound extends StatelessWidget {
  final VoidCallback onClose;
  final bool product;
  const _NotFound({required this.onClose, required this.product});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      backgroundColor: brandBg(context),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.link_off_rounded, size: 54, color: p.muted),
            const SizedBox(height: 14),
            Text(product ? tr('Mahsulot topilmadi') : tr("Do'kon topilmadi"),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: brandFg(context))),
            const SizedBox(height: 6),
            Text(tr("Havola eskirgan yoki mahsulot o'chirilgan bo'lishi mumkin"),
                textAlign: TextAlign.center,
                style: TextStyle(color: brandFgSoft(context, .55), fontWeight: FontWeight.w600)),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onClose,
              icon: const Icon(Icons.storefront_rounded, size: 18),
              label: Text(tr("Do'konlarni ko'rish")),
            ),
          ]),
        ),
      ),
    );
  }
}
