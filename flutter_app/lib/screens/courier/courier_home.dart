import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api.dart';
import '../../l10n.dart';
import '../../main.dart';
import '../../models.dart';
import '../../state.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../map_screen.dart';

/// Transport turi: belgi va nom
IconData vehicleIcon(String v) => switch (v) { 'bike' => Icons.pedal_bike_rounded, 'moto' => Icons.two_wheeler_rounded, 'car' => Icons.directions_car_rounded, _ => Icons.directions_walk_rounded };
String vehicleName(String v) => switch (v) { 'bike' => tr('Velosiped'), 'moto' => tr('Mototsikl'), 'car' => tr('Mashina'), _ => tr('Piyoda') };

/// Yuk mashinasi turi
const cargoVehicles = ['labo', 'damas', 'gazel', 'isuzu', 'fura'];
IconData cargoVehicleIcon(String v) => switch (v) { 'fura' => Icons.local_shipping_rounded, 'isuzu' => Icons.fire_truck_rounded, 'gazel' => Icons.airport_shuttle_rounded, _ => Icons.directions_car_filled_rounded };
String cargoVehicleName(String v) => switch (v) { 'labo' => 'Labo', 'damas' => 'Damas', 'gazel' => 'Gazel', 'isuzu' => 'Isuzu', 'fura' => 'Fura', _ => tr('Yuk mashinasi') };

/// Rol belgisi uchun: kuryer yoki yuk tashuvchi avatari
IconData providerIcon(Courier c) => c.isCargo ? cargoVehicleIcon(c.vehicleType) : vehicleIcon(c.vehicle);

/// Kuryer paneli: buyurtmalar, xarita (onlayn holat), profil
class CourierHome extends StatefulWidget {
  final VoidCallback onExit;
  const CourierHome({super.key, required this.onExit});
  @override
  State<CourierHome> createState() => _CourierHomeState();
}

class _CourierHomeState extends State<CourierHome> {
  int index = 0;
  final keys = List.generate(3, (_) => GlobalKey<NavigatorState>());
  Timer? _loc;

  @override
  void initState() {
    super.initState();
    if (AppState.instance.courier?.online == true) _startReporting();
  }

  @override
  void dispose() {
    _loc?.cancel();
    super.dispose();
  }

  /// Onlayn bo'lganda joylashuv har 15 soniyada serverga yuboriladi (xaridorlar xaritada ko'radi)
  void _startReporting() {
    _loc?.cancel();
    _report();
    _loc = Timer.periodic(const Duration(seconds: 15), (_) => _report());
  }

  Future<void> _report() async {
    final st = AppState.instance;
    if (st.courier == null || st.courier!.online != true) return;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)).timeout(const Duration(seconds: 12));
      await Api.instance.post('/api/courier/location', {'lat': pos.latitude, 'lon': pos.longitude, 'online': true});
      st.courier = st.courier!.copyWith(lat: pos.latitude, lon: pos.longitude);
      st.refresh();
    } catch (_) {}
  }

  Future<void> setOnline(bool v) async {
    final st = AppState.instance;
    if (st.courier == null) return;
    st.courier = st.courier!.copyWith(online: v);
    st.refresh();
    if (v) {
      _startReporting();
    } else {
      _loc?.cancel();
      try {
        await Api.instance.post('/api/courier/location', {'online': false});
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCargo = AppState.instance.courier?.isCargo == true;
    final roots = [if (isCargo) CargoOrdersTab(onExit: widget.onExit) else CourierOrdersTab(onExit: widget.onExit), CourierMapTab(onExit: widget.onExit, onOnline: setOnline), CourierProfileTab(onExit: widget.onExit, onOnline: setOnline)];
    final lk = L10n.lang.name;
    final pages = [for (var i = 0; i < roots.length; i++) TabNavigator(key: ValueKey('c$i$lk'), navKey: keys[i], root: roots[i])];
    return ListenableBuilder(
      listenable: AppState.instance,
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
          bottomNavigationBar: index == 1
              ? null
              : FloatingNav(
                  index: index,
                  onTap: (i) => i == index ? keys[i].currentState?.popUntil((r) => r.isFirst) : setState(() => index = i),
                  items: [
                    NavItem(Icons.local_shipping_outlined, Icons.local_shipping_rounded, isCargo ? tr('Yuklar') : tr('Yetkazish')),
                    NavItem(Icons.map_outlined, Icons.map_rounded, tr('Xarita')),
                    NavItem(Icons.person_outline_rounded, Icons.person_rounded, tr('Profil')),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Kuryer sahifalari sarlavhasi: onlayn tugmasi + xaridor rejimiga chiqish
class CourierHeader extends StatelessWidget {
  final String title;
  final VoidCallback onExit;
  final ValueChanged<bool>? onOnline;
  const CourierHeader(this.title, {super.key, required this.onExit, this.onOnline});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = AppState.instance.courier!;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 0),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c.name} · ${c.isCargo ? tr('yuk tashuvchi') : tr('kuryer')}', style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600)),
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.5)),
          ]),
        ),
        if (onOnline != null)
          GestureDetector(
            onTap: () => onOnline!(!c.online),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: c.online ? p.successSoft : p.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.online ? p.success : p.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: c.online ? p.success : p.muted, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(c.online ? tr('Onlayn') : tr('Oflayn'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.online ? p.success : p.muted)),
              ]),
            ),
          ),
        const SizedBox(width: 8),
        IconBtn(Icons.storefront_outlined, onTap: onExit),
      ]),
    );
  }
}

// ---- Yetkazish buyurtmalari ----
class CourierOrdersTab extends StatefulWidget {
  final VoidCallback onExit;
  const CourierOrdersTab({super.key, required this.onExit});
  @override
  State<CourierOrdersTab> createState() => _CourierOrdersTabState();
}

class _CourierOrdersTabState extends State<CourierOrdersTab> {
  List<Order> orders = [];
  List<CargoOrder> requests = []; // xaridorlarning to'g'ridan-to'g'ri so'rovlari
  bool loading = true;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    load();
    _t = Timer.periodic(const Duration(seconds: 20), (_) => load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await Api.instance.get('/api/courier/orders');
      orders = (r as List).map((e) => Order.fromJson(e)).toList();
      final q = await Api.instance.get('/api/courier/cargo');
      requests = (q as List).map((e) => CargoOrder.fromJson(e)).where((x) => x.kind == 'direct').toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> setRequestStatus(CargoOrder o, String status) async {
    try {
      await Api.instance.patch('/api/courier/cargo/${o.id}', {'status': status});
      if (status == 'done') {
        final c = AppState.instance.courier;
        if (c != null) AppState.instance.courier = c.copyWith(deliveries: c.deliveries + 1);
        AppState.instance.refresh();
      }
      await load();
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  Future<void> setStatus(Order o, String status) async {
    try {
      await Api.instance.patch('/api/courier/orders/${o.id}', {'status': status});
      if (status == 'delivered') {
        final c = AppState.instance.courier;
        if (c != null) AppState.instance.courier = c.copyWith(deliveries: c.deliveries + 1);
        AppState.instance.refresh();
      }
      await load();
      if (mounted) showToast(context, status == 'delivered' ? tr('Yetkazildi') : status == 'picked' ? tr('Buyurtma olindi') : tr('Rad etildi'));
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = orders.where((o) => o.deliveryStatus != 'delivered').toList();
    final done = orders.where((o) => o.deliveryStatus == 'delivered').toList();
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: EdgeInsets.zero, children: [
          CourierHeader(tr('Yetkazish'), onExit: widget.onExit),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, navPad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (loading)
                const Column(children: [Skeleton(height: 120, radius: 20), SizedBox(height: 10), Skeleton(height: 120, radius: 20)])
              else if (orders.isEmpty && requests.isEmpty)
                EmptyBox(Icons.local_shipping_outlined, tr("Hozircha buyurtma yo'q.\nOnlayn bo'ling — xaridorlar sizni xaritada ko'radi."))
              else ...[
                if (requests.where((r) => r.status != 'done' && r.status != 'rejected').isNotEmpty) ...[
                  SectionTitle(tr("So'rovlar")),
                  for (final r in requests.where((r) => r.status != 'done' && r.status != 'rejected')) _RequestCard(r, onStatus: (s) => setRequestStatus(r, s)),
                ],
                if (active.isNotEmpty) ...[
                  SectionTitle(tr('Faol')),
                  for (final o in active) _OrderCard(o, onStatus: (s) => setStatus(o, s)),
                ],
                if (done.isNotEmpty) ...[
                  SectionTitle(tr('Yetkazilgan')),
                  for (final o in done) _OrderCard(o, onStatus: (s) => setStatus(o, s)),
                ],
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order o;
  final ValueChanged<String> onStatus;
  const _OrderCard(this.o, {required this.onStatus});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final st = o.deliveryStatus ?? 'assigned';
    final label = switch (st) { 'picked' => tr("Yo'lda"), 'delivered' => tr('Yetkazildi'), _ => tr('Yangi') };
    final color = switch (st) { 'picked' => p.accentText, 'delivered' => p.success, _ => const Color(0xFF2F80ED) };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)), child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11))),
          const Spacer(),
          Text(fmtTime(o.createdAt), style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Text(o.productName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 2),
        Row(children: [Expanded(child: Text('${o.shopName} · ${o.customerName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600))), PriceText(o.price, size: 13)]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Small(Icons.phone_outlined, tr('Xaridor'), () => launchUrl(Uri.parse('tel:${o.phone}'))),
          if (o.shopPhone.isNotEmpty) _Small(Icons.storefront_outlined, tr("Do'kon"), () => launchUrl(Uri.parse('tel:${o.shopPhone}'))),
          if (o.shopLat != null)
            _Small(Icons.map_outlined, tr('Xaritada'), () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => MapScreen(focus: [Shop(id: '', name: o.shopName, sellerName: '', phone: o.shopPhone, lat: o.shopLat, lon: o.shopLon)])))),
        ]),
        if (st != 'delivered') ...[
          const SizedBox(height: 10),
          Row(children: [
            if (st == 'assigned') ...[
              Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42), foregroundColor: p.danger), onPressed: () => onStatus('rejected'), child: Text(tr('Rad etish')))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(0, 42)), icon: const Icon(Icons.inventory_2_outlined, size: 16), label: Text(tr('Buyurtmani oldim')), onPressed: () => onStatus('picked'))),
            ] else
              Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(0, 42), backgroundColor: p.success, foregroundColor: Colors.white), icon: const Icon(Icons.check_rounded, size: 18), label: Text(tr('Yetkazdim')), onPressed: () => onStatus('delivered'))),
          ]),
        ],
      ]),
    );
  }
}

/// Xaridorning to'g'ridan-to'g'ri so'rovi (do'kon buyurtmasisiz)
class _RequestCard extends StatelessWidget {
  final CargoOrder o;
  final ValueChanged<String> onStatus;
  const _RequestCard(this.o, {required this.onStatus});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (label, color) = switch (o.status) { 'accepted' => (tr('Qabul qilindi'), p.success), _ => (tr('Yangi'), const Color(0xFF2F80ED)) };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: Border.all(color: p.accent.withValues(alpha: .6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)), child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11))),
          const Spacer(),
          Text(fmtTime(o.createdAt), style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Text(o.customerName.isNotEmpty ? o.customerName : tr('Xaridor'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        if (o.fromRegion.isNotEmpty) Text('${tr('Qayerdan')}: ${o.fromRegion}', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
        if (o.toRegion.isNotEmpty) Text('${tr('Qayerga')}: ${o.toRegion}', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
        if (o.cargo.isNotEmpty) Text(o.cargo, style: TextStyle(fontSize: 13, color: p.text.withValues(alpha: .85))),
        const SizedBox(height: 10),
        Row(children: [
          OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42), backgroundColor: p.successSoft, foregroundColor: p.success, side: BorderSide.none), icon: const Icon(Icons.phone_rounded, size: 16), label: Text(o.phone), onPressed: () => launchUrl(Uri.parse('tel:${o.phone}'))),
          const SizedBox(width: 8),
          if (o.status == 'new') ...[
            Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42), foregroundColor: p.danger), onPressed: () => onStatus('rejected'), child: Text(tr('Rad etish')))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 42)), onPressed: () => onStatus('accepted'), child: Text(tr('Qabul qilish')))),
          ] else
            Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(0, 42), backgroundColor: p.success, foregroundColor: Colors.white), icon: const Icon(Icons.check_rounded, size: 18), label: Text(tr('Yetkazdim')), onPressed: () => onStatus('done'))),
        ]),
      ]),
    );
  }
}

class _Small extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  const _Small(this.icon, this.text, this.onTap);
  @override
  Widget build(BuildContext context) => Material(
        color: context.p.bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: context.p.accentText), const SizedBox(width: 6), Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))])),
        ),
      );
}

// ---- Kuryer xaritasi: mening joyim, onlayn holat ----
class CourierMapTab extends StatefulWidget {
  final VoidCallback onExit;
  final ValueChanged<bool> onOnline;
  const CourierMapTab({super.key, required this.onExit, required this.onOnline});
  @override
  State<CourierMapTab> createState() => _CourierMapTabState();
}

class _CourierMapTabState extends State<CourierMapTab> {
  final ctrl = MapController();
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = AppState.instance.courier!;
    final me = c.lat != null ? LatLng(c.lat!, c.lon!) : null;
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: ctrl,
          options: MapOptions(initialCenter: me ?? const LatLng(41.3111, 69.2797), initialZoom: me == null ? 12 : 15),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'uz.saler.ai'),
            if (me != null)
              MarkerLayer(markers: [
                Marker(
                  point: me,
                  width: 56,
                  height: 56,
                  child: ProviderAvatar(photo: c.photo, icon: providerIcon(c), role: c.isCargo ? 'cargo' : 'courier', size: 50, online: c.online),
                ),
              ]),
          ],
        ),
        Positioned(
          top: top + 10,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .15), blurRadius: 20, offset: const Offset(0, 8))]),
            child: Row(children: [
              ProviderAvatar(photo: c.photo, icon: providerIcon(c), role: c.isCargo ? 'cargo' : 'courier', size: 44, online: c.online),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.online ? tr('Siz onlaynsiz') : tr('Siz oflaynsiz'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text(c.online ? tr("Xaridorlar sizni xaritada ko'radi") : tr('Buyurtma olish uchun onlayn bo\'ling'), style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
                ]),
              ),
              Switch(value: c.online, activeColor: p.success, onChanged: widget.onOnline),
            ]),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 24 + MediaQuery.of(context).padding.bottom,
          child: Column(children: [
            FloatingActionButton.small(heroTag: 'c-me', backgroundColor: p.card, foregroundColor: p.accentText, onPressed: () => me == null ? null : ctrl.move(me, 15), child: const Icon(Icons.my_location_rounded)),
            const SizedBox(height: 10),
            FloatingActionButton.small(heroTag: 'c-exit', backgroundColor: p.card, foregroundColor: p.text, onPressed: widget.onExit, child: const Icon(Icons.storefront_outlined)),
          ]),
        ),
        // Pastki panelga qaytish uchun kichik tugma (xarita tabida panel yashirin)
        Positioned(
          left: 16,
          bottom: 24 + MediaQuery.of(context).padding.bottom,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 14), backgroundColor: p.dark, foregroundColor: p.onDark),
            icon: const Icon(Icons.local_shipping_outlined, size: 18),
            label: Text(tr('Buyurtmalar')),
            onPressed: () => context.findAncestorStateOfType<_CourierHomeState>()?.setState(() => context.findAncestorStateOfType<_CourierHomeState>()!.index = 0),
          ),
        ),
      ]),
    );
  }
}

// ---- Profil ----
class CourierProfileTab extends StatelessWidget {
  final VoidCallback onExit;
  final ValueChanged<bool> onOnline;
  const CourierProfileTab({super.key, required this.onExit, required this.onOnline});

  /// Profil rasmi: galereyadan tanlab, serverga yuboriladi
  Future<void> _photo(BuildContext context) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, imageQuality: 85);
    if (f == null) return;
    try {
      final r = await Api.instance.put('/api/courier/profile', {'photo': 'data:image/jpeg;base64,${base64Encode(await f.readAsBytes())}'});
      AppState.instance.courier = Courier.fromJson(r['courier']).copyWith(online: AppState.instance.courier?.online);
      AppState.instance.refresh();
    } catch (e) {
      if (context.mounted) showToast(context, e.toString(), error: true);
    }
  }

  Future<void> _edit(BuildContext context) async {
    final c = AppState.instance.courier!;
    final f = {for (final e in {'name': c.name, 'phone': c.phone, 'email': c.email, 'about': c.about, 'capacity': c.capacityKg > 0 ? '${c.capacityKg}' : '', 'base': c.basePrice > 0 ? '${c.basePrice}' : '', 'km': c.pricePerKm > 0 ? '${c.pricePerKm}' : ''}.entries) e.key: TextEditingController(text: e.value)};
    var vehicle = c.vehicle;
    var vehicleType = c.vehicleType;
    final regions = List<String>.from(c.regions);
    List<String> allRegions = [];
    try {
      allRegions = ((await Api.instance.get('/api/cargo/regions')) as List).cast<String>();
    } catch (_) {}
    if (!context.mounted) return;
    await showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Profilni tahrirlash'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
            const SizedBox(height: 12),
            TextField(controller: f['name'], decoration: InputDecoration(labelText: tr('Ism'))),
            const SizedBox(height: 10),
            TextField(controller: f['phone'], keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Telefon'))),
            const SizedBox(height: 10),
            TextField(controller: f['email'], keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 10),
            TextField(controller: f['about'], maxLines: 2, decoration: InputDecoration(labelText: tr("O'zingiz haqingizda"))),
            const SizedBox(height: 12),
            if (c.isCargo) ...[
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final v in cargoVehicles)
                  ChoiceChip(selected: vehicleType == v, avatar: Icon(cargoVehicleIcon(v), size: 16, color: vehicleType == v ? ctx.p.onDark : ctx.p.text), label: Text(cargoVehicleName(v)), onSelected: (_) => setS(() => vehicleType = v)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: f['capacity'], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr("Sig'im, kg")))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: f['base'], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr("Boshlang'ich narx")))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: f['km'], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('so\'m/km')))),
              ]),
              const SizedBox(height: 10),
              Text(tr('Xizmat viloyatlari'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ctx.p.muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in allRegions)
                  FilterChip(selected: regions.contains(r), label: Text(r, style: const TextStyle(fontSize: 12)), onSelected: (v) => setS(() => v ? regions.add(r) : regions.remove(r))),
              ]),
            ] else
              Wrap(spacing: 8, children: [
                for (final v in ['foot', 'bike', 'moto', 'car'])
                  ChoiceChip(selected: vehicle == v, avatar: Icon(vehicleIcon(v), size: 16, color: vehicle == v ? ctx.p.onDark : ctx.p.text), label: Text(vehicleName(v)), onSelected: (_) => setS(() => vehicle = v)),
              ]),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                try {
                  final r = await Api.instance.put('/api/courier/profile', {
                    'name': f['name']!.text,
                    'phone': f['phone']!.text,
                    'email': f['email']!.text,
                    'about': f['about']!.text,
                    'vehicle': vehicle,
                    if (c.isCargo) 'vehicleType': vehicleType,
                    if (c.isCargo) 'capacityKg': int.tryParse(f['capacity']!.text) ?? 0,
                    if (c.isCargo) 'basePrice': int.tryParse(f['base']!.text) ?? 0,
                    if (c.isCargo) 'pricePerKm': int.tryParse(f['km']!.text) ?? 0,
                    if (c.isCargo) 'regions': regions,
                  });
                  AppState.instance.courier = Courier.fromJson(r['courier']).copyWith(online: c.online);
                  AppState.instance.refresh();
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) showToast(ctx, e.toString(), error: true);
                }
              },
              child: Text(tr('Saqlash')),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final st = AppState.instance;
    final c = st.courier!;
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        CourierHeader(tr('Profil'), onExit: onExit, onOnline: onOnline),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, navPad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(22), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
              child: Column(children: [
                GestureDetector(onTap: () => _photo(context), child: ProviderAvatar(photo: c.photo, icon: providerIcon(c), role: c.isCargo ? 'cargo' : 'courier', size: 84, online: c.online)),
                const SizedBox(height: 8),
                TextButton.icon(onPressed: () => _photo(context), icon: const Icon(Icons.photo_camera_outlined, size: 16), label: Text(c.photo == null ? tr('Rasm qo\'yish') : tr("Rasmni o'zgartirish"))),
                Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.3)),
                Text('${c.isCargo ? '${cargoVehicleName(c.vehicleType)}${c.capacityKg > 0 ? ' · ${c.capacityKg} kg' : ''}' : vehicleName(c.vehicle)} · ${c.phone}${c.email.isNotEmpty ? ' · ${c.email}' : ''}', textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 13)),
                if (c.isCargo && c.regions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [for (final r in c.regions) Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(99)), child: Text(r, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)))])),
                if (c.isCargo && (c.basePrice > 0 || c.pricePerKm > 0)) Padding(padding: const EdgeInsets.only(top: 6), child: Text([if (c.basePrice > 0) '${tr('dan')} ${fmtPrice(c.basePrice)} so\'m', if (c.pricePerKm > 0) '${fmtPrice(c.pricePerKm)} so\'m/km'].join(' · '), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.accentText))),
                if (c.about.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.about, textAlign: TextAlign.center, style: TextStyle(color: p.text.withValues(alpha: .8), fontSize: 13, height: 1.4))),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _Stat(c.isCargo ? tr('Reyslar') : tr('Yetkazilgan'), '${c.deliveries}', Icons.local_shipping_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat(tr('Reyting'), c.rating.toStringAsFixed(1), Icons.star_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat(tr('Holat'), c.online ? tr('Onlayn') : tr('Oflayn'), c.online ? Icons.wifi_rounded : Icons.wifi_off_rounded)),
                ]),
                const SizedBox(height: 12),
                OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: p.bg, side: BorderSide.none), icon: const Icon(Icons.edit_outlined, size: 16), label: Text(tr('Profilni tahrirlash')), onPressed: () => _edit(context)),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
              child: Column(children: [
                ListTile(leading: Icon(Icons.translate_rounded, color: p.accentText), title: Text(tr('Til'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)), subtitle: Text('${L10n.flags[L10n.lang]} ${L10n.names[L10n.lang]}', style: TextStyle(fontSize: 12, color: p.muted)), trailing: Icon(Icons.chevron_right_rounded, color: p.muted), onTap: () => showLangSheet(context)),
                ListTile(leading: Icon(Icons.storefront_outlined, color: p.accentText), title: Text(tr('Xaridor rejimi'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)), trailing: Icon(Icons.chevron_right_rounded, color: p.muted), onTap: onExit),
                ListTile(
                  leading: Icon(Icons.logout_rounded, color: p.danger),
                  title: Text(tr('Chiqish'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.danger)),
                  onTap: () async {
                    if (!await confirmDialog(context, tr('Kuryer akkauntidan chiqasizmi?'), ok: tr('Chiqish'))) return;
                    try {
                      await Api.instance.post('/api/courier/logout');
                    } catch (_) {}
                    st.courier = null;
                    st.refresh();
                    onExit();
                  },
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Stat(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: context.p.bg, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Icon(icon, size: 18, color: context.p.accentText),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          Text(label, style: TextStyle(fontSize: 11, color: context.p.muted, fontWeight: FontWeight.w600)),
        ]),
      );
}


// ---- Yuk tashuvchi: viloyatlararo yuk buyurtmalari ----
class CargoOrdersTab extends StatefulWidget {
  final VoidCallback onExit;
  const CargoOrdersTab({super.key, required this.onExit});
  @override
  State<CargoOrdersTab> createState() => _CargoOrdersTabState();
}

class _CargoOrdersTabState extends State<CargoOrdersTab> {
  List<CargoOrder> orders = [];
  bool loading = true;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    load();
    _t = Timer.periodic(const Duration(seconds: 20), (_) => load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await Api.instance.get('/api/courier/cargo');
      orders = (r as List).map((e) => CargoOrder.fromJson(e)).toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> setStatus(CargoOrder o, String status) async {
    try {
      await Api.instance.patch('/api/courier/cargo/${o.id}', {'status': status});
      if (status == 'done') {
        final c = AppState.instance.courier;
        if (c != null) AppState.instance.courier = c.copyWith(deliveries: c.deliveries + 1);
        AppState.instance.refresh();
      }
      await load();
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: EdgeInsets.zero, children: [
          CourierHeader(tr('Yuklar'), onExit: widget.onExit),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, navPad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (loading)
                const Column(children: [Skeleton(height: 130, radius: 20), SizedBox(height: 10), Skeleton(height: 130, radius: 20)])
              else if (orders.isEmpty)
                EmptyBox(Icons.local_shipping_outlined, tr("Hozircha yuk buyurtmasi yo'q.\nProfilingizda viloyatlar va narxni to'ldiring — mijozlar sizni topadi."))
              else
                for (final o in orders)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Builder(builder: (_) {
                          final (label, color) = switch (o.status) { 'accepted' => (tr('Qabul qilindi'), p.success), 'done' => (tr('Yetkazildi'), p.success), 'rejected' => (tr('Rad etildi'), p.danger), _ => (tr('Yangi'), const Color(0xFF2F80ED)) };
                          return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)), child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11)));
                        }),
                        const Spacer(),
                        Text(fmtTime(o.createdAt), style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 8),
                      Text('${o.fromRegion} → ${o.toRegion}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text([if (o.cargo.isNotEmpty) o.cargo, if (o.weightKg > 0) '${o.weightKg} kg', if (o.date.isNotEmpty) o.date].join(' · '), style: TextStyle(fontSize: 13, color: p.text.withValues(alpha: .85), fontWeight: FontWeight.w600)),
                      if (o.address.isNotEmpty) Text(o.address, style: TextStyle(fontSize: 12, color: p.muted)),
                      Text('${o.customerName} · ${o.phone}', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      Row(children: [
                        IconBtn(Icons.phone_outlined, size: 42, bg: p.successSoft, color: p.success, onTap: () => launchUrl(Uri.parse('tel:${o.phone}'))),
                        const SizedBox(width: 8),
                        if (o.status == 'new') ...[
                          Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42), foregroundColor: p.danger), onPressed: () => setStatus(o, 'rejected'), child: Text(tr('Rad etish')))),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 42)), onPressed: () => setStatus(o, 'accepted'), child: Text(tr('Qabul qilish')))),
                        ] else if (o.status == 'accepted')
                          Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(0, 42), backgroundColor: p.success, foregroundColor: Colors.white), icon: const Icon(Icons.check_rounded, size: 18), label: Text(tr('Yetkazdim')), onPressed: () => setStatus(o, 'done'))),
                      ]),
                    ]),
                  ),
            ]),
          ),
        ]),
      ),
    );
  }
}
