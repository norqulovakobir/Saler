import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api.dart';
import '../../categories.dart';
import '../../l10n.dart';
import '../../main.dart';
import '../../models.dart';
import '../../state.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../shops_screen.dart';
import 'analytics_tab.dart';

/// Sotuvchi paneli
class SellerHome extends StatefulWidget {
  final VoidCallback onExit;
  const SellerHome({super.key, required this.onExit});
  @override
  State<SellerHome> createState() => _SellerHomeState();
}

class _SellerHomeState extends State<SellerHome> {
  int index = 0;
  final keys = List.generate(5, (_) => GlobalKey<NavigatorState>());
  final pager = PageController();

  @override
  void initState() {
    super.initState();
    AppState.instance.refreshBadges();
  }

  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  /// Bo'limni almashtirish: tugma bosilganda yoki yonga surilganda
  void _go(int i) {
    if (i == index) {
      keys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    final from = index;
    setState(() => index = i);
    if (!pager.hasClients) return;
    if ((i - from).abs() <= 1) {
      pager.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    } else {
      pager.jumpToPage(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.instance;
    final p = context.p;
    final roots = [
      // "Yangi buyurtmalarni ko'rish" ikkinchi sahifa ochmaydi — shu yerda Buyurtmalar tabiga o'tadi
      AnalyticsTab(onExit: widget.onExit, onOpenOrders: () => _go(1)),
      OrdersTab(onExit: widget.onExit),
      AdviceTab(onExit: widget.onExit),
      ProductsTab(onExit: widget.onExit),
      ProfileTab(onExit: widget.onExit),
    ];
    final pages = [for (var i = 0; i < roots.length; i++) TabNavigator(key: ValueKey('s$i${L10n.lang.name}'), navKey: keys[i], root: roots[i])];
    return ListenableBuilder(
      listenable: st,
      builder: (_, __) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final nav = keys[index].currentState;
          if (nav != null && nav.canPop()) nav.pop();
        },
        child: Scaffold(
          extendBody: true,
          body: Stack(fit: StackFit.expand, children: [
            PageView(
              controller: pager,
              onPageChanged: (i) {
                if (i != index) setState(() => index = i);
              },
              children: [for (final page in pages) KeepAlivePage(child: page)],
            ),
            // Status bar shaffof: aylantirilgan kontent soat/batareya ostida ko'rinmasin — tepada fon rangli parda
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).padding.top,
              child: IgnorePointer(child: ColoredBox(color: p.bg.withValues(alpha: .96))),
            ),
          ]),
          bottomNavigationBar: FloatingNav(
            index: index,
            badges: {1: st.newOrders},
            onTap: _go,
            items: [
              NavItem(Icons.bar_chart_rounded, Icons.bar_chart_rounded, tr('Analitika')),
              NavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, tr('Buyurtma')),
              NavItem(Icons.auto_awesome_outlined, Icons.auto_awesome, tr('AI tavsiya')),
              NavItem(Icons.inventory_2_outlined, Icons.inventory_2_rounded, tr('Mahsulot')),
              NavItem(Icons.person_outline_rounded, Icons.person_rounded, tr('Profil')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sotuvchi sahifalari sarlavhasi: nom + qo'ng'iroqcha + xaridor rejimi
class SellerHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onExit;
  const SellerHeader(this.title, {super.key, this.subtitle, this.onExit});
  @override
  Widget build(BuildContext context) {
    final st = AppState.instance;
    final s = st.sellerShop!;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 0),
      child: Row(children: [
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(subtitle ?? '${s.name} · sotuvchi', style: TextStyle(fontSize: 13, color: context.p.muted, fontWeight: FontWeight.w600)),
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.5)),
        ])),
        const ThemeBtn(),
        const SizedBox(width: 8),
        ListenableBuilder(listenable: st, builder: (_, __) => IconBtn(Icons.notifications_none_rounded, badge: st.unread, onTap: () => openNotifications(context))),
        const SizedBox(width: 8),
        if (onExit != null) IconBtn(Icons.storefront_outlined, onTap: onExit) else ShopAvatar(s, size: 42),
      ]),
    );
  }
}

/// Xato matnini foydalanuvchiga ko'rsatish uchun tozalaydi: server xabari, "Exception: " prefiksisiz yoki tarmoq xatosi
String sellerErrorText(Object e) {
  if (e is ApiException) return e.message;
  final s = e.toString();
  if (s.startsWith('Exception: ')) return s.substring('Exception: '.length);
  if (s.contains('SocketException') || s.contains('ClientException') || s.contains('TimeoutException') || s.contains('HandshakeException')) {
    return tr("Serverga ulanib bo'lmadi. Internetni tekshiring.");
  }
  return s;
}

// ---- Buyurtmalar ----
class OrdersTab extends StatefulWidget {
  final VoidCallback? onExit;
  const OrdersTab({super.key, this.onExit});
  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  String filter = 'new';
  List<Order> orders = [];
  bool loading = true;
  String? error;
  String? busyId; // holati o'zgartirilayotgan buyurtma — tugmalari vaqtincha o'chadi
  int _lastNew = AppState.instance.newOrders;

  @override
  void initState() {
    super.initState();
    final cached = Api.instance.cached('/api/seller/orders');
    if (cached is List) {
      orders = cached.map((e) => Order.fromJson(e)).toList();
      loading = false;
    }
    AppState.instance.addListener(_onAppState);
    load();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onAppState);
    super.dispose();
  }

  // Yangi buyurtmalar soni oshsa yoki jonli hodisa kelsa (buyurtma, kuryer holati, pul) ro'yxat joyida yangilanadi
  int _seenLive = AppState.instance.liveVersion;
  void _onAppState() {
    final st = AppState.instance;
    final n = st.newOrders;
    var reload = n > _lastNew;
    _lastNew = n;
    if (st.liveVersion != _seenLive) {
      _seenLive = st.liveVersion;
      final t = st.lastEvent?.type ?? '';
      if (t.startsWith('order:') || t == 'money') reload = true;
    }
    if (reload) load();
  }

  Future<void> load() async {
    try {
      final r = await Api.instance.get('/api/seller/orders');
      if (!mounted) return;
      setState(() {
        orders = (r as List).map((e) => Order.fromJson(e)).toList();
        error = null;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = sellerErrorText(e);
        loading = false;
      });
    }
  }

  void retry() {
    setState(() {
      loading = true;
      error = null;
    });
    load();
  }

  Future<void> setStatus(Order o, String status) async {
    if (busyId != null) return;
    // Bekor qilishdan oldin tasdiqlash (server kuryer biriktiruvini ham olib tashlaydi)
    if (status == 'cancelled' &&
        !await confirmDialog(context, tr('Buyurtmani bekor qilasizmi?'), text: tr("Kuryer biriktirilgan bo'lsa, u ham bekor qilinadi."), ok: tr('Ha, bekor qilish'), danger: true)) {
      return;
    }
    if (!mounted) return;
    setState(() => busyId = o.id);
    try {
      await Api.instance.patch('/api/seller/orders/${o.id}', {'status': status});
      await load();
      AppState.instance.refreshBadges();
    } catch (e) {
      if (mounted) showToast(context, sellerErrorText(e), error: true);
      // 409: buyurtma holati allaqachon o'zgargan — ro'yxatni yangilaymiz
      if (e is ApiException && e.status == 409) await load();
    }
    if (mounted) setState(() => busyId = null);
  }

  Future<void> _open(Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
    try {
      final ok = await launchUrl(uri, mode: mode);
      if (!ok && mounted) showToast(context, tr("Ochib bo'lmadi"), error: true);
    } catch (_) {
      if (mounted) showToast(context, tr("Ochib bo'lmadi"), error: true);
    }
  }

  /// Yetkazish holati chipi: (matn, rang, ikonka) yoki null
  (String, Color, IconData)? _delivery(Order o) {
    final p = context.p;
    return switch (o.deliveryStatus) {
      'assigned' => (tr('Kuryer biriktirildi'), const Color(0xFF7C5CFF), Icons.assignment_ind_outlined),
      'picked' => (tr("Kuryer yo'lda"), const Color(0xFF3B6BFF), Icons.two_wheeler_rounded),
      'delivered' => (tr('Yetkazildi'), p.success, Icons.check_circle_outline_rounded),
      null when o.status == 'new' => (tr('Kuryer qidirilmoqda'), p.accentText, Icons.search_rounded),
      _ => null,
    };
  }

  Widget _chip(String text, Color c, IconData ic) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, size: 13, color: c),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11)),
        ]),
      );

  Widget _pill(IconData ic, String text, VoidCallback onTap) {
    final p = context.p;
    return Material(
      color: p.bg,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ic, size: 14, color: p.accentText),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.accentText)),
          ]),
        ),
      ),
    );
  }

  Widget _orderCard(Order o) {
    final p = context.p;
    final dl = _delivery(o);
    final busy = busyId == o.id;
    final extra = [
      if (o.deliveryFee != null && o.deliveryFee! > 0) "${tr('Yetkazish')}: ${fmtPrice(o.deliveryFee!)} so'm",
      if (o.routeKm != null && o.routeKm! > 0) '${o.routeKm!.toStringAsFixed(1)} km',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [StatusBadge(o.status, tr(o.statusLabel)), const Spacer(), Text(fmtTime(o.createdAt), style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600))]),
        const SizedBox(height: 10),
        if (o.items.length > 1 || (o.items.isNotEmpty && o.items.first.qty > 1)) ...[
          for (final i in o.items) Text('${i.name} × ${i.qty}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          PriceText(o.price, size: 15),
        ] else
          Row(children: [Expanded(child: Text(o.productName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))), PriceText(o.price, size: 14)]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.person_outline_rounded, size: 16, color: p.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(o.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        if (o.phone.isNotEmpty) ...[
          const SizedBox(height: 4),
          InkWell(
              onTap: () => _open(Uri.parse('tel:${o.phone}')),
              child: Row(children: [
                Icon(Icons.phone_outlined, size: 16, color: p.success),
                const SizedBox(width: 6),
                Text(o.phone, style: TextStyle(color: p.accentText, fontWeight: FontWeight.w700))
              ])),
        ],
        // Xaridor manzili va xaritada ochish
        if (o.address.isNotEmpty || o.hasLocation) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.location_on_outlined, size: 16, color: p.muted),
            const SizedBox(width: 6),
            Expanded(
                child: Text(o.address.isNotEmpty ? o.address : tr('Joylashuv yuborilgan'),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.text.withValues(alpha: .85), height: 1.3))),
            if (o.hasLocation) ...[
              const SizedBox(width: 8),
              _pill(Icons.map_outlined, tr('Xarita'),
                  () => _open(Uri.parse('https://www.google.com/maps/search/?api=1&query=${o.lat},${o.lon}'), mode: LaunchMode.externalApplication)),
            ],
          ]),
        ],
        // Yetkazish: holat, kuryer, narx va masofa
        if (dl != null || o.courierName.isNotEmpty || extra.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (dl != null || extra.isNotEmpty)
                Row(children: [
                  if (dl != null) _chip(dl.$1, dl.$2, dl.$3),
                  if (dl != null && extra.isNotEmpty) const SizedBox(width: 8),
                  if (extra.isNotEmpty)
                    Expanded(
                        child: Text(extra,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: dl != null ? TextAlign.end : TextAlign.start,
                            style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600))),
                ]),
              if (o.courierName.isNotEmpty) ...[
                if (dl != null || extra.isNotEmpty) const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.two_wheeler_rounded, size: 16, color: p.muted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(o.courierName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  if (o.courierPhone.isNotEmpty) IconBtn(Icons.phone_outlined, size: 34, bg: p.successSoft, color: p.success, onTap: () => _open(Uri.parse('tel:${o.courierPhone}'))),
                ]),
              ],
            ]),
          ),
        if (o.status == 'new')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              Expanded(
                  child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                          backgroundColor: p.successSoft,
                          foregroundColor: p.success,
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: Text(tr('Bajarildi')),
                      onPressed: busy ? null : () => setStatus(o, 'done'))),
              const SizedBox(width: 8),
              Expanded(
                  child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                          backgroundColor: p.danger.withValues(alpha: .12),
                          foregroundColor: p.danger,
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: Text(tr('Bekor')),
                      onPressed: busy ? null : () => setStatus(o, 'cancelled'))),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final list = filter == 'all' ? orders : orders.where((o) => o.status == filter).toList();
    int count(String k) => k == 'all' ? orders.length : orders.where((o) => o.status == k).length;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: EdgeInsets.zero, physics: const AlwaysScrollableScrollPhysics(), children: [
          SellerHeader(tr('Buyurtmalar'), onExit: widget.onExit),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, navPad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ChoiceChips(
                  items: [
                    ('new', '${tr('Yangi')} · ${count('new')}'),
                    ('all', '${tr('Hammasi')} · ${count('all')}'),
                    ('done', '${tr('Bajarilgan')} · ${count('done')}'),
                    ('cancelled', '${tr('Bekor')} · ${count('cancelled')}'),
                  ],
                  value: filter,
                  onChanged: (v) => setState(() => filter = v)),
              const SizedBox(height: 12),
              if (loading)
                const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator(strokeWidth: 2.5)))
              else if (error != null && orders.isEmpty)
                EmptyBox(Icons.cloud_off_rounded, error!, action: FilledButton.icon(onPressed: retry, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(tr('Qayta urinish'))))
              else ...[
                // Eski ro'yxat bor, lekin yangilab bo'lmadi — ixcham ogohlantirish
                if (error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    decoration: BoxDecoration(color: p.danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Icon(Icons.cloud_off_rounded, size: 16, color: p.danger),
                      const SizedBox(width: 8),
                      Expanded(child: Text(error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.danger, fontWeight: FontWeight.w600))),
                      TextButton(onPressed: load, child: Text(tr('Qayta urinish'), style: const TextStyle(fontSize: 12))),
                    ]),
                  ),
                if (list.isEmpty) EmptyBox(Icons.receipt_long_outlined, tr("Buyurtma yo'q")) else for (final o in list) _orderCard(o),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---- AI tavsiyalar ----
class AdviceTab extends StatefulWidget {
  final VoidCallback? onExit;
  const AdviceTab({super.key, this.onExit});
  @override
  State<AdviceTab> createState() => _AdviceTabState();
}

class _AdviceTabState extends State<AdviceTab> {
  static const _path = '/api/seller/advice';
  dynamic data = Api.instance.cached(_path);
  String? error;
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    _fetch(false);
  }

  /// refresh=true — AI qayta tahlil qiladi (?refresh=1), tugmada indikator aylanadi
  Future<void> _fetch(bool refresh) async {
    try {
      final r = await Api.instance.get(refresh ? '$_path?refresh=1' : _path);
      if (!mounted) return;
      setState(() {
        data = r;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = sellerErrorText(e));
      // Eski tavsiyalar ekranda qoladi — faqat xabar
      if (refresh && data != null) showToast(context, error!, error: true);
    }
    if (mounted && refreshing) setState(() => refreshing = false);
  }

  void reanalyze() {
    if (refreshing) return;
    setState(() => refreshing = true);
    _fetch(true);
  }

  void retry() {
    setState(() => error = null);
    _fetch(false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final raw = data;
    final tipsRaw = raw is Map ? raw['tips'] : null;
    final tips = (tipsRaw is List ? tipsRaw : const []).map((e) => Tip.fromJson(e)).toList();
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        SellerHeader(tr('AI tavsiyalar'), onExit: widget.onExit),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, navPad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DarkBanner(
              glow: const Color(0xFF7C5CFF),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFC9D3FF)),
                  const SizedBox(width: 6),
                  Text(tr('AI MASLAHATCHI'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: Color(0xFFC9D3FF)))
                ]),
                const SizedBox(height: 8),
                Text(tr("Do'koningiz ma'lumotlarini tahlil qilib, sotuvni oshirish bo'yicha tavsiyalar beradi"),
                    style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 14, height: 1.4, fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 12),
            if (raw == null && error != null)
              EmptyBox(Icons.cloud_off_rounded, error!, action: FilledButton.icon(onPressed: retry, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(tr('Qayta urinish'))))
            else if (raw == null)
              const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))
            else ...[
              for (final t in tips)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                          color: switch (t.type) { 'warning' => const Color(0xFFFFF1E0), 'success' => p.successSoft, _ => const Color(0xFFEFEAFF) }, borderRadius: BorderRadius.circular(12)),
                      child: Icon(switch (t.type) { 'warning' => Icons.warning_amber_rounded, 'success' => Icons.check_circle_outline_rounded, _ => Icons.lightbulb_outline_rounded },
                          size: 20, color: switch (t.type) { 'warning' => const Color(0xFFA86F00), 'success' => p.success, _ => const Color(0xFF7C5CFF) }),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 3),
                      Text(t.text, style: TextStyle(fontSize: 13, color: p.text.withValues(alpha: .8), height: 1.45))
                    ])),
                  ]),
                ),
              OutlinedButton.icon(
                  icon: refreshing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(refreshing ? tr('Tahlil qilinmoqda...') : tr('Qayta tahlil qilish')),
                  onPressed: refreshing ? null : reanalyze),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ---- Mahsulotlar ----
class ProductsTab extends StatefulWidget {
  final VoidCallback? onExit;
  const ProductsTab({super.key, this.onExit});
  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  List<Product> products = [];
  bool loading = true;
  String q = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final cached = Api.instance.cached('/api/seller/products');
    if (cached != null) {
      products = (cached as List).map((e) => Product.fromJson(e)).toList();
      loading = false;
      if (mounted) setState(() {});
    }
    try {
      products = ((await Api.instance.get('/api/seller/products')) as List).map((e) => Product.fromJson(e)).toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final list = q.isEmpty ? products : products.where((x) => x.name.toLowerCase().contains(q.toLowerCase())).toList();
    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: FloatingActionButton.extended(
            backgroundColor: p.dark,
            foregroundColor: p.onDark,
            icon: const Icon(Icons.add_rounded),
            label: Text(tr("Mahsulot qo'shish"), style: const TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () => openProductForm(context, null, load)),
      ),
      body: ListView(padding: EdgeInsets.zero, children: [
        SellerHeader(tr('Mahsulotlar'), onExit: widget.onExit),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, navPad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SearchField(hint: tr('Qidirish...'), onChanged: (v) => setState(() => q = v)),
            const SizedBox(height: 12),
            if (loading)
              const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator(strokeWidth: 2.5)))
            else if (list.isEmpty)
              EmptyBox(Icons.inventory_2_outlined, tr("Hozircha mahsulot yo'q"))
            else
              for (final x in list)
                Opacity(
                  opacity: x.active ? 1 : .55,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
                    child: Row(children: [
                      ProductImage(x, size: 56, radius: 12),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Row(children: [
                          PriceText(x.price, size: 13),
                          // Tor ekranda ko'rishlar matni qisqaradi, qator toshib ketmaydi
                          Flexible(
                              child: Text("  ·  ${x.views} ${tr("ko'rish")}${x.active ? '' : '  ·  ${tr('yashirin')}'}",
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600))),
                        ]),
                      ])),
                      IconBtn(x.active ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 36, bg: p.bg, onTap: () async {
                        try {
                          await Api.instance.put('/api/seller/products/${x.id}', {'active': !x.active});
                          await load();
                        } catch (e) {
                          if (context.mounted) showToast(context, sellerErrorText(e), error: true);
                        }
                      }),
                      const SizedBox(width: 6),
                      IconBtn(Icons.edit_outlined, size: 36, bg: p.bg, onTap: () => openProductForm(context, x, load)),
                      const SizedBox(width: 6),
                      IconBtn(Icons.delete_outline_rounded, size: 36, bg: p.danger.withValues(alpha: .1), color: p.danger, onTap: () async {
                        if (!await confirmDialog(context, '"${x.name}" o\'chirilsinmi?', text: "Bu amalni qaytarib bo'lmaydi.", ok: "O'chirish", danger: true)) return;
                        try {
                          await Api.instance.delete('/api/seller/products/${x.id}');
                          await load();
                        } catch (e) {
                          if (context.mounted) showToast(context, sellerErrorText(e), error: true);
                        }
                      }),
                    ]),
                  ),
                ),
          ]),
        ),
      ]),
    );
  }
}

/// Mahsulot qo'shish / tahrirlash (rasm, narx va kategoriya majburiy)
void openProductForm(BuildContext context, Product? p, VoidCallback onSaved) {
  final name = TextEditingController(text: p?.name ?? '');
  final price = TextEditingController(text: p == null ? '' : '${p.price}');
  final desc = TextEditingController(text: p?.description ?? '');
  final photos = <String>[...?p?.photos];
  String? category = p?.category;
  String? rejection;
  bool busy = false;
  showModalBottomSheet(
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setSt) {
        final pal = c.p;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 24),
          child: ListView(shrinkWrap: true, children: [
            Text(p == null ? tr('Yangi mahsulot') : tr('Tahrirlash'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
            if (rejection != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: pal.danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.danger.withValues(alpha: .3))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline_rounded, color: pal.danger),
                  const SizedBox(width: 10),
                  // Server rad etgan sabab (matn serverdan keladi)
                  Expanded(child: Text(rejection ?? '', style: const TextStyle(fontWeight: FontWeight.w600)))
                ]),
              ),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: InputDecoration(labelText: tr('Nomi'))),
            const SizedBox(height: 10),
            TextField(controller: price, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr("Narxi (so'm)"))),
            const SizedBox(height: 10),
            TextField(controller: desc, maxLines: 3, decoration: InputDecoration(labelText: tr('Tavsif'))),
            const SizedBox(height: 14),
            Row(children: [
              Text('${tr('Kategoriya')} *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: pal.muted)),
              const Spacer(),
              if (category != null) Text(categoryOf(category)?.name ?? '', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: pal.accentText)),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final cat = categories[i];
                  final sel = category == cat.slug;
                  return GestureDetector(
                    onTap: () => setSt(() => category = cat.slug),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 88,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: sel ? pal.accent : Colors.transparent, width: 3), boxShadow: sel ? [BoxShadow(color: pal.accent.withValues(alpha: .35), blurRadius: 12)] : null),
                      clipBehavior: Clip.antiAlias,
                      child: Opacity(opacity: category == null || sel ? 1 : .55, child: Image.asset(cat.asset, fit: BoxFit.cover)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Text('Rasmlar (majburiy, 10 tagacha)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: pal.muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < photos.length; i++)
                Stack(children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: photos[i].startsWith('data:')
                          ? Image.memory(base64Decode(photos[i].split(',')[1]), width: 72, height: 72, fit: BoxFit.cover)
                          : Image.network(Api.instance.photoUrl(photos[i]), width: 72, height: 72, fit: BoxFit.cover)),
                  Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                          onTap: () => setSt(() => photos.removeAt(i)),
                          child: const CircleAvatar(radius: 10, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 12, color: Colors.white)))),
                ]),
              if (photos.length < 10)
                InkWell(
                  onTap: () async {
                    final src = await askImageSource(c);
                    if (src == null) return;
                    try {
                      final List<XFile> files;
                      if (src == ImageSource.camera) {
                        final f = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1280, imageQuality: 85);
                        files = f == null ? [] : [f];
                      } else {
                        files = await ImagePicker().pickMultiImage(maxWidth: 1280, imageQuality: 85);
                      }
                      for (final f in files.take(10 - photos.length)) {
                        photos.add(await Api.instance.uploadImage(
                          await f.readAsBytes(),
                          mime: Api.imageMimeForPath(f.path),
                        ));
                      }
                      setSt(() {});
                    } catch (_) {
                      if (c.mounted) showToast(c, tr("Rasm olib bo'lmadi"), error: true);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(color: pal.card, border: Border.all(color: pal.border, width: 2), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.add_rounded, color: pal.muted)),
                ),
            ]),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: busy ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: pal.onAccent)) : const Icon(Icons.check_rounded, size: 18),
              label: Text(busy ? tr('Saqlanmoqda...') : (p == null ? tr("Qo'shish") : tr('Saqlash'))),
              onPressed: busy
                  ? null
                  : () async {
                      // Mijoz tomonida tekshiruv: narx > 0, kategoriya va kamida 1 ta rasm
                      final priceVal = int.tryParse(price.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                      if (priceVal <= 0) return showToast(c, tr('Narxni kiriting'), error: true);
                      if (category == null) return showToast(c, tr('Kategoriyani tanlang'), error: true);
                      if (photos.isEmpty) return showToast(c, tr('Kamida 1 ta rasm yuklang'), error: true);
                      setSt(() {
                        busy = true;
                        rejection = null;
                      });
                      try {
                        final body = {'name': name.text.trim(), 'price': priceVal, 'description': desc.text, 'photos': photos, 'category': category};
                        p == null ? await Api.instance.post('/api/seller/products', body) : await Api.instance.put('/api/seller/products/${p.id}', body);
                        if (c.mounted) Navigator.pop(c);
                        onSaved();
                      } on ApiException catch (e) {
                        if (c.mounted) {
                          setSt(() {
                            busy = false;
                            if (e.rejected) rejection = e.message;
                          });
                        }
                        if (!e.rejected && c.mounted) showToast(c, e.message, error: true);
                      } catch (e) {
                        if (c.mounted) {
                          setSt(() => busy = false);
                          showToast(c, sellerErrorText(e), error: true);
                        }
                      }
                    },
            ),
          ]),
        );
      },
    ),
  );
}

// ---- Xabarnomalar ----
void openNotifications(BuildContext context) async {
  showModalBottomSheet(
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => FutureBuilder(
      future: Api.instance.get('/api/seller/notifications?read=1').then((r) {
        AppState.instance.unread = 0;
        AppState.instance.refresh();
        return (r as List).map((e) => Notif.fromJson(e)).toList();
      }),
      builder: (c, snap) {
        final list = snap.data ?? [];
        final pal = c.p;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Expanded(child: Text('Xabarnomalar', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4))),
              if (list.isNotEmpty)
                IconBtn(Icons.delete_outline_rounded, size: 38, onTap: () async {
                  if (!await confirmDialog(c, "Xabarnomalarni o'chirasizmi?", text: '${list.length} ta xabarnoma butunlay o\'chiriladi.', ok: "O'chirish", danger: true)) return;
                  await Api.instance.delete('/api/seller/notifications');
                  if (c.mounted) Navigator.pop(c);
                }),
            ]),
            const SizedBox(height: 8),
            if (!snap.hasData)
              const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))
            else if (list.isEmpty)
              const EmptyBox(Icons.notifications_none_rounded, "Hozircha xabarnoma yo'q")
            else
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final n in list)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: n.read ? pal.border : pal.accent.withValues(alpha: .4))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: n.type == 'security' ? pal.danger.withValues(alpha: .12) : pal.accentSoft, borderRadius: BorderRadius.circular(12)),
                            child: Icon(switch (n.type) { 'order' => Icons.shopping_cart_outlined, 'security' => Icons.shield_outlined, _ => Icons.key_outlined },
                                size: 18, color: n.type == 'security' ? pal.danger : pal.accentText)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800))),
                            Text(fmtTime(n.createdAt), style: TextStyle(fontSize: 11, color: pal.muted))
                          ]),
                          const SizedBox(height: 2),
                          Text(n.text, style: TextStyle(fontSize: 13, color: pal.text.withValues(alpha: .8), height: 1.4)),
                          if (n.mapUrl != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), backgroundColor: pal.bg, side: BorderSide.none),
                                    icon: const Icon(Icons.map_outlined, size: 16),
                                    label: const Text("Xaritada ko'rish"),
                                    onPressed: () => launchUrl(Uri.parse(n.mapUrl!), mode: LaunchMode.externalApplication))),
                        ])),
                      ]),
                    ),
                ]),
              ),
          ]),
        );
      },
    ),
  );
}

// ---- Profil ----
class ProfileTab extends StatelessWidget {
  final VoidCallback onExit;
  const ProfileTab({super.key, required this.onExit});

  Widget item(BuildContext c, IconData ic, String title, {String? sub, VoidCallback? onTap, bool danger = false}) {
    final p = c.p;
    // Oq kartochka ichida bosilish effekti ko'rinishi uchun ListTile o'z Material qatlamida turadi
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
      onTap: onTap,
      leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: danger ? p.danger.withValues(alpha: .1) : p.bg, borderRadius: BorderRadius.circular(12)),
          child: Icon(ic, size: 18, color: danger ? p.danger : p.accentText)),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: danger ? p.danger : null)),
      subtitle: sub == null ? null : Text(sub, style: TextStyle(fontSize: 12, color: p.muted)),
      trailing: danger ? null : Icon(Icons.chevron_right_rounded, color: p.muted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.instance;
    final s = st.sellerShop!;
    final p = context.p;
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        SellerHeader(tr('Profil'), onExit: onExit),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, navPad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(22), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
              child: Column(children: [
                ShopAvatar(s, size: 76, shadow: true, badge: true),
                const SizedBox(height: 12),
                Text(s.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.3)),
                Text('${s.ownerName ?? ''} · @${s.login ?? ''}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 13)),
                if (s.description.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(s.description, textAlign: TextAlign.center, style: TextStyle(color: p.text.withValues(alpha: .8), fontSize: 13, height: 1.4))),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: p.bg, side: BorderSide.none),
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: Text(s.logo == null ? tr('Logo yuklash') : tr("Logoni o'zgartirish")),
                    onPressed: () async {
                      final src = await askImageSource(context);
                      if (src == null) return;
                      final f = await ImagePicker().pickImage(source: src, maxWidth: 512, imageQuality: 85);
                      if (f == null) return;
                      try {
                        final logo = await Api.instance.uploadImage(
                          await f.readAsBytes(),
                          mime: Api.imageMimeForPath(f.path),
                        );
                        final r = await Api.instance.put('/api/seller/shop', {'logo': logo});
                        st.sellerShop = Shop.fromJson(r['shop']);
                        st.refresh();
                      } catch (e) {
                        if (context.mounted) showToast(context, sellerErrorText(e), error: true);
                      }
                    }),
              ]),
            ),
            const SizedBox(height: 12),
            _InstagramSellerInsights(shop: s),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
              child: Column(children: [
                // Ilova tili — sotuvchi o'z profilidan o'zgartiradi
                item(context, Icons.translate_rounded, tr('Til'), sub: '${L10n.flags[L10n.lang]} ${L10n.names[L10n.lang]}', onTap: () => showLangSheet(context)),
                item(context, Icons.settings_outlined, tr("Do'kon sozlamalari"), sub: 'Nomi, sotuvchi ismi, telefon, izoh', onTap: () => _settings(context)),
                item(context, Icons.map_outlined, tr("Do'kon joylashuvi"),
                    sub: s.lat == null ? "Xaritada ko'rinishi uchun belgilang" : (s.address?.isNotEmpty == true ? s.address! : '${s.lat!.toStringAsFixed(4)}, ${s.lon!.toStringAsFixed(4)}'),
                    onTap: () => _location(context)),
                item(context, Icons.brightness_6_outlined, 'Mavzu',
                    sub: const {ThemeMode.system: 'Avtomatik', ThemeMode.light: "Yorug'", ThemeMode.dark: "Qorong'i"}[st.themeMode],
                    onTap: () => st.setTheme(ThemeMode.values[(st.themeMode.index + 1) % 3])),
                item(context, Icons.key_outlined, "Parolni o'zgartirish", onTap: () => _password(context)),
                item(context, Icons.storefront_outlined, "Do'konni xaridor ko'zi bilan ko'rish", onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(s.id)))),
                item(context, Icons.picture_as_pdf_outlined, tr('Hisobot (PDF)'),
                    sub: tr("Barcha ko'rsatkichlar bitta sahifada. Brauzerda ochiladi, PDF qilib saqlash mumkin."), onTap: () => downloadReport(context)),
                item(context, Icons.restart_alt_rounded, 'Hisobni yopib, yangisini boshlash', sub: "Buyurtmalar va ko'rishlar nolga tushadi, mahsulotlar qoladi", onTap: () => _reset(context)),
                item(context, Icons.logout_rounded, tr('Chiqish'), danger: true, onTap: () async {
                  if (!await confirmDialog(context, tr("Do'kondan chiqasizmi?"), ok: tr('Chiqish'))) return;
                  try {
                    await Api.instance.post('/api/seller/logout');
                  } catch (e) {
                    // Server chiqishni tasdiqlamasa, sessiya saqlanib qoladi — ekranda qolamiz
                    if (context.mounted) showToast(context, sellerErrorText(e), error: true);
                    return;
                  }
                  st.sellerShop = null;
                  st.refresh();
                  onExit();
                }),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  void _settings(BuildContext context) {
    final s = AppState.instance.sellerShop!;
    final name = TextEditingController(text: s.name);
    final seller = TextEditingController(text: s.sellerName);
    final phone = TextEditingController(text: s.phone);
    final desc = TextEditingController(text: s.description);
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text("Do'kon sozlamalari", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
          const SizedBox(height: 12),
          TextField(controller: name, decoration: const InputDecoration(labelText: "Do'kon nomi")),
          const SizedBox(height: 10),
          TextField(controller: seller, decoration: const InputDecoration(labelText: 'Sotuvchi ismi')),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon')),
          const SizedBox(height: 10),
          TextField(controller: desc, maxLines: 3, maxLength: 200, decoration: const InputDecoration(labelText: "Do'kon izohi")),
          const SizedBox(height: 6),
          FilledButton(
              onPressed: () async {
                try {
                  final r = await Api.instance.put('/api/seller/shop', {'name': name.text, 'sellerName': seller.text, 'phone': phone.text, 'description': desc.text});
                  AppState.instance.sellerShop = Shop.fromJson(r['shop']);
                  AppState.instance.refresh();
                  if (c.mounted) Navigator.pop(c);
                } catch (e) {
                  if (c.mounted) showToast(c, sellerErrorText(e), error: true);
                }
              },
              child: const Text('Saqlash')),
        ]),
      ),
    );
  }

  void _location(BuildContext context) {
    final s = AppState.instance.sellerShop!;
    LatLng? pos = s.lat == null ? null : LatLng(s.lat!, s.lon!);
    final addr = TextEditingController(text: s.address ?? '');
    final ctrl = MapController();
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text("Do'kon joylashuvi", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
            Text("Xaritada do'koningiz joyiga bosing yoki tugmani bosing", style: TextStyle(color: c.p.muted, fontSize: 13)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 300,
                child: FlutterMap(
                  mapController: ctrl,
                  options: MapOptions(initialCenter: pos ?? const LatLng(41.3111, 69.2797), initialZoom: pos == null ? 12 : 15, onTap: (_, p) => setSt(() => pos = p)),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'uz.saler.ai'),
                    if (pos != null) MarkerLayer(markers: [Marker(point: pos!, width: 44, height: 52, child: Icon(Icons.location_on, color: c.p.danger, size: 44))]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('Mening joylashuvim'),
              onPressed: () async {
                try {
                  var perm = await Geolocator.checkPermission();
                  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
                  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw Exception(tr('Joylashuvga ruxsat berilmadi'));
                  final p = await Geolocator.getCurrentPosition();
                  setSt(() => pos = LatLng(p.latitude, p.longitude));
                  ctrl.move(pos!, 16);
                } catch (e) {
                  if (c.mounted) showToast(c, sellerErrorText(e), error: true);
                }
              },
            ),
            const SizedBox(height: 10),
            TextField(controller: addr, decoration: const InputDecoration(labelText: 'Manzil (ixtiyoriy)', hintText: 'Masalan: Chorsu bozori, 2-qator')),
            const SizedBox(height: 6),
            Text(pos == null ? 'Joy tanlanmagan' : '${pos!.latitude.toStringAsFixed(5)}, ${pos!.longitude.toStringAsFixed(5)}', style: TextStyle(color: c.p.muted, fontSize: 12)),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Saqlash'),
              onPressed: () async {
                if (pos == null) return showToast(c, 'Avval xaritada joyni belgilang', error: true);
                try {
                  final r = await Api.instance.put('/api/seller/shop', {
                    'location': {'lat': pos!.latitude, 'lon': pos!.longitude, 'address': addr.text}
                  });
                  AppState.instance.sellerShop = Shop.fromJson(r['shop']);
                  AppState.instance.refresh();
                  if (c.mounted) Navigator.pop(c);
                } catch (e) {
                  if (c.mounted) showToast(c, sellerErrorText(e), error: true);
                }
              },
            ),
            if (s.lat != null)
              TextButton.icon(
                icon: Icon(Icons.delete_outline_rounded, color: c.p.danger, size: 18),
                label: Text("Joylashuvni o'chirish", style: TextStyle(color: c.p.danger)),
                onPressed: () async {
                  if (!await confirmDialog(c, tr("Joylashuv o'chirilsinmi?"), ok: tr("O'chirish"), danger: true)) return;
                  try {
                    final r = await Api.instance.put('/api/seller/shop', {'location': null});
                    AppState.instance.sellerShop = Shop.fromJson(r['shop']);
                    AppState.instance.refresh();
                    if (c.mounted) Navigator.pop(c);
                  } catch (e) {
                    if (c.mounted) showToast(c, sellerErrorText(e), error: true);
                  }
                },
              ),
          ]),
        ),
      ),
    );
  }

  /// Hisobni yopib yangisini boshlash: avval PDF haqida so'raydi, keyin parol bilan tasdiqlaydi
  void _reset(BuildContext context) {
    final pwd = TextEditingController();
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) {
        final p = c.p;
        const amber = Color(0xFFA86F00);
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Yangi hisob boshlash', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: amber.withValues(alpha: .1), borderRadius: BorderRadius.circular(14), border: Border.all(color: amber.withValues(alpha: .3))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, color: amber),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Nima bo'ladi?", style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                      "Barcha buyurtmalar arxivga o'tadi, ko'rishlar va statistika nolga tushadi, xabarnomalar tozalanadi. Mahsulotlar, logo va sozlamalar saqlanib qoladi. Bu amalni qaytarib bo'lmaydi.",
                      style: TextStyle(fontSize: 13, color: p.text.withValues(alpha: .85), height: 1.4))
                ])),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16), border: c.isDark ? Border.all(color: p.border) : null),
              child: Row(children: [
                Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: p.danger.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.picture_as_pdf_outlined, size: 18, color: p.danger)),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Hisobotni saqlab oldingizmi?'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  Text("Eski hisob ma'lumotlari faqat hisobotda qoladi", style: TextStyle(fontSize: 11, color: p.muted))
                ])),
                const SizedBox(width: 8),
                OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 10), backgroundColor: p.bg, side: BorderSide.none),
                    onPressed: () => downloadReport(c),
                    child: Text(tr('Ochish'), style: const TextStyle(fontSize: 12))),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(controller: pwd, obscureText: true, decoration: const InputDecoration(labelText: "Tasdiqlash uchun do'kon parolini kiriting")),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.danger),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Hisobni yopib, yangisini boshlash'),
              onPressed: () async {
                if (pwd.text.isEmpty) return showToast(c, 'Parolni kiriting', error: true);
                if (!await confirmDialog(c, 'Aniq yangi hisob boshlaysizmi?',
                    text: tr("Hisobotni saqlab olganingizga ishonch hosil qiling — eski buyurtmalar qaytmaydi."), ok: tr('Ha, boshlash'), danger: true)) {
                      return;
                    }
                try {
                  final r = await Api.instance.post('/api/seller/reset', {'password': pwd.text});
                  AppState.instance.refreshBadges();
                  if (c.mounted) Navigator.pop(c);
                  if (context.mounted) showToast(context, 'Yangi hisob boshlandi: ${r['orders']} ta buyurtma arxivlandi');
                } catch (e) {
                  if (c.mounted) showToast(c, sellerErrorText(e), error: true);
                }
              },
            ),
          ]),
        );
      },
    );
  }

  void _password(BuildContext context) {
    final o = TextEditingController(), n = TextEditingController(), n2 = TextEditingController(), code = TextEditingController();
    var codeSent = false, busy = false;
    String? devCode, error;
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text("Parolni o'zgartirish", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
            const SizedBox(height: 5),
            Text(codeSent ? 'Emailingizga yuborilgan 6 xonali kodni kiriting' : 'Yangi parol email-kod bilan tasdiqlanadi', style: TextStyle(fontSize: 13, color: c.p.muted)),
            const SizedBox(height: 12),
            TextField(controller: o, obscureText: true, enabled: !codeSent && !busy, decoration: const InputDecoration(labelText: 'Joriy parol')),
            const SizedBox(height: 10),
            TextField(controller: n, obscureText: true, enabled: !codeSent && !busy, decoration: const InputDecoration(labelText: 'Yangi parol (kamida 6 belgi)')),
            if (!codeSent) ...[
              const SizedBox(height: 10),
              TextField(controller: n2, obscureText: true, enabled: !busy, decoration: const InputDecoration(labelText: 'Yangi parolni takrorlang')),
            ] else ...[
              const SizedBox(height: 10),
              TextField(controller: code, keyboardType: TextInputType.number, maxLength: 6, enabled: !busy, decoration: const InputDecoration(labelText: '6 xonali tasdiqlash kodi', counterText: '')),
              if (devCode != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Test kodi: $devCode', style: TextStyle(fontSize: 12, color: c.p.accentText, fontWeight: FontWeight.w800)),
                ),
            ],
            if (error != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(fontSize: 12, color: c.p.danger, fontWeight: FontWeight.w700))),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(codeSent ? Icons.verified_rounded : Icons.mark_email_read_outlined, size: 18),
              label: Text(codeSent ? 'Kod bilan tasdiqlash' : 'Emailga kod yuborish'),
              onPressed: busy
                  ? null
                  : () async {
                      if (n.text != n2.text && !codeSent) {
                        setSheet(() => error = 'Parollar mos kelmadi');
                        return;
                      }
                      setSheet(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final result = await Api.instance.post('/api/seller/password', {
                          'oldPassword': o.text,
                          'newPassword': n.text,
                          if (codeSent) 'code': code.text,
                        });
                        if (!c.mounted) return;
                        if (!codeSent) {
                          setSheet(() {
                            codeSent = true;
                            devCode = result['devCode']?.toString();
                          });
                        } else {
                          Navigator.pop(c);
                          if (context.mounted) showToast(context, "Parol email kodi bilan o'zgartirildi");
                        }
                      } catch (e) {
                        if (c.mounted) setSheet(() => error = sellerErrorText(e));
                      } finally {
                        if (c.mounted) setSheet(() => busy = false);
                      }
                    },
            ),
          ]),
        ),
      ),
    );
  }
}

/// Sotuvchining Instagram-uslubidagi professional profili: obunachilar,
/// qamrov va har bir mahsulot postining haqiqiy ko'rish natijalari.
class _InstagramSellerInsights extends StatefulWidget {
  final Shop shop;
  const _InstagramSellerInsights({required this.shop});

  @override
  State<_InstagramSellerInsights> createState() => _InstagramSellerInsightsState();
}

class _InstagramSellerInsightsState extends State<_InstagramSellerInsights> {
  Map<String, dynamic>? data;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _n(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  String _short(int value) => value >= 1000000
      ? '${(value / 1000000).toStringAsFixed(1)}M'
      : value >= 1000
          ? '${(value / 1000).toStringAsFixed(1)}K'
          : '$value';
  List<Map<String, dynamic>> _rows(dynamic raw) => (raw as List? ?? const [])
      .whereType<Map>()
      .map((row) => row.cast<String, dynamic>())
      .toList();

  Future<void> _load() async {
    if (loading == false && !mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await Api.instance.get('/api/seller/audience');
      if (!mounted) return;
      setState(() {
        data = response is Map ? response.cast<String, dynamic>() : <String, dynamic>{};
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = sellerErrorText(e);
        loading = false;
      });
    }
  }

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).take(2);
    final text = words.map((word) => word[0]).join();
    return text.isEmpty ? 'X' : text.toUpperCase();
  }

  void _followersSheet(List<Map<String, dynamic>> followers) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final p = sheetContext.p;
        return SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .72,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Obunachilar', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
              const SizedBox(height: 3),
              Text('Eng yangi obunachilar va do\'koningizdagi faolligi', style: TextStyle(color: p.muted, fontSize: 13)),
              const SizedBox(height: 12),
              Expanded(
                child: followers.isEmpty
                    ? const EmptyBox(Icons.people_outline_rounded, 'Hali obunachilar yo\'q')
                    : ListView.separated(
                        itemCount: followers.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: p.border),
                        itemBuilder: (_, index) {
                          final f = followers[index];
                          final name = '${f['name'] ?? 'Xaridor'}';
                          final last = '${f['lastProduct'] ?? ''}'.trim();
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 3),
                            leading: CircleAvatar(
                              backgroundColor: p.accentSoft,
                              foregroundColor: p.accentText,
                              child: Text(_initials(name), style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(
                              last.isEmpty
                                  ? 'Hali mahsulot ko\'rmagan'
                                  : 'Oxirgi ko\'rgan: $last',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('${_n(f['views'])} ko\'rish', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                              Text('${_n(f['orders'])} buyurtma', style: TextStyle(fontSize: 11, color: p.muted)),
                            ]),
                          );
                        },
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }

  void _productSheet(Map<String, dynamic> product) {
    final p = context.p;
    final photo = product['photo']?.toString();
    final name = '${product['name'] ?? 'Mahsulot'}';
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (photo != null && photo.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(height: 180, child: Image.network(Api.instance.photoUrl(photo), fit: BoxFit.cover)),
            )
          else
            Container(height: 120, decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(18)), child: Icon(Icons.inventory_2_outlined, color: p.muted, size: 42)),
          const SizedBox(height: 14),
          Text(name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Row(children: [
            _detail(Icons.visibility_outlined, _short(_n(product['views'])), 'ko\'rish'),
            _detail(Icons.people_outline_rounded, _short(_n(product['followerViews'])), 'obunachi'),
            _detail(Icons.favorite_border_rounded, _short(_n(product['likes'])), 'layk'),
            _detail(Icons.shopping_bag_outlined, _short(_n(product['sold'])), 'sotildi'),
          ]),
        ]),
      ),
    );
  }

  Widget _detail(IconData icon, String value, String label) => Expanded(
        child: Column(children: [
          Icon(icon, size: 19),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(fontSize: 10, color: context.p.muted)),
        ]),
      );

  Widget _metric({required String value, required String label, VoidCallback? onTap}) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Column(children: [
              Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -.4)),
              const SizedBox(height: 2),
              Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: context.p.muted, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    if (loading && data == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context)),
        padding: const EdgeInsets.all(16),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Skeleton(height: 42), SizedBox(height: 12), Skeleton(height: 104)]),
      );
    }
    if (error != null && data == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context)),
        child: EmptyBox(Icons.insights_outlined, error!, action: OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded, size: 17), label: const Text('Qayta urinish'))),
      );
    }

    final summary = (data?['summary'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final followers = _rows(data?['followers']);
    final products = _rows(data?['products']);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.insights_rounded, size: 19),
          const SizedBox(width: 7),
          const Expanded(child: Text('Professional profil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
          IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 19), tooltip: 'Yangilash'),
        ]),
        Row(children: [
          _metric(value: '${widget.shop.productCount}', label: 'mahsulot', onTap: products.isEmpty ? null : () => _productSheet(products.first)),
          _metric(value: _short(_n(summary['followers'])), label: 'obunachi', onTap: () => _followersSheet(followers)),
          _metric(value: _short(_n(summary['reach'])), label: 'qamrov'),
          _metric(value: _short(_n(summary['engagedFollowers'])), label: 'faol'),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.grid_on_rounded, size: 17, color: p.accentText),
          const SizedBox(width: 7),
          const Expanded(child: Text('Mahsulotlar ko\'rishlari', style: TextStyle(fontWeight: FontWeight.w900))),
          Text('${_short(_n(summary['likes']))} layk', style: TextStyle(fontSize: 11, color: p.muted, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        if (products.isEmpty)
          Container(height: 94, alignment: Alignment.center, decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(14)), child: Text('Mahsulot qo\'shilgach ko\'rishlar shu yerda chiqadi', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)))
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: products.length.clamp(0, 6),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 5, mainAxisSpacing: 5, childAspectRatio: .84),
            itemBuilder: (_, index) {
              final product = products[index];
              final photo = product['photo']?.toString();
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _productSheet(product),
                child: Ink(
                  decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(12)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(fit: StackFit.expand, children: [
                      if (photo != null && photo.isNotEmpty)
                        Image.network(Api.instance.photoUrl(photo), fit: BoxFit.cover)
                      else
                        Icon(Icons.inventory_2_outlined, color: p.muted),
                      const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xAA000000)]))),
                      Positioned(
                        left: 7,
                        right: 7,
                        bottom: 6,
                        child: Row(children: [
                          const Icon(Icons.visibility_outlined, color: Colors.white, size: 14),
                          const SizedBox(width: 3),
                          Expanded(child: Text(_short(_n(product['views'])), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900))),
                        ]),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
        if (followers.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.people_alt_outlined, size: 17),
            const SizedBox(width: 7),
            const Expanded(child: Text('Yangi obunachilar', style: TextStyle(fontWeight: FontWeight.w900))),
            TextButton(onPressed: () => _followersSheet(followers), child: const Text('Barchasi')),
          ]),
          for (final follower in followers.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                CircleAvatar(radius: 16, backgroundColor: p.accentSoft, foregroundColor: p.accentText, child: Text(_initials('${follower['name'] ?? ''}'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
                const SizedBox(width: 9),
                Expanded(child: Text('${follower['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                Text('${_n(follower['views'])} ko\'rish', style: TextStyle(fontSize: 11, color: p.muted, fontWeight: FontWeight.w700)),
              ]),
            ),
        ],
      ]),
    );
  }
}
