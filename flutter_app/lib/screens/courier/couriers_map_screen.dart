import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api.dart';
import '../auth/buyer_auth.dart';
import '../../l10n.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'courier_home.dart' show vehicleName, providerIcon;

/// "Kuryer yollash": yaqin atrofdagi onlayn kuryerlar xaritada (jonli joylashuv), profili va yollash
class CouriersMapScreen extends StatefulWidget {
  const CouriersMapScreen({super.key});
  @override
  State<CouriersMapScreen> createState() => _CouriersMapScreenState();
}

class _CouriersMapScreenState extends State<CouriersMapScreen>
    with SingleTickerProviderStateMixin {
  final ctrl = MapController();
  List<Courier> couriers = [];

  /// Server har 15 soniyada yangi nuqta beradi. Belgini shu zahoti ko'chirsak
  /// u sakrab yuradi, shuning uchun eski va yangi nuqta orasida silliq
  /// suriladi — harakat jonli ko'rinadi.
  late final AnimationController _move = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600))
    ..addListener(() {
      if (mounted) setState(() {});
    });
  final Map<String, LatLng> _from = {};

  /// Belgi hozir turgan (oraliq) nuqtasi
  LatLng _at(Courier c) {
    final to = LatLng(c.lat!, c.lon!);
    final from = _from[c.id];
    if (from == null || _move.value >= 1) return to;
    final t = Curves.easeInOut.transform(_move.value);
    return LatLng(from.latitude + (to.latitude - from.latitude) * t,
        from.longitude + (to.longitude - from.longitude) * t);
  }
  Courier? selected;
  LatLng? me;
  bool loading = true;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _t?.cancel();
    _move.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium)).timeout(const Duration(seconds: 8));
        me = LatLng(pos.latitude, pos.longitude);
        if (mounted) ctrl.move(me!, 13);
      }
    } catch (_) {}
    await load();
    // Kuryerlar harakatini jonli ko'rsatish: har 15 soniyada yangilanadi
    _t = Timer.periodic(const Duration(seconds: 15), (_) => load());
  }

  Future<void> load() async {
    try {
      final q = me == null ? '' : '?lat=${me!.latitude}&lon=${me!.longitude}';
      final r = await Api.instance.get('/api/couriers/nearby$q');
      // Yangi nuqtalar kelishidan oldin belgilar hozir qayerda turganini
      // eslab qolamiz — siljish shu joydan boshlanadi.
      final was = {
        for (final c in couriers)
          if (c.lat != null && c.lon != null) c.id: _at(c)
      };
      couriers = (r as List).map((e) => Courier.fromJson(e)).toList();
      _from
        ..clear()
        ..addAll(was);
      if (selected != null) selected = couriers.where((c) => c.id == selected!.id).firstOrNull ?? selected;
      if (_from.isNotEmpty) _move.forward(from: 0);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> hire(Courier c) => showHireCourierSheet(context, c, me: me);

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: ctrl,
          options: MapOptions(initialCenter: const LatLng(41.3111, 69.2797), initialZoom: 12, onTap: (_, __) => setState(() => selected = null)),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'uz.rydex.app'),
            MarkerLayer(markers: [
              if (me != null)
                Marker(point: me!, width: 22, height: 22, child: Container(decoration: BoxDecoration(color: const Color(0xFF2F80ED), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)))),
              for (final c in couriers.where((c) => c.lat != null && c.lon != null))
                Marker(
                  point: _at(c),
                  width: 56,
                  height: 66,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => selected = c);
                      ctrl.move(_at(c), ctrl.camera.zoom < 14 ? 14 : ctrl.camera.zoom);
                    },
                    child: Column(children: [
                      ProviderAvatar(photo: c.photo, icon: providerIcon(c), role: 'courier', size: selected?.id == c.id ? 50 : 44, online: true),
                      Icon(Icons.arrow_drop_down, color: selected?.id == c.id ? p.text : Colors.white, size: 20),
                    ]),
                  ),
                ),
            ]),
          ],
        ),
        Positioned(
          top: top + 10,
          left: 16,
          right: 16,
          child: Row(children: [
            IconBtn(Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop()),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16), boxShadow: softShadow(context, y: 4, blur: 14)),
                child: Text(loading ? tr('Kuryerlar qidirilmoqda...') : '${couriers.length} ${tr('ta kuryer onlayn')}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ),
            const SizedBox(width: 10),
            IconBtn(Icons.refresh_rounded, onTap: load),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 16 + bottom,
          child: selected != null
              ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _CourierCard(selected!, onHire: () => hire(selected!), onClose: () => setState(() => selected = null)))
              : couriers.isEmpty
                  ? (loading
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context)),
                            child: Row(children: [
                              Icon(Icons.local_shipping_outlined, color: p.muted),
                              const SizedBox(width: 12),
                              Expanded(child: Text(tr("Hozir yaqin atrofda onlayn kuryer yo'q. Birozdan so'ng qayta tekshiring."), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text))),
                            ]),
                          ),
                        ))
                  : SizedBox(
                      height: 112,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: couriers.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => _MiniCard(couriers[i], onTap: () {
                          setState(() => selected = couriers[i]);
                          if (couriers[i].lat != null) ctrl.move(LatLng(couriers[i].lat!, couriers[i].lon!), 14);
                        }),
                      ),
                    ),
        ),
      ]),
    );
  }
}

String _dist(double? km) => km == null ? '' : (km < 1 ? '${(km * 1000).round()} m' : '$km km');

/// Reyting o'rniga: haqiqiy yetkazishlar soni (0 bo'lsa "Yangi")
String _deliveriesText(Courier c) => c.deliveries > 0 ? '${c.deliveries} ${tr('yetkazish')}' : tr('Yangi');

class _MiniCard extends StatelessWidget {
  final Courier c;
  final VoidCallback onTap;
  const _MiniCard(this.c, {required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 210,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: softShadow(context)),
          child: Row(children: [
            ProviderAvatar(photo: c.photo, icon: providerIcon(c), role: 'courier', size: 44, online: true),
            const SizedBox(width: 10),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                Text('${vehicleName(c.vehicle)} · ${_dist(c.distanceKm)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
                Row(children: [
                  Icon(Icons.local_shipping_outlined, size: 13, color: p.muted),
                  const SizedBox(width: 4),
                  Expanded(child: Text(_deliveriesText(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.muted, fontWeight: FontWeight.w600))),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Kuryer profili kartasi: nom, transport, yetkazishlar soni, masofa, qo'ng'iroq va yollash
class _CourierCard extends StatelessWidget {
  final Courier c;
  final VoidCallback onHire;
  final VoidCallback onClose;
  const _CourierCard(this.c, {required this.onHire, required this.onClose});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 24, offset: const Offset(0, 10))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ProviderAvatar(photo: c.photo, icon: providerIcon(c), role: 'courier', size: 56, online: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: p.successSoft, borderRadius: BorderRadius.circular(99)), child: Text(tr('Onlayn'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: p.success))),
              ]),
              Text('${vehicleName(c.vehicle)}${c.distanceKm != null ? ' · ${_dist(c.distanceKm)}' : ''}', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
              GestureDetector(onTap: () => launchUrl(Uri.parse('tel:${c.phone}')), child: Row(children: [Icon(Icons.phone_rounded, size: 14, color: p.success), const SizedBox(width: 4), Text(c.phone, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.success))])),
              Row(children: [
                Icon(Icons.local_shipping_outlined, size: 14, color: p.muted),
                const SizedBox(width: 4),
                Text(_deliveriesText(c), style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
              ]),
              if (c.about.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.about, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.text.withValues(alpha: .8)))),
            ]),
          ),
          IconBtn(Icons.close_rounded, size: 34, bg: p.bg, onTap: onClose),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: p.successSoft, foregroundColor: p.success, side: BorderSide.none), icon: const Icon(Icons.phone_rounded, size: 18), label: Text(tr("Qo'ng'iroq")), onPressed: () => launchUrl(Uri.parse('tel:${c.phone}')))),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)), icon: const Icon(Icons.local_shipping_rounded, size: 18), label: Text(tr('Kuryerni yollash')), onPressed: onHire)),
        ]),
      ]),
    );
  }
}

/// Kuryerga to'g'ridan-to'g'ri so'rov formasi (xaritadan va Sofia chatidan ishlatiladi)
/// Yollash: do'kon buyurtmasi shart emas — qayerdan, qayerga, izoh va telefon yuboriladi, kuryer qo'ng'iroq qiladi
Future<void> showHireCourierSheet(BuildContext context, Courier c, {LatLng? me}) async {
  final ok = await showModalBottomSheet<bool>(
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HireSheet(courier: c, me: me),
  );
  if (ok == true && context.mounted) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (d) => AlertDialog(
        icon: Container(width: 56, height: 56, decoration: BoxDecoration(color: d.p.successSoft, borderRadius: BorderRadius.circular(18)), child: Icon(Icons.local_shipping_rounded, color: d.p.success, size: 28)),
        title: Text(tr("So'rov yuborildi!"), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        content: Text('${c.name} ${tr("siz bilan bog'lanadi. Telefoni")}: ${c.phone}', textAlign: TextAlign.center, style: TextStyle(color: d.p.muted)),
        actions: [
          OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('tel:${c.phone}')), icon: const Icon(Icons.phone_rounded, size: 16), label: Text(tr("Qo'ng'iroq"))),
          FilledButton(onPressed: () => Navigator.pop(d), child: Text(tr('Yopish'))),
        ],
      ),
    );
  }
}

class _HireSheet extends StatefulWidget {
  final Courier courier;
  final LatLng? me;
  const _HireSheet({required this.courier, this.me});
  @override
  State<_HireSheet> createState() => _HireSheetState();
}

class _HireSheetState extends State<_HireSheet> {
  final f = {for (final k in ['from', 'to', 'note', 'name', 'phone']) k: TextEditingController()};
  bool sending = false;
  String? err;

  @override
  void initState() {
    super.initState();
    f['name']!.text = Api.instance.userName == 'Xaridor' ? '' : Api.instance.userName;
    final me = widget.me;
    if (me != null) f['from']!.text = '${tr('Mening joyim')} (${me.latitude.toStringAsFixed(4)}, ${me.longitude.toStringAsFixed(4)})';
  }

  @override
  void dispose() {
    for (final x in f.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (sending) return;
    // Buyurtma berish uchun tasdiqlangan xaridor hisobi kerak
    if (!await ensureBuyer(context, title: tr('Buyurtma berish uchun kiring'))) return;
    if (!mounted) return;
    final c = widget.courier;
    setState(() {
      sending = true;
      err = null;
    });
    try {
      await Api.instance.post('/api/courier-requests', {'courierId': c.id, 'from': f['from']!.text, 'to': f['to']!.text, 'note': f['note']!.text, 'name': f['name']!.text, 'phone': f['phone']!.text});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // Xato oyna ichida ko'rsatiladi (bottom sheet ustida snackbar ko'rinmaydi)
      if (mounted) {
        setState(() {
          sending = false;
          err = e is ApiException ? e.message : tr("Serverga ulanib bo'lmadi. Internetni tekshiring.");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = widget.courier;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ProviderAvatar(photo: c.photo, icon: providerIcon(c), role: 'courier', size: 44, online: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Kuryerni yollash'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                Text('${c.name} · ${c.phone}', style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          TextField(controller: f['from'], decoration: InputDecoration(labelText: tr('Qayerdan olib ketsin'), prefixIcon: const Icon(Icons.trip_origin_rounded, size: 20))),
          const SizedBox(height: 10),
          TextField(controller: f['to'], decoration: InputDecoration(labelText: tr('Qayerga yetkazsin'), prefixIcon: const Icon(Icons.place_outlined, size: 20))),
          const SizedBox(height: 10),
          TextField(controller: f['note'], maxLines: 2, decoration: InputDecoration(labelText: tr('Nima yetkaziladi (izoh)'), prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20))),
          const SizedBox(height: 10),
          TextField(controller: f['name'], decoration: InputDecoration(labelText: tr('Ismingiz'), prefixIcon: const Icon(Icons.person_outline_rounded, size: 20))),
          const SizedBox(height: 10),
          TextField(controller: f['phone'], keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Telefon raqam'), hintText: '+998 90 123 45 67', prefixIcon: const Icon(Icons.phone_outlined, size: 20))),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: TextStyle(fontSize: 13, color: p.danger, fontWeight: FontWeight.w700))),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: sending ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.muted)) : const Icon(Icons.send_rounded, size: 18),
            label: Text(tr("So'rov yuborish")),
            onPressed: sending ? null : submit,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: p.successSoft, foregroundColor: p.success, side: BorderSide.none),
            icon: const Icon(Icons.phone_rounded, size: 18),
            label: Text('${tr("Qo'ng'iroq")}: ${c.phone}'),
            onPressed: () => launchUrl(Uri.parse('tel:${c.phone}')),
          ),
        ]),
      ),
    );
  }
}
