import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Xaridorning o'z buyurtmalari
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});
  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  static List<Order> _parse(dynamic r) =>
      (r as List).map((e) => Order.fromJson(e)).toList();
  Future<List<Order>> load() async =>
      _parse(await Api.instance.get('/api/my-orders'));
  late Future<List<Order>> future = load();
  // Kesh: darhol ko'rsatiladi, fonda yangilanadi
  List<Order>? get cachedOrders {
    final c = Api.instance.cached('/api/my-orders');
    return c == null ? null : _parse(c);
  }

  // Buyurtma holati o'zgarsa (do'kon qabul qildi, kuryer yo'lda, yetkazildi) ro'yxat joyida yangilanadi
  int _seenLive = AppState.instance.liveVersion;

  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onLive);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onLive);
    super.dispose();
  }

  void _onLive() {
    final st = AppState.instance;
    if (st.liveVersion == _seenLive) return;
    _seenLive = st.liveVersion;
    final type = st.lastEvent?.type ?? '';
    if ((type.startsWith('order:') || type.startsWith('cargo:')) && mounted) {
      setState(() => future = load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Buyurtmalarim'))),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => future = load()),
        child: FutureBuilder(
          future: future,
          initialData: cachedOrders,
          builder: (_, snap) {
            if (!snap.hasData) {
              return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2.5));
            }
            final orders = snap.data!;
            if (orders.isEmpty) {
              return EmptyBox(
                  Icons.receipt_long_outlined, tr("Hozircha buyurtma yo'q"));
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, navPad),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final o = orders[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: softShadow(context),
                      border:
                          context.isDark ? Border.all(color: p.border) : null),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          StatusBadge(o.status, o.statusLabel),
                          const Spacer(),
                          Text(fmtTime(o.createdAt),
                              style: TextStyle(
                                  color: p.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600))
                        ]),
                        const SizedBox(height: 8),
                        Text(o.productName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 2),
                        Row(children: [
                          Text(o.shopName,
                              style: TextStyle(
                                  color: p.muted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          Text('  ·  ', style: TextStyle(color: p.muted)),
                          PriceText(o.price, size: 13)
                        ]),
                        if (o.shopPhone.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 40),
                                    backgroundColor: p.bg,
                                    side: BorderSide.none),
                                icon: Icon(Icons.phone_outlined,
                                    size: 16, color: p.success),
                                label: Text(tr("Do'konga qo'ng'iroq")),
                                onPressed: () =>
                                    launchUrl(Uri.parse('tel:${o.shopPhone}'))),
                          ),
                      ]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
