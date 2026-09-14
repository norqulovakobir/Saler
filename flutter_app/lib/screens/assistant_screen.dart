import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_screen.dart';
import 'courier/courier_home.dart' show providerIcon, vehicleName;
import 'courier/couriers_map_screen.dart';
import 'courier/cargo_screen.dart';
import 'map_screen.dart';
import 'shops_screen.dart';

class _Msg {
  final String role; // user | assistant | shops | couriers | cargo
  final String text;
  final List<Shop> shops;
  final List<Courier> couriers;
  final bool showMap;
  _Msg(this.role, this.text, {this.shops = const [], this.couriers = const [], this.showMap = false});
}

/// Umumiy AI yordamchi: do'kon tanlanmaganda xaridorga do'konlarni tavsiya qiladi,
/// xaritada ko'rsatadi. Buyurtmani rasmiylashtirmaydi — bu do'kon sotuvchisining ishi.
class AssistantScreen extends StatefulWidget {
  /// Tab ichida (orqaga tugmasiz) yoki alohida sahifa sifatida
  final bool inTab;
  /// Tab rejimida yopish tugmasi — bosh sahifaga qaytaradi
  final VoidCallback? onClose;
  const AssistantScreen({super.key, this.inTab = true, this.onClose});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final msgs = <_Msg>[];
  final inp = TextEditingController();
  final scroll = ScrollController();
  bool busy = false;
  Position? me;

  static const _hello = "Assalomu alaykum! Men Sofia, Saler AI yordamchisiman. Nima olmoqchisiz? Sizga mos do'konlarni topib, xaritada ko'rsataman.";

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    const path = '/api/assistant/history';
    void apply(dynamic r) {
      final h = (r['history'] as List? ?? const []);
      msgs.clear();
      if (h.isEmpty) {
        msgs.add(_Msg('assistant', tr(_hello)));
      } else {
        for (final m in h) {
          msgs.add(_Msg(m['role'], m['content']));
        }
      }
      if (mounted) setState(() {});
      _scrollDown();
    }

    final cached = Api.instance.cached(path);
    if (cached != null) apply(cached);
    try {
      apply(await Api.instance.get(path));
    } catch (_) {
      if (msgs.isEmpty) apply({'history': []});
    }
  }

  Future<void> clearHistory() async {
    if (!await confirmDialog(context, tr('Suhbatni tozalaysizmi?'), text: tr('Yordamchi suhbatni boshidan boshlaydi.'), ok: tr('Tozalash'), danger: true)) return;
    try {
      await Api.instance.delete('/api/assistant/history');
      msgs
        ..clear()
        ..add(_Msg('assistant', tr(_hello)));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent + 300, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  /// Joylashuvni bir marta olamiz (ruxsat bo'lsa) — yaqin do'konlar uchun
  Future<Position?> _locate({bool ask = false}) async {
    if (me != null) return me;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && ask) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      me = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium)).timeout(const Duration(seconds: 6));
      return me;
    } catch (_) {
      return null;
    }
  }

  Future<void> send(String text, {bool needLocation = false}) async {
    text = text.trim();
    if (text.isEmpty || busy) return;
    setState(() {
      busy = true;
      inp.clear();
      msgs.add(_Msg('user', text));
    });
    _scrollDown();
    final pos = await _locate(ask: needLocation || RegExp(r'yaqin|atrof|qayer|manzil|xarita', caseSensitive: false).hasMatch(text));
    try {
      final r = await Api.instance.post('/api/assistant', {'message': text, 'lang': L10n.code, if (pos != null) 'lat': pos.latitude, if (pos != null) 'lon': pos.longitude});
      final shops = (r['shops'] as List? ?? const []).map((e) => Shop.fromJson(e)).toList();
      final couriers = (r['couriers'] as List? ?? const []).map((e) => Courier.fromJson(e)).toList();
      msgs.add(_Msg('assistant', (r['text'] ?? '').toString()));
      if (shops.isNotEmpty) msgs.add(_Msg('shops', '', shops: shops, showMap: r['showMap'] == true));
      // Sofia kuryer yollashni o'zi qiladi: yaqin onlayn kuryerlar kartochkasi
      if (r['showCouriers'] == true) msgs.add(_Msg('couriers', '', couriers: couriers));
      if (r['showCargo'] == true) msgs.add(_Msg('cargo', ''));
    } catch (e) {
      msgs.add(_Msg('assistant', tr("Hozir javob bera olmayapman, birozdan so'ng urinib ko'ring.")));
    }
    if (mounted) setState(() => busy = false);
    _scrollDown();
  }

  void _openMap(List<Shop> shops) {
    final withLoc = shops.where((s) => s.lat != null).toList();
    if (withLoc.isEmpty) {
      showToast(context, tr("Bu do'konlarning joylashuvi ko'rsatilmagan"));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MapScreen(focus: withLoc)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      body: Column(children: [
        Container(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 10, 16, 12),
          decoration: BoxDecoration(color: p.card, border: Border(bottom: BorderSide(color: p.border))),
          child: Row(children: [
            IconBtn(widget.inTab ? Icons.close_rounded : Icons.arrow_back_ios_new_rounded, bg: p.bg, onTap: widget.inTab ? widget.onClose : () => Navigator.of(context).maybePop()),
            const SizedBox(width: 10),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFD633), Color(0xFFF2A900)])),
              child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF111111), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Sofia', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(tr("AI yordamchi · do'kon topib tavsiya beradi"), style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
              ]),
            ),
            IconBtn(Icons.map_outlined, bg: p.bg, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MapScreen()))),
            const SizedBox(width: 8),
            IconBtn(Icons.delete_outline_rounded, bg: p.bg, onTap: clearHistory),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            itemCount: msgs.length + (busy ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == msgs.length) return const TypingBubble();
              final m = msgs[i];
              if (m.role == 'couriers') return _CouriersBlock(m.couriers, me: me == null ? null : LatLng(me!.latitude, me!.longitude));
              if (m.role == 'cargo') return _CargoBlock();
              if (m.role == 'shops') {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final s in m.shops) _ShopBubble(s, onMap: () => _openMap([s])),
                  if (m.showMap || m.shops.where((s) => s.lat != null).length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: () => _openMap(m.shops),
                        icon: Icon(Icons.map_rounded, size: 18, color: p.accentText),
                        label: Text(tr("Hammasini xaritada ko'rish")),
                      ),
                    ),
                ]);
              }
              return ChatBubble(m.text, me: m.role == 'user');
            },
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            QuickChip(tr('Kuryer yollash'), () => send(tr('Men kuryer yollamoqchiman'), needLocation: true)),
            QuickChip(tr("Yaqin atrofdagi do'konlar"), () => send(tr("Yaqin atrofimdagi do'konlarni ko'rsating"), needLocation: true)),
            QuickChip(tr('Kiyim olmoqchiman'), () => send(tr('Men kiyim olmoqchiman'))),
            QuickChip(tr('Telefon kerak'), () => send(tr('Menga telefon kerak'))),
            QuickChip(tr('Oziq-ovqat'), () => send(tr("Oziq-ovqat do'konlari bormi?"))),
          ]),
        ),
        ChatInput(controller: inp, hint: tr('Nima olmoqchisiz?'), onSend: () => send(inp.text), bottomExtra: 0),
      ]),
    );
  }
}

/// Sofia ko'rsatadigan kuryerlar: kartochkalar (telefon, masofa, qo'ng'iroq, yollash) + xarita tugmasi
class _CouriersBlock extends StatelessWidget {
  final List<Courier> couriers;
  final LatLng? me;
  const _CouriersBlock(this.couriers, {this.me});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final c in couriers.take(4))
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 300,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
            child: Column(children: [
              Row(children: [
                ProviderAvatar(photo: c.photo, icon: providerIcon(c), role: 'courier', size: 48, online: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text('${vehicleName(c.vehicle)}${c.distanceKm != null ? ' · ${c.distanceKm! < 1 ? '${(c.distanceKm! * 1000).round()} m' : '${c.distanceKm} km'}' : ''} · ★ ${c.rating.toStringAsFixed(1)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
                    Text(c.phone, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.success)),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40), backgroundColor: p.successSoft, foregroundColor: p.success, side: BorderSide.none, padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)), icon: const Icon(Icons.phone_rounded, size: 16), label: Text(tr("Qo'ng'iroq")), onPressed: () => launchUrl(Uri.parse('tel:${c.phone}')))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(40), padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)), icon: const Icon(Icons.local_shipping_rounded, size: 16), label: Text(tr('Yollash')), onPressed: () => showHireCourierSheet(context, c, me: me))),
              ]),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const CouriersMapScreen())),
          icon: Icon(Icons.map_rounded, size: 18, color: p.accentText),
          label: Text(couriers.isEmpty ? tr("Xaritada kuryerlarni ko'rish") : tr("Hammasini xaritada ko'rish")),
        ),
      ),
    ]);
  }
}

/// Sofia: viloyatlararo yuk — tashuvchilar ro'yxatiga tugma
class _CargoBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 300,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.local_shipping_rounded, color: p.onAccent)),
          const SizedBox(width: 10),
          Expanded(child: Text(tr('Viloyatlararo yuk'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12)), onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const CargoScreen())), child: Text(tr('Ochish'))),
        ]),
      ),
    );
  }
}

/// Tavsiya qilingan do'kon kartochkasi
class _ShopBubble extends StatelessWidget {
  final Shop s;
  final VoidCallback onMap;
  const _ShopBubble(this.s, {required this.onMap});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final dist = s.distanceKm;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 300,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(s.id))),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                ShopAvatar(s, size: 54),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    if (s.description.isNotEmpty) Text(s.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.inventory_2_outlined, size: 13, color: p.muted),
                      const SizedBox(width: 4),
                      Text('${s.productCount} ${tr('ta mahsulot')}', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
                      if (dist != null) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.near_me_outlined, size: 13, color: p.accentText),
                        const SizedBox(width: 3),
                        Text('${dist < 1 ? '${(dist * 1000).round()} m' : '$dist km'}', style: TextStyle(fontSize: 12, color: p.accentText, fontWeight: FontWeight.w700)),
                      ],
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(40), padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  icon: const Icon(Icons.storefront_rounded, size: 16),
                  label: Text(tr("Do'konga kirish")),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(s.id))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      padding: EdgeInsets.zero,
                      backgroundColor: p.bg,
                      side: BorderSide.none,
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: Text(tr('Xaritada')),
                  onPressed: s.lat == null ? null : onMap,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
