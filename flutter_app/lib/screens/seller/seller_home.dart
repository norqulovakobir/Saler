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

  @override
  void initState() {
    super.initState();
    AppState.instance.refreshBadges();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.instance;
    final roots = [AnalyticsTab(onExit: widget.onExit), OrdersTab(onExit: widget.onExit), AdviceTab(onExit: widget.onExit), ProductsTab(onExit: widget.onExit), ProfileTab(onExit: widget.onExit)];
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
          body: IndexedStack(index: index, children: pages),
          bottomNavigationBar: FloatingNav(
            index: index,
            badges: {1: st.newOrders},
            onTap: (i) => i == index ? keys[i].currentState?.popUntil((r) => r.isFirst) : setState(() => index = i),
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

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final cached = Api.instance.cached('/api/seller/orders');
    if (cached != null) {
      orders = (cached as List).map((e) => Order.fromJson(e)).toList();
      loading = false;
      if (mounted) setState(() {});
    }
    try {
      orders = ((await Api.instance.get('/api/seller/orders')) as List).map((e) => Order.fromJson(e)).toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> setStatus(Order o, String status) async {
    try {
      await Api.instance.patch('/api/seller/orders/${o.id}', {'status': status});
      await load();
      AppState.instance.refreshBadges();
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final list = filter == 'all' ? orders : orders.where((o) => o.status == filter).toList();
    int count(String k) => k == 'all' ? orders.length : orders.where((o) => o.status == k).length;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: EdgeInsets.zero, children: [
          SellerHeader('Buyurtmalar', onExit: widget.onExit),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, navPad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ChoiceChips(
                  items: [('new', 'Yangi · ${count('new')}'), ('all', 'Hammasi · ${count('all')}'), ('done', 'Bajarilgan · ${count('done')}'), ('cancelled', 'Bekor · ${count('cancelled')}')],
                  value: filter,
                  onChanged: (v) => setState(() => filter = v)),
              const SizedBox(height: 12),
              if (loading)
                const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator(strokeWidth: 2.5)))
              else if (list.isEmpty)
                const EmptyBox(Icons.receipt_long_outlined, "Buyurtma yo'q")
              else
                for (final o in list)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [StatusBadge(o.status, o.statusLabel), const Spacer(), Text(fmtTime(o.createdAt), style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600))]),
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
                        Text(o.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        Icon(Icons.send_outlined, size: 14, color: p.muted),
                        const SizedBox(width: 6),
                        Expanded(child: Text(o.buyerLink, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13))),
                      ]),
                      const SizedBox(height: 4),
                      InkWell(
                          onTap: () => launchUrl(Uri.parse('tel:${o.phone}')),
                          child: Row(children: [
                            Icon(Icons.phone_outlined, size: 16, color: p.success),
                            const SizedBox(width: 6),
                            Text(o.phone, style: TextStyle(color: p.accentText, fontWeight: FontWeight.w700))
                          ])),
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
                                    label: const Text('Bajarildi'),
                                    onPressed: () => setStatus(o, 'done'))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                        minimumSize: const Size.fromHeight(40),
                                        backgroundColor: p.danger.withValues(alpha: .12),
                                        foregroundColor: p.danger,
                                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                                    icon: const Icon(Icons.close_rounded, size: 16),
                                    label: const Text('Bekor'),
                                    onPressed: () => setStatus(o, 'cancelled'))),
                          ]),
                        ),
                    ]),
                  ),
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
  late Future<dynamic> future = Api.instance.get('/api/seller/advice');
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        SellerHeader('AI tavsiyalar', onExit: widget.onExit),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, navPad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DarkBanner(
              glow: const Color(0xFF7C5CFF),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.auto_awesome, size: 14, color: Color(0xFFC9D3FF)),
                  SizedBox(width: 6),
                  Text('AI MASLAHATCHI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: Color(0xFFC9D3FF)))
                ]),
                const SizedBox(height: 8),
                Text("Do'koningiz ma'lumotlarini tahlil qilib, sotuvni oshirish bo'yicha tavsiyalar beradi",
                    style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 14, height: 1.4, fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 12),
            FutureBuilder(
              future: future,
              initialData: Api.instance.cached('/api/seller/advice'),
              builder: (_, snap) {
                if (!snap.hasData) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)));
                final tips = (snap.data['tips'] as List).map((e) => Tip.fromJson(e)).toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Qayta tahlil qilish'),
                      onPressed: () => setState(() => future = Api.instance.get('/api/seller/advice?refresh=1'))),
                ]);
              },
            ),
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
            label: const Text("Mahsulot qo'shish", style: TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () => openProductForm(context, null, load)),
      ),
      body: ListView(padding: EdgeInsets.zero, children: [
        SellerHeader('Mahsulotlar', onExit: widget.onExit),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, navPad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SearchField(hint: 'Qidirish...', onChanged: (v) => setState(() => q = v)),
            const SizedBox(height: 12),
            if (loading)
              const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator(strokeWidth: 2.5)))
            else if (list.isEmpty)
              const EmptyBox(Icons.inventory_2_outlined, "Hozircha mahsulot yo'q")
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
                          Text('  ·  ${x.views} ko\'rish${x.active ? '' : '  ·  yashirin'}', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600))
                        ]),
                      ])),
                      IconBtn(x.active ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 36, bg: p.bg, onTap: () async {
                        await Api.instance.put('/api/seller/products/${x.id}', {'active': !x.active});
                        load();
                      }),
                      const SizedBox(width: 6),
                      IconBtn(Icons.edit_outlined, size: 36, bg: p.bg, onTap: () => openProductForm(context, x, load)),
                      const SizedBox(width: 6),
                      IconBtn(Icons.delete_outline_rounded, size: 36, bg: p.danger.withValues(alpha: .1), color: p.danger, onTap: () async {
                        if (!await confirmDialog(context, '"${x.name}" o\'chirilsinmi?', text: "Bu amalni qaytarib bo'lmaydi.", ok: "O'chirish", danger: true)) return;
                        await Api.instance.delete('/api/seller/products/${x.id}');
                        load();
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

/// Mahsulot qo'shish / tahrirlash (rasm majburiy, AI tekshiradi)
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
            Text(p == null ? 'Yangi mahsulot' : 'Tahrirlash', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
            if (rejection != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: pal.danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.danger.withValues(alpha: .3))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline_rounded, color: pal.danger),
                  const SizedBox(width: 10),
                  Expanded(child: Text('AI tekshiruvi rad etdi: $rejection', style: const TextStyle(fontWeight: FontWeight.w600)))
                ]),
              ),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nomi')),
            const SizedBox(height: 10),
            TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Narxi (so'm)")),
            const SizedBox(height: 10),
            TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Tavsif')),
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
                    final files = await ImagePicker().pickMultiImage(maxWidth: 1280, imageQuality: 85);
                    for (final f in files.take(10 - photos.length)) {
                      photos.add('data:image/jpeg;base64,${base64Encode(await f.readAsBytes())}');
                    }
                    setSt(() {});
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
              icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_rounded, size: 18),
              label: Text(busy ? 'AI tekshirmoqda...' : (p == null ? "Qo'shish" : 'Saqlash')),
              onPressed: busy
                  ? null
                  : () async {
                      if (photos.isEmpty) return showToast(c, 'Kamida 1 ta rasm yuklang', error: true);
                      setSt(() {
                        busy = true;
                        rejection = null;
                      });
                      if (category == null) {
                        setSt(() => busy = false);
                        showToast(c, tr('Kategoriyani tanlang'), error: true);
                        return;
                      }
                      try {
                        final body = {'name': name.text, 'price': price.text, 'description': desc.text, 'photos': photos, 'category': category};
                        p == null ? await Api.instance.post('/api/seller/products', body) : await Api.instance.put('/api/seller/products/${p.id}', body);
                        if (c.mounted) Navigator.pop(c);
                        onSaved();
                      } on ApiException catch (e) {
                        setSt(() {
                          busy = false;
                          if (e.rejected) rejection = e.message;
                        });
                        if (!e.rejected && c.mounted) showToast(c, e.message, error: true);
                      } catch (e) {
                        setSt(() => busy = false);
                        if (c.mounted) showToast(c, e.toString(), error: true);
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
    return ListTile(
      onTap: onTap,
      leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: danger ? p.danger.withValues(alpha: .1) : p.bg, borderRadius: BorderRadius.circular(12)),
          child: Icon(ic, size: 18, color: danger ? p.danger : p.accentText)),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: danger ? p.danger : null)),
      subtitle: sub == null ? null : Text(sub, style: TextStyle(fontSize: 12, color: p.muted)),
      trailing: danger ? null : Icon(Icons.chevron_right_rounded, color: p.muted),
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
                      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, imageQuality: 85);
                      if (f == null) return;
                      try {
                        final r = await Api.instance.put('/api/seller/shop', {'logo': 'data:image/jpeg;base64,${base64Encode(await f.readAsBytes())}'});
                        st.sellerShop = Shop.fromJson(r['shop']);
                        st.refresh();
                      } catch (e) {
                        if (context.mounted) showToast(context, e.toString(), error: true);
                      }
                    }),
              ]),
            ),
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
                item(context, Icons.picture_as_pdf_outlined, 'PDF hisobot', sub: "Barcha ko'rsatkichlar bitta faylda, Telegram botga yuboriladi", onTap: () => downloadReport(context)),
                item(context, Icons.restart_alt_rounded, 'Hisobni yopib, yangisini boshlash', sub: "Buyurtmalar va ko'rishlar nolga tushadi, mahsulotlar qoladi", onTap: () => _reset(context)),
                item(context, Icons.logout_rounded, tr('Chiqish'), danger: true, onTap: () async {
                  if (!await confirmDialog(context, "Do'kondan chiqasizmi?", ok: 'Chiqish')) return;
                  await Api.instance.post('/api/seller/logout');
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
                  if (c.mounted) showToast(c, e.toString(), error: true);
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
                  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw Exception('Joylashuvga ruxsat berilmadi');
                  final p = await Geolocator.getCurrentPosition();
                  setSt(() => pos = LatLng(p.latitude, p.longitude));
                  ctrl.move(pos!, 16);
                } catch (e) {
                  if (c.mounted) showToast(c, e.toString(), error: true);
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
                  if (c.mounted) showToast(c, e.toString(), error: true);
                }
              },
            ),
            if (s.lat != null)
              TextButton.icon(
                icon: Icon(Icons.delete_outline_rounded, color: c.p.danger, size: 18),
                label: Text("Joylashuvni o'chirish", style: TextStyle(color: c.p.danger)),
                onPressed: () async {
                  if (!await confirmDialog(c, "Joylashuv o'chirilsinmi?", ok: "O'chirish", danger: true)) return;
                  final r = await Api.instance.put('/api/seller/shop', {'location': null});
                  AppState.instance.sellerShop = Shop.fromJson(r['shop']);
                  AppState.instance.refresh();
                  if (c.mounted) Navigator.pop(c);
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
                  const Text('PDF hisobotni yuklab oldingizmi?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  Text("Eski hisob ma'lumotlari faqat hisobotda qoladi", style: TextStyle(fontSize: 11, color: p.muted))
                ])),
                const SizedBox(width: 8),
                OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 10), backgroundColor: p.bg, side: BorderSide.none),
                    onPressed: () => downloadReport(c),
                    child: const Text('Yuklab olish', style: TextStyle(fontSize: 12))),
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
                    text: "PDF hisobotni yuklab olganingizga ishonch hosil qiling — eski buyurtmalar qaytmaydi.", ok: 'Ha, boshlash', danger: true)) return;
                try {
                  final r = await Api.instance.post('/api/seller/reset', {'password': pwd.text});
                  AppState.instance.refreshBadges();
                  if (c.mounted) Navigator.pop(c);
                  if (context.mounted) showToast(context, 'Yangi hisob boshlandi: ${r['orders']} ta buyurtma arxivlandi');
                } catch (e) {
                  if (c.mounted) showToast(c, e.toString(), error: true);
                }
              },
            ),
          ]),
        );
      },
    );
  }

  void _password(BuildContext context) {
    final o = TextEditingController(), n = TextEditingController(), n2 = TextEditingController();
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text("Parolni o'zgartirish", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
          const SizedBox(height: 12),
          TextField(controller: o, obscureText: true, decoration: const InputDecoration(labelText: 'Joriy parol')),
          const SizedBox(height: 10),
          TextField(controller: n, obscureText: true, decoration: const InputDecoration(labelText: 'Yangi parol (kamida 6 belgi)')),
          const SizedBox(height: 10),
          TextField(controller: n2, obscureText: true, decoration: const InputDecoration(labelText: 'Yangi parolni takrorlang')),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: () async {
                if (n.text != n2.text) return showToast(c, 'Parollar mos kelmadi', error: true);
                try {
                  await Api.instance.post('/api/seller/password', {'oldPassword': o.text, 'newPassword': n.text});
                  if (c.mounted) Navigator.pop(c);
                  if (context.mounted) showToast(context, "Parol o'zgartirildi");
                } catch (e) {
                  if (c.mounted) showToast(c, e.toString(), error: true);
                }
              },
              child: const Text("O'zgartirish")),
        ]),
      ),
    );
  }
}
