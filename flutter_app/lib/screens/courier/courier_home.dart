import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api.dart';
import '../../photo.dart';
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

/// 0.45 -> "450 m", 3.26 -> "3.3 km", 124.6 -> "125 km"
String fmtKm(num km) {
  if (km > 0 && km < 1) return '${(km * 1000).round()} m';
  if (km < 10 && km != km.roundToDouble()) return '${km.toStringAsFixed(1)} km';
  return '${km.round()} km';
}

// ---- Umumiy yordamchilar ----

/// Xato matni: server xabari (ApiException) yoki umumiy matn
String _errText(Object e) => e is ApiException ? e.message : tr("Serverga ulanib bo'lmadi. Internetni tekshiring.");

int _n(dynamic v) => v is num ? v.round() : 0;
double? _d(dynamic v) => v is num ? v.toDouble() : null;
Map _map(dynamic v) => v is Map ? v : const {};
List<Map> _list(dynamic v) => v is List ? v.whereType<Map>().toList() : const [];

Color _amber(BuildContext c) => c.isDark ? const Color(0xFFFFB547) : const Color(0xFFA86F00);
Color _violet(BuildContext c) => c.isDark ? const Color(0xFF9D86FF) : const Color(0xFF7C5CFF);
const _blue = Color(0xFF2F80ED);

Widget _spinner(Color c, {double size = 16}) => SizedBox(width: size, height: size, child: CircularProgressIndicator(strokeWidth: 2, color: c));

/// Google Maps'da yo'l ko'rsatish (tashqi ilovada ochiladi)
Future<void> _openDirections(BuildContext context, double? lat, double? lon) async {
  if (lat == null || lon == null) return;
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon'), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) showToast(context, tr("Xaritani ochib bo'lmadi"), error: true);
}

/// Kuryer paneli: buyurtmalar, daromad/statistika, xarita (onlayn holat), profil
class CourierHome extends StatefulWidget {
  final VoidCallback onExit;
  const CourierHome({super.key, required this.onExit});
  @override
  State<CourierHome> createState() => _CourierHomeState();
}

class _CourierHomeState extends State<CourierHome> {
  int index = 0;
  final keys = List.generate(4, (_) => GlobalKey<NavigatorState>());
  final pager = PageController();
  // Daromad tabi ochilganda statistikani yangilash signali
  final _statsTick = ValueNotifier<int>(0);
  Timer? _loc;

  @override
  void initState() {
    super.initState();
    if (AppState.instance.courier?.online == true) _startReporting();
  }

  @override
  void dispose() {
    _loc?.cancel();
    _statsTick.dispose();
    pager.dispose();
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

  void _onTab(int i) {
    if (i == index) {
      keys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    if (i == 1) _statsTick.value++;
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
    final isCargo = AppState.instance.courier?.isCargo == true;
    final roots = [
      if (isCargo) CargoOrdersTab(onExit: widget.onExit) else CourierOrdersTab(onExit: widget.onExit),
      CourierStatsTab(onExit: widget.onExit, refresh: _statsTick),
      CourierMapTab(onExit: widget.onExit, onOnline: setOnline),
      CourierProfileTab(onExit: widget.onExit, onOnline: setOnline),
    ];
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
          body: PageView(
            controller: pager,
            // Xarita tabida yonga surish xaritaning o'ziga tegishli
            physics: index == 2 ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
            onPageChanged: (i) {
              if (i == index) return;
              if (i == 1) _statsTick.value++;
              setState(() => index = i);
            },
            children: [for (final page in pages) KeepAlivePage(child: page)],
          ),
          // Xarita tabida panel yashirinadi
          bottomNavigationBar: index == 2
              ? null
              : FloatingNav(
                  index: index,
                  onTap: _onTab,
                  items: [
                    NavItem(Icons.local_shipping_outlined, Icons.local_shipping_rounded, isCargo ? tr('Yuklar') : tr('Yetkazish')),
                    if (isCargo)
                      NavItem(Icons.insights_outlined, Icons.insights_rounded, tr('Statistika'))
                    else
                      NavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, tr('Daromad')),
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

// ---- Kichik umumiy vidjetlar ----

/// Kartochka: 20 radius, yumshoq soya (ichida InkWell effekti ko'rinishi uchun shaffof Material)
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  const _Card({required this.child, this.padding = const EdgeInsets.all(14), this.borderColor});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: softShadow(context),
        border: borderColor != null ? Border.all(color: borderColor!) : (context.isDark ? Border.all(color: p.border) : null),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// Bo'lim sarlavhasi (ikonka + nom + ixtiyoriy izoh) va kontenti
class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final Widget child;
  const _Section(this.icon, this.title, {this.hint, required this.child});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 17, color: p.text),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -.2))),
          ]),
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint!, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600))),
        ]),
      ),
      child,
    ]);
  }
}

/// Kichik belgi: ikonka + matn (masofa, narx, holat)
class _Pill extends StatelessWidget {
  final IconData? icon;
  final String text;
  final Color color;
  final Color? bg;
  const _Pill(this.icon, this.text, this.color, {this.bg});
  // Text.rich: Row ichida (cheklanmagan kenglik) ham, Wrap ichida (uzun matn — "...") ham to'g'ri ishlaydi
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: bg ?? color.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)),
        child: Text.rich(
          TextSpan(children: [
            if (icon != null) WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(icon, size: 13, color: color))),
            TextSpan(text: text),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5),
        ),
      );
}

/// To'liq xato holati: xabar va "Qayta urinish" tugmasi
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState(this.message, {required this.onRetry});
  @override
  Widget build(BuildContext context) => EmptyBox(
        Icons.cloud_off_rounded,
        message,
        action: FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(tr('Qayta urinish'))),
      );
}

/// Ma'lumot bor, lekin yangilab bo'lmadi — ro'yxat ustida kichik ogohlantirish
class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _InlineError(this.message, {required this.onRetry});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(color: p.danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(Icons.cloud_off_rounded, size: 18, color: p.danger),
        const SizedBox(width: 8),
        Expanded(child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text))),
        TextButton(onPressed: onRetry, child: Text(tr('Qayta urinish'))),
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
  String? error;
  final busy = <String>{}; // so'rov ketayotgan buyurtmalar — tugmalar vaqtincha o'chadi
  Timer? _t;

  // Optimal marshrut
  List<_Stop> stops = [];
  double? totalKm;
  bool planLoading = false;
  String? planError;
  String _planKey = '';

  @override
  void initState() {
    super.initState();
    load();
    _t = Timer.periodic(const Duration(seconds: 20), (_) => load());
    AppState.instance.addListener(_onLive);
  }

  @override
  void dispose() {
    _t?.cancel();
    AppState.instance.removeListener(_onLive);
    super.dispose();
  }

  // Yangi buyurtma biriktirilsa, bekor qilinsa yoki so'rov kelsa ro'yxat joyida yangilanadi
  int _seenLive = AppState.instance.liveVersion;
  void _onLive() {
    final st = AppState.instance;
    if (st.liveVersion == _seenLive) return;
    _seenLive = st.liveVersion;
    final t = st.lastEvent?.type ?? '';
    if (t.startsWith('order:') || t.startsWith('cargo:')) load(force: true);
  }

  /// Faol buyurtmalar: yangi (assigned) va yo'lda (picked)
  List<Order> get active => orders.where((o) => const {'assigned', 'picked'}.contains(o.deliveryStatus ?? 'assigned')).toList();

  Future<void> load({bool force = false}) async {
    try {
      final r = await Future.wait([Api.instance.get('/api/courier/orders'), Api.instance.get('/api/courier/cargo')]);
      orders = (r[0] as List).map((e) => Order.fromJson(e)).toList();
      requests = (r[1] as List).map((e) => CargoOrder.fromJson(e)).where((x) => x.kind == 'direct').toList();
      error = null;
    } catch (e) {
      error = _errText(e);
    }
    if (!mounted) return;
    setState(() => loading = false);
    _syncPlan(force: force);
  }

  /// Marshrut faqat faol buyurtmalar o'zgarganda (yoki qo'lda yangilaganda) qayta so'raladi
  void _syncPlan({bool force = false}) {
    final act = active;
    if (act.isEmpty) {
      _planKey = '';
      if (stops.isNotEmpty || planError != null) {
        setState(() {
          stops = [];
          totalKm = null;
          planError = null;
        });
      }
      return;
    }
    final key = act.map((o) => '${o.id}:${o.deliveryStatus}').join(',');
    if (!force && key == _planKey && planError == null) return;
    _planKey = key;
    loadPlan();
  }

  Future<void> loadPlan() async {
    if (planLoading) return;
    setState(() {
      planLoading = true;
      planError = null;
    });
    // Kuryerning oxirgi ma'lum joylashuvi (bo'lmasa — serverga yuborilgan oxirgi nuqta)
    double? lat, lon;
    try {
      final pos = await Geolocator.getLastKnownPosition().timeout(const Duration(seconds: 3));
      lat = pos?.latitude;
      lon = pos?.longitude;
    } catch (_) {}
    final me = AppState.instance.courier;
    if (lat == null || lon == null) {
      lat = me?.lat;
      lon = me?.lon;
    }
    try {
      final r = _map(await Api.instance.get('/api/courier/route-plan${lat != null && lon != null ? '?lat=$lat&lon=$lon' : ''}'));
      stops = _list(r['stops']).map(_Stop.fromJson).toList();
      totalKm = _d(r['totalKm']);
    } catch (e) {
      planError = _errText(e);
    }
    if (mounted) setState(() => planLoading = false);
  }

  void _incDeliveries() {
    final c = AppState.instance.courier;
    if (c != null) AppState.instance.courier = c.copyWith(deliveries: c.deliveries + 1);
    AppState.instance.refresh();
  }

  Future<void> setRequestStatus(CargoOrder o, String status) async {
    if (busy.contains(o.id)) return;
    setState(() => busy.add(o.id));
    try {
      await Api.instance.patch('/api/courier/cargo/${o.id}', {'status': status});
      if (status == 'done') _incDeliveries();
      await load();
    } catch (e) {
      if (mounted) showToast(context, _errText(e), error: true);
      if (e is ApiException && e.status == 409) await load(); // holat eskirgan — ro'yxatni yangilaymiz
    } finally {
      if (mounted) setState(() => busy.remove(o.id));
    }
  }

  Future<void> setStatus(Order o, String status) async {
    if (busy.contains(o.id)) return;
    setState(() => busy.add(o.id));
    try {
      await Api.instance.patch('/api/courier/orders/${o.id}', {'status': status});
      if (status == 'delivered') _incDeliveries();
      await load();
      if (mounted) showToast(context, status == 'delivered' ? tr('Yetkazildi') : status == 'picked' ? tr('Buyurtma olindi') : tr('Rad etildi'));
    } catch (e) {
      if (mounted) showToast(context, _errText(e), error: true);
      if (e is ApiException && e.status == 409) await load();
    } finally {
      if (mounted) setState(() => busy.remove(o.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final act = active;
    final done = orders.where((o) => o.deliveryStatus == 'delivered').toList();
    final openReq = requests.where((r) => r.status == 'new' || r.status == 'accepted').toList();
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => load(force: true),
        child: ListView(padding: EdgeInsets.zero, children: [
          CourierHeader(tr('Yetkazish'), onExit: widget.onExit),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, navPad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (loading)
                const Column(children: [Skeleton(height: 120, radius: 20), SizedBox(height: 10), Skeleton(height: 120, radius: 20)])
              else if (error != null && orders.isEmpty && requests.isEmpty)
                _ErrorState(error!, onRetry: () {
                  setState(() => loading = true);
                  load(force: true);
                })
              else ...[
                if (error != null) _InlineError(error!, onRetry: () => load(force: true)),
                if (act.isNotEmpty) _RoutePlanCard(stops: stops, totalKm: totalKm, loading: planLoading, error: planError, onRefresh: loadPlan),
                if (openReq.isNotEmpty) ...[
                  SectionTitle(tr("So'rovlar")),
                  for (final r in openReq) _RequestCard(r, busy: busy.contains(r.id), onStatus: (s) => setRequestStatus(r, s)),
                ],
                if (act.isNotEmpty) ...[
                  SectionTitle(tr('Faol')),
                  for (final o in act) _OrderCard(o, busy: busy.contains(o.id), onStatus: (s) => setStatus(o, s)),
                ],
                // Faol ish yo'q bo'lsa ham ekran bo'sh qolmasin
                if (act.isEmpty && openReq.isEmpty)
                  EmptyBox(
                    Icons.local_shipping_outlined,
                    orders.isEmpty && requests.isEmpty ? tr("Hozircha buyurtma yo'q.\nOnlayn bo'ling — xaridorlar sizni xaritada ko'radi.") : tr("Hozircha faol buyurtma yo'q.\nYangi buyurtmalar shu yerda paydo bo'ladi."),
                  ),
                if (done.isNotEmpty) ...[
                  SectionTitle(tr('Yetkazilgan')),
                  for (final o in done) _OrderCard(o, onStatus: (_) {}),
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
  final bool busy;
  final ValueChanged<String> onStatus;
  const _OrderCard(this.o, {required this.onStatus, this.busy = false});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final st = o.deliveryStatus ?? 'assigned';
    final label = switch (st) { 'picked' => tr("Yo'lda"), 'delivered' => tr('Yetkazildi'), _ => tr('Yangi') };
    final color = switch (st) { 'picked' => p.accentText, 'delivered' => p.success, _ => _blue };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Pill(null, label, color),
          const Spacer(),
          Text(fmtTime(o.deliveredAt ?? o.createdAt), style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Text(o.productName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 2),
        Row(children: [Expanded(child: Text('${o.shopName} · ${o.customerName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600))), PriceText(o.price, size: 13)]),
        // Xaridor manzili
        if (o.address.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.place_outlined, size: 15, color: p.muted)),
            const SizedBox(width: 4),
            Expanded(child: Text(o.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.text.withValues(alpha: .85), fontWeight: FontWeight.w600))),
          ]),
        ],
        if (o.routeKm != null || o.deliveryFee != null) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (o.routeKm != null) _Pill(Icons.route_rounded, fmtKm(o.routeKm!), p.text, bg: p.bg),
            if (o.deliveryFee != null) _Pill(Icons.payments_outlined, "${tr('Yetkazish haqi')}: ${fmtPrice(o.deliveryFee!)} so'm", p.success, bg: p.successSoft),
          ]),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          // Navigatsiya: yangi buyurtmada do'konga, olingandan keyin xaridorga
          if (st == 'assigned' && o.shopLat != null && o.shopLon != null) _Small(Icons.navigation_rounded, tr("Do'konga yo'l"), () => _openDirections(context, o.shopLat, o.shopLon), accent: true),
          if (st == 'picked' && o.hasLocation) _Small(Icons.navigation_rounded, tr("Xaridorga yo'l"), () => _openDirections(context, o.lat, o.lon), accent: true),
          _Small(Icons.phone_outlined, tr('Xaridor'), () => launchUrl(Uri.parse('tel:${o.phone}'))),
          if (o.shopPhone.isNotEmpty) _Small(Icons.storefront_outlined, tr("Do'kon"), () => launchUrl(Uri.parse('tel:${o.shopPhone}'))),
          if (o.shopLat != null)
            _Small(Icons.map_outlined, tr('Xaritada'), () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => MapScreen(focus: [Shop(id: '', name: o.shopName, sellerName: '', phone: o.shopPhone, lat: o.shopLat, lon: o.shopLon)])))),
        ]),
        if (st == 'assigned' || st == 'picked') ...[
          const SizedBox(height: 10),
          Row(children: [
            if (st == 'assigned') ...[
              Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42), foregroundColor: p.danger), onPressed: busy ? null : () => onStatus('rejected'), child: Text(tr('Rad etish')))),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                  icon: busy ? _spinner(p.muted) : const Icon(Icons.inventory_2_outlined, size: 16),
                  label: Text(tr('Buyurtmani oldim')),
                  onPressed: busy ? null : () => onStatus('picked'),
                ),
              ),
            ] else
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 42), backgroundColor: p.success, foregroundColor: Colors.white),
                  icon: busy ? _spinner(p.muted) : const Icon(Icons.check_rounded, size: 18),
                  label: Text(tr('Yetkazdim')),
                  onPressed: busy ? null : () => onStatus('delivered'),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// Xaridorning to'g'ridan-to'g'ri so'rovi (do'kon buyurtmasisiz)
class _RequestCard extends StatelessWidget {
  final CargoOrder o;
  final bool busy;
  final ValueChanged<String> onStatus;
  const _RequestCard(this.o, {required this.onStatus, this.busy = false});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (label, color) = switch (o.status) { 'accepted' => (tr('Qabul qilindi'), p.success), _ => (tr('Yangi'), _blue) };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: Border.all(color: p.accent.withValues(alpha: .6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Pill(null, label, color),
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
            Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42), foregroundColor: p.danger), onPressed: busy ? null : () => onStatus('rejected'), child: Text(tr('Rad etish')))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 42)), onPressed: busy ? null : () => onStatus('accepted'), child: busy ? _spinner(p.muted) : Text(tr('Qabul qilish')))),
          ] else
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 42), backgroundColor: p.success, foregroundColor: Colors.white),
                icon: busy ? _spinner(p.muted) : const Icon(Icons.check_rounded, size: 18),
                label: Text(tr('Yetkazdim')),
                onPressed: busy ? null : () => onStatus('done'),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _Small extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool accent; // navigatsiya tugmasi — sariq fon bilan ajralib turadi
  const _Small(this.icon, this.text, this.onTap, {this.accent = false});
  @override
  Widget build(BuildContext context) => Material(
        color: accent ? context.p.accentSoft : context.p.bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: context.p.accentText),
              const SizedBox(width: 6),
              Text(text, style: TextStyle(fontSize: 12, fontWeight: accent ? FontWeight.w800 : FontWeight.w700)),
            ]),
          ),
        ),
      );
}

/// Marshrut nuqtasi: do'kondan olish (pickup) yoki xaridorga topshirish (dropoff)
class _Stop {
  final String orderId, kind, title, address;
  final double? lat, lon, legKm;
  _Stop.fromJson(Map j)
      : orderId = '${j['orderId'] ?? ''}',
        kind = '${j['kind'] ?? 'pickup'}',
        title = '${j['title'] ?? ''}',
        address = '${j['address'] ?? ''}',
        lat = _d(j['lat']),
        lon = _d(j['lon']),
        legKm = _d(j['legKm']);
}

/// "Optimal marshrut": faol buyurtmalar bo'yicha nuqtalar tartibi va jami masofa
class _RoutePlanCard extends StatelessWidget {
  final List<_Stop> stops;
  final double? totalKm;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  const _RoutePlanCard({required this.stops, required this.totalKm, required this.loading, required this.error, required this.onRefresh});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final sub = loading && stops.isEmpty
        ? tr('Hisoblanmoqda...')
        : stops.isEmpty
            ? tr('Faol buyurtmalar uchun eng qisqa tartib')
            : '${stops.length} ${tr('ta nuqta')}${totalKm != null ? ' · ${tr('jami')} ${fmtKm(totalKm!)}' : ''}';
    return _Card(
      borderColor: p.accent.withValues(alpha: .55),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.alt_route_rounded, size: 21, color: p.accentText)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Optimal marshrut'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(sub, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (loading) SizedBox(width: 36, height: 36, child: Center(child: _spinner(p.accentText))) else IconBtn(Icons.refresh_rounded, size: 36, bg: p.bg, onTap: onRefresh),
        ]),
        if (error != null && stops.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: TextStyle(fontSize: 12.5, color: p.danger, fontWeight: FontWeight.w600)))
        else if (loading && stops.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 10), child: Skeleton(height: 52, radius: 14))
        else if (stops.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (var i = 0; i < stops.length; i++) _StopRow(i + 1, stops[i], last: i == stops.length - 1),
        ],
      ]),
    );
  }
}

class _StopRow extends StatelessWidget {
  final int n;
  final _Stop s;
  final bool last;
  const _StopRow(this.n, this.s, {this.last = false});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final pickup = s.kind == 'pickup';
    final canNav = s.lat != null && s.lon != null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: canNav ? () => _openDirections(context, s.lat, s.lon) : null,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Chap tomonda nuqta belgisi va keyingi nuqtaga chiziq
          SizedBox(
            width: 28,
            child: Column(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: pickup ? p.accent : p.success, shape: BoxShape.circle),
                child: Icon(pickup ? Icons.storefront_rounded : Icons.person_pin_circle_rounded, size: 15, color: pickup ? p.onAccent : Colors.white),
              ),
              if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 3), color: p.muted.withValues(alpha: .25))),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 2 : 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$n. ${pickup ? tr('Olib ketish') : tr('Topshirish')}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: pickup ? p.accentText : p.success)),
                Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                if (s.address.isNotEmpty) Text(s.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (s.legKm != null) Text('+${fmtKm(s.legKm!)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            if (canNav) Padding(padding: const EdgeInsets.only(top: 4), child: Icon(Icons.navigation_rounded, size: 18, color: p.accentText)),
          ]),
        ]),
      ),
    );
  }
}

// ---- Daromad (kuryer) / Statistika (yuk tashuvchi) ----
class CourierStatsTab extends StatefulWidget {
  final VoidCallback onExit;
  final Listenable? refresh; // tab ochilganda yangilash signali
  const CourierStatsTab({super.key, required this.onExit, this.refresh});
  @override
  State<CourierStatsTab> createState() => _CourierStatsTabState();
}

class _CourierStatsTabState extends State<CourierStatsTab> {
  static const _path = '/api/courier/stats';
  Map? stats;
  bool loading = true;
  bool _fetching = false;
  String? error;
  // AI tavsiyalar
  List<Tip> tips = [];
  DateTime? tipsAt;
  bool aiLoading = true;
  String? aiError;
  String _tariffKey = '';

  static String _tariffOf(Courier? c) => c == null ? '' : '${c.basePrice}/${c.pricePerKm}';

  @override
  void initState() {
    super.initState();
    final cached = Api.instance.cached(_path);
    if (cached is Map) stats = cached;
    _tariffKey = _tariffOf(AppState.instance.courier);
    AppState.instance.addListener(_onState);
    widget.refresh?.addListener(load);
    load();
    loadAi();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onState);
    widget.refresh?.removeListener(load);
    super.dispose();
  }

  int _seenLive = AppState.instance.liveVersion;

  /// Tarif o'zgarsa yoki yetkazish/yuk holati o'zgarsa (jonli hodisa) statistika qayta hisoblanadi
  void _onState() {
    final st = AppState.instance;
    var reload = false;
    final k = _tariffOf(st.courier);
    if (k != _tariffKey) {
      _tariffKey = k;
      reload = true;
    }
    if (st.liveVersion != _seenLive) {
      _seenLive = st.liveVersion;
      final t = st.lastEvent?.type ?? '';
      if (t == 'stats' || t.startsWith('order:') || t.startsWith('cargo:')) reload = true;
    }
    if (reload) load();
  }

  Future<void> load() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final r = await Api.instance.get(_path);
      if (r is Map) stats = r;
      error = null;
    } catch (e) {
      error = _errText(e);
    }
    _fetching = false;
    if (mounted) setState(() => loading = false);
  }

  Future<void> loadAi({bool refresh = false}) async {
    if (refresh) {
      if (aiLoading) return;
      setState(() {
        aiLoading = true;
        aiError = null;
      });
    }
    try {
      final r = _map(await Api.instance.get('/api/courier/ai-insights${refresh ? '?refresh=1' : ''}'));
      tips = _list(r['tips']).map((e) => Tip.fromJson(Map<String, dynamic>.from(e))).toList();
      tipsAt = DateTime.tryParse('${r['generatedAt'] ?? ''}');
      aiError = null;
    } catch (e) {
      aiError = _errText(e);
    }
    if (mounted) setState(() => aiLoading = false);
  }

  void _retry() {
    setState(() {
      loading = true;
      error = null;
    });
    load();
  }

  @override
  Widget build(BuildContext context) {
    final isCargo = AppState.instance.courier?.isCargo == true;
    final s = stats;
    final type = s?['type'] ?? (isCargo ? 'cargo' : 'courier');
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([load(), loadAi()]);
        },
        child: ListView(padding: EdgeInsets.zero, children: [
          CourierHeader(isCargo ? tr('Statistika') : tr('Daromad'), onExit: widget.onExit),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, navPad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _AiCard(tips: tips, at: tipsAt, loading: aiLoading, error: aiError, onRefresh: () => loadAi(refresh: true)),
              const SizedBox(height: 12),
              if (s == null && loading)
                const Column(children: [Skeleton(height: 118, radius: 20), SizedBox(height: 10), Skeleton(height: 220, radius: 20), SizedBox(height: 10), Skeleton(height: 140, radius: 20)])
              else if (s == null)
                _ErrorState(error ?? tr("Ma'lumot yo'q"), onRetry: _retry)
              else ...[
                if (error != null) _InlineError(error!, onRetry: _retry),
                if (type == 'cargo') ..._cargo(context, s) else ..._courier(context, s),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  /// Kuryer: davr bo'yicha daromad, 14 kun, faol soatlar, issiq zonalar
  List<Widget> _courier(BuildContext context, Map s) {
    final p = context.p;
    final tariff = _map(s['tariff']);
    final total = _map(s['total']);
    final rate = s['acceptRate'];
    final days = _parseDays(s['byDay'], 'deliveries', 'earnings');
    final peaks = _list(s['peakHours']);
    final zones = _list(s['hotZones']);
    return [
      if (tariff['isSet'] != true) ...[_TariffBanner(tr('Daromad hisoblanishi uchun tarifingizni kiriting')), const SizedBox(height: 12)],
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _PeriodTile(tr('Bugun'), _map(s['today']), highlight: true)),
        const SizedBox(width: 8),
        Expanded(child: _PeriodTile(tr('Hafta'), _map(s['week']))),
        const SizedBox(width: 8),
        Expanded(child: _PeriodTile(tr('Oy'), _map(s['month']))),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _Pill(Icons.hourglass_top_rounded, '${tr('Kutayotgan buyurtmalar')}: ${_n(s['waitingOrders'])}', p.accentText, bg: p.accentSoft),
        if (rate is num) _Pill(Icons.task_alt_rounded, '${tr('Qabul qilish')}: ${rate.round()}%', rate >= 70 ? p.success : _amber(context)),
        if (_n(s['active']) > 0) _Pill(Icons.delivery_dining_rounded, '${tr('Faol')}: ${_n(s['active'])}', _blue),
        _Pill(Icons.all_inclusive_rounded, "${tr('Jami')}: ${_n(total['deliveries'])} · ${fmtPrice(_n(total['earnings']))} so'm · ${fmtKm(_d(total['km']) ?? 0)}", p.text, bg: p.card),
      ]),
      _Section(Icons.bar_chart_rounded, tr('14 kunlik yetkazishlar'), hint: tr("Kunni bosing — o'sha kungi daromad ko'rinadi"), child: _Card(child: _DayBars(days, unit: tr('yetkazish')))),
      if (peaks.isNotEmpty)
        _Section(
          Icons.schedule_rounded,
          tr('Eng faol soatlar'),
          hint: tr("Bozorda buyurtmalar eng ko'p bo'ladigan vaqtlar"),
          child: _Card(child: _HBars([for (final h in peaks) (label: '${h['label'] ?? ''}', v: _n(h['orders']), text: '${_n(h['orders'])} ${tr('ta buyurtma')}')], color: _violet(context))),
        ),
      if (zones.isNotEmpty)
        _Section(
          Icons.local_fire_department_outlined,
          tr('Issiq zonalar'),
          hint: tr("Buyurtma ko'p do'konlar — shu atrofda bo'ling"),
          child: _Card(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Column(children: [
              for (var i = 0; i < zones.length; i++) ...[
                if (i > 0) Divider(height: 1, color: p.border),
                _ZoneRow(i + 1, zones[i]),
              ],
            ]),
          ),
        ),
    ];
  }

  /// Yuk tashuvchi: buyurtmalar soni, tushum, 14 kun, talabgir yo'nalishlar, bozor
  List<Widget> _cargo(BuildContext context, Map s) {
    final p = context.p;
    final tariff = _map(s['tariff']);
    final counts = _map(s['counts']);
    final revenue = _map(s['revenue']);
    final market = _map(s['market']);
    final rate = s['acceptRate'];
    final days = _parseDays(s['byDay'], 'orders', 'revenue');
    final routes = _list(s['topRoutes']);
    return [
      if (tariff['isSet'] != true) ...[_TariffBanner(tr('Tavsiya narxlar va tushum hisoblanishi uchun tarifingizni kiriting')), const SizedBox(height: 12)],
      Row(children: [
        Expanded(child: _StatTile(Icons.account_balance_wallet_outlined, p.success, fmtPrice(_n(revenue['month'])), tr("Bu oy, so'm"))),
        const SizedBox(width: 10),
        Expanded(child: _StatTile(Icons.savings_outlined, _violet(context), fmtPrice(_n(revenue['total'])), tr("Jami, so'm"))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _StatTile(Icons.fiber_new_outlined, _blue, '${_n(counts['new'])}', tr('Yangi'))),
        const SizedBox(width: 10),
        Expanded(child: _StatTile(Icons.local_shipping_outlined, p.accentText, '${_n(counts['accepted'])}', tr('Qabul qilingan'))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _StatTile(Icons.check_circle_outline_rounded, p.success, '${_n(counts['done'])}', tr('Bajarilgan'))),
        const SizedBox(width: 10),
        Expanded(child: _StatTile(Icons.block_rounded, p.danger, '${_n(counts['rejected'])}', tr('Rad etilgan'))),
      ]),
      if (rate is num) ...[
        const SizedBox(height: 10),
        Wrap(children: [_Pill(Icons.task_alt_rounded, '${tr('Qabul qilish')}: ${rate.round()}%', rate >= 70 ? p.success : _amber(context))]),
      ],
      _Section(Icons.bar_chart_rounded, tr('14 kunlik buyurtmalar'), hint: tr("Kunni bosing — o'sha kungi tushum ko'rinadi"), child: _Card(child: _DayBars(days, unit: tr('ta buyurtma')))),
      if (routes.isNotEmpty)
        _Section(
          Icons.route_rounded,
          tr("Eng talabgir yo'nalishlar"),
          hint: tr('Sizning narxingiz va bozor narxi'),
          child: _Card(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Column(children: [
              for (var i = 0; i < routes.length; i++) ...[
                if (i > 0) Divider(height: 1, color: p.border),
                _RouteDemandRow(routes[i]),
              ],
            ]),
          ),
        ),
      _Section(Icons.groups_2_outlined, tr('Bozor'), child: _MarketCard(market: market, tariff: tariff)),
    ];
  }
}

typedef _Day = ({DateTime? date, int count, int money});

List<_Day> _parseDays(dynamic v, String countKey, String moneyKey) => [
      for (final x in _list(v)) (date: DateTime.tryParse('${x['date']}'), count: _n(x[countKey]), money: _n(x[moneyKey])),
    ];

/// AI yordamchi kartasi: tavsiyalar, yangilash tugmasi
class _AiCard extends StatelessWidget {
  final List<Tip> tips;
  final DateTime? at;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  const _AiCard({required this.tips, required this.at, required this.loading, required this.error, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    const soft = Color(0xB3FFFFFF);
    final sub = loading
        ? tr('Tahlil qilinmoqda...')
        : at != null
            ? '${tr('Yangilandi')}: ${fmtTime(at!)}'
            : tr("Daromadni oshirish bo'yicha maslahatlar");
    return DarkBanner(
      glow: const Color(0xFF7C5CFF),
      glow2: const Color(0xFFFFCC00),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.auto_awesome_rounded, size: 20, color: p.onAccent)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('AI yordamchi'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -.2)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
          Material(
            color: Colors.white.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: loading ? null : onRefresh,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 38, height: 38, child: Center(child: loading ? _spinner(Colors.white) : const Icon(Icons.refresh_rounded, size: 20, color: Colors.white))),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        if (loading && tips.isEmpty)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final w in [1.0, .8, .6])
              FractionallySizedBox(
                widthFactor: w,
                child: Container(height: 12, margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), borderRadius: BorderRadius.circular(6))),
              ),
          ])
        else if (error != null && tips.isEmpty)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.cloud_off_rounded, size: 18, color: Colors.white.withValues(alpha: .6)),
            const SizedBox(width: 8),
            Expanded(child: Text("${tr("AI tavsiyalarini yuklab bo'lmadi")}.\n$error", style: const TextStyle(color: soft, fontSize: 13, height: 1.4, fontWeight: FontWeight.w500))),
          ])
        else if (tips.isEmpty)
          Text(tr("Hozircha tavsiya yo'q — birozdan so'ng yangilang"), style: const TextStyle(color: soft, fontSize: 13, fontWeight: FontWeight.w500))
        else
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: loading ? .5 : 1,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < tips.length; i++) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 12), child: _TipRow(tips[i])),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Color(0xFFFF8A8E), fontSize: 12, fontWeight: FontWeight.w600))),
            ]),
          ),
      ]),
    );
  }
}

class _TipRow extends StatelessWidget {
  final Tip t;
  const _TipRow(this.t);
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (t.type) {
      'warning' => (Icons.warning_amber_rounded, const Color(0xFFFFB547)),
      'success' => (Icons.check_circle_outline_rounded, const Color(0xFF7EE2B0)),
      _ => (Icons.lightbulb_outline_rounded, const Color(0xFFFFD633)),
    };
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: color.withValues(alpha: .18), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 17, color: color)),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (t.title.isNotEmpty) Text(t.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
          if (t.text.isNotEmpty) Text(t.text, style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)),
        ]),
      ),
    ]);
  }
}

/// Tarif kiritilmagan: ogohlantirish va tahrirlash oynasini ochish
class _TariffBanner extends StatelessWidget {
  final String text;
  const _TariffBanner(this.text);
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.accent.withValues(alpha: .6))),
      child: Row(children: [
        Icon(Icons.payments_outlined, size: 22, color: p.accentText),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text, height: 1.3))),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            backgroundColor: context.isDark ? p.accent : p.dark,
            foregroundColor: context.isDark ? p.onAccent : p.onDark,
          ),
          onPressed: () => showCourierEditSheet(context),
          child: Text(tr('Kiritish')),
        ),
      ]),
    );
  }
}

/// Bugun / Hafta / Oy: daromad, yetkazishlar soni, km
class _PeriodTile extends StatelessWidget {
  final String label;
  final Map data;
  final bool highlight;
  const _PeriodTile(this.label, this.data, {this.highlight = false});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final dark = highlight && !context.isDark; // yorug' mavzuda "Bugun" qora kartada
    final fg = dark ? Colors.white : p.text;
    final sub = dark ? Colors.white.withValues(alpha: .6) : p.muted;
    Widget line(IconData ic, String t) => Row(children: [
          Icon(ic, size: 12, color: sub),
          const SizedBox(width: 3),
          Expanded(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg))),
        ]);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? p.dark : p.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: softShadow(context),
        border: context.isDark ? Border.all(color: highlight ? p.accent.withValues(alpha: .6) : p.border) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: highlight ? p.accent : p.muted)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(fmtPrice(_n(data['earnings'])), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.5, color: fg, height: 1.1)),
        ),
        Text("so'm", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sub)),
        const SizedBox(height: 8),
        line(Icons.check_circle_outline_rounded, '${_n(data['deliveries'])} ${tr('yetkazish')}'),
        const SizedBox(height: 2),
        line(Icons.route_rounded, fmtKm(_d(data['km']) ?? 0)),
      ]),
    );
  }
}

/// Ko'rsatkich plitkasi (analitika uslubida)
class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _StatTile(this.icon, this.color, this.value, this.label);
  @override
  Widget build(BuildContext context) => _Card(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 19, color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.5, height: 1.1))),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: context.p.muted, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      );
}

/// 14 kunlik ustunli diagramma: ustunni bosganda o'sha kun tafsiloti ko'rinadi
class _DayBars extends StatefulWidget {
  final List<_Day> days;
  final String unit;
  const _DayBars(this.days, {required this.unit});
  @override
  State<_DayBars> createState() => _DayBarsState();
}

class _DayBarsState extends State<_DayBars> {
  int? sel;

  String _label(DateTime? d) {
    if (d == null) return '—';
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return tr('Bugun');
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final days = widget.days;
    if (days.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Center(child: Text(tr("Ma'lumot yo'q"), style: TextStyle(color: p.muted, fontSize: 13))));
    }
    final max = days.fold<int>(1, (m, d) => d.count > m ? d.count : m);
    final i = (sel ?? days.length - 1).clamp(0, days.length - 1);
    final cur = days[i];
    final sumCount = days.fold<int>(0, (a, d) => a + d.count);
    final sumMoney = days.fold<int>(0, (a, d) => a + d.money);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text("${tr('14 kunda')}: $sumCount ${widget.unit} · ${fmtPrice(sumMoney)} so'm", style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      // Tanlangan kun
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.calendar_today_rounded, size: 14, color: p.accentText),
          const SizedBox(width: 6),
          Text(_label(cur.date), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('${cur.count} ${widget.unit} · ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          Text("${fmtPrice(cur.money)} so'm", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.success)),
        ]),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 116,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var j = 0; j < days.length; j++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => sel = j),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (days[j].count > 0) Text('${days[j].count}', maxLines: 1, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: j == i ? p.text : p.muted)),
                    const SizedBox(height: 2),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 4 + 86 * days[j].count / max,
                      decoration: BoxDecoration(color: j == i ? p.accent : p.accent.withValues(alpha: context.isDark ? .28 : .35), borderRadius: BorderRadius.circular(5)),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        for (var j = 0; j < days.length; j++)
          Expanded(
            child: Text(
              days[j].date == null ? '' : '${days[j].date!.day}',
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(fontSize: 9.5, fontWeight: j == i ? FontWeight.w800 : FontWeight.w600, color: j == i ? p.accentText : p.muted),
            ),
          ),
      ]),
    ]);
  }
}

/// Gorizontal ustunlar ro'yxati (faol soatlar)
class _HBars extends StatelessWidget {
  final List<({String label, num v, String text})> items;
  final Color color;
  const _HBars(this.items, {required this.color});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final max = items.fold<num>(1, (m, i) => i.v > m ? i.v : m);
    return Column(children: [
      for (var k = 0; k < items.length; k++)
        Padding(
          padding: EdgeInsets.only(bottom: k == items.length - 1 ? 0 : 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(items[k].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              Text(items[k].text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 7,
                child: Stack(children: [
                  Container(color: context.isDark ? p.border : p.bg),
                  FractionallySizedBox(widthFactor: (items[k].v / max).clamp(.02, 1).toDouble(), child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)))),
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}

/// Issiq zona qatori: do'kon, manzil, buyurtmalar, masofa va navigatsiya
class _ZoneRow extends StatelessWidget {
  final int n;
  final Map z;
  const _ZoneRow(this.n, this.z);
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final lat = _d(z['lat']), lon = _d(z['lon']), dist = _d(z['distanceKm']);
    final address = '${z['address'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)),
          child: Text('$n', style: TextStyle(fontWeight: FontWeight.w800, color: p.danger)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${z['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            if (address.isNotEmpty) Text(address, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
            Text(
              [ '${_n(z['orders'])} ${tr('ta buyurtma')}', if (dist != null) '${fmtKm(dist)} ${tr('uzoqlikda')}' ].join(' · '),
              style: TextStyle(fontSize: 12, color: p.text.withValues(alpha: .85), fontWeight: FontWeight.w700),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        IconBtn(Icons.navigation_rounded, size: 38, bg: p.accentSoft, color: p.accentText, onTap: lat != null && lon != null ? () => _openDirections(context, lat, lon) : null),
      ]),
    );
  }
}

/// Talabgir yo'nalish: sizning narxingiz bozor narxidan past/teng — yashil, yuqori — sariq
class _RouteDemandRow extends StatelessWidget {
  final Map r;
  const _RouteDemandRow(this.r);
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final dist = _d(r['distanceKm']);
    final yours = r['yourPrice'] is num ? _n(r['yourPrice']) : null;
    final market = r['marketPrice'] is num ? _n(r['marketPrice']) : null;
    final yourColor = yours == null || market == null ? p.text : (yours <= market ? p.success : _amber(context));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['from'] ?? ''} → ${r['to'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            Text(
              [ '${_n(r['orders'])} ${tr('ta buyurtma')}', if (dist != null) fmtKm(dist) ].join(' · '),
              style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(yours == null ? "${tr('Siz')}: —" : "${tr('Siz')}: ${fmtPrice(yours)} so'm", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: yourColor)),
          if (market != null) Text("${tr('Bozor')}: ${fmtPrice(market)} so'm", style: TextStyle(fontSize: 11, color: p.muted, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

/// Bozor: tashuvchilar soni va median tariflar bilan solishtirish
class _MarketCard extends StatelessWidget {
  final Map market;
  final Map tariff;
  const _MarketCard({required this.market, required this.tariff});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget row(String label, int mine, dynamic median, String suffix) {
      final m = median is num ? median.round() : null;
      final color = mine <= 0 || m == null ? p.text : (mine <= m ? p.success : _amber(context));
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w700))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(mine > 0 ? "${tr('Siz')}: ${fmtPrice(mine)} $suffix" : "${tr('Siz')}: —", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
            Text(m != null ? "${tr('Median')}: ${fmtPrice(m)} $suffix" : "${tr('Median')}: —", style: TextStyle(fontSize: 11, color: p.muted, fontWeight: FontWeight.w600)),
          ]),
        ]),
      );
    }

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: _blue.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.groups_2_outlined, size: 19, color: _blue)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_n(market['carriers'])} ${tr('ta tashuvchi')}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              Text(tr('Ilovadagi yuk tashuvchilar tariflari bilan solishtirish'), style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        row(tr("Boshlang'ich narx"), _n(tariff['basePrice']), market['medianBasePrice'], "so'm"),
        row(tr('Har km narxi'), _n(tariff['pricePerKm']), market['medianPricePerKm'], "so'm/km"),
      ]),
    );
  }
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
              Switch(value: c.online, activeThumbColor: p.success, onChanged: widget.onOnline),
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

/// Tarif matni: "5 000 so'm + 2 000 so'm/km"
String _tariffText(Courier c) => [if (c.basePrice > 0) "${fmtPrice(c.basePrice)} so'm", if (c.pricePerKm > 0) "${fmtPrice(c.pricePerKm)} so'm/km"].join(' + ');

/// Profilni tahrirlash oynasi (profil va daromad tablaridan ochiladi). Saqlansa true qaytadi.
Future<bool> showCourierEditSheet(BuildContext context) async {
  final c = AppState.instance.courier;
  if (c == null) return false;
  var allRegions = <String>[];
  if (c.isCargo) {
    try {
      final r = await Api.instance.get('/api/cargo/regions');
      if (r is List) allRegions = r.map((e) => '$e').toList();
    } catch (_) {}
  }
  if (!context.mounted) return false;
  final saved = await showModalBottomSheet<bool>(
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CourierEditSheet(courier: c, allRegions: allRegions),
  );
  return saved == true;
}

class _CourierEditSheet extends StatefulWidget {
  final Courier courier;
  final List<String> allRegions;
  const _CourierEditSheet({required this.courier, required this.allRegions});
  @override
  State<_CourierEditSheet> createState() => _CourierEditSheetState();
}

class _CourierEditSheetState extends State<_CourierEditSheet> {
  late final Courier c = widget.courier;
  late final name = TextEditingController(text: c.name);
  late final phone = TextEditingController(text: c.phone);
  late final email = TextEditingController(text: c.email);
  late final about = TextEditingController(text: c.about);
  late final capacity = TextEditingController(text: c.capacityKg > 0 ? '${c.capacityKg}' : '');
  late final base = TextEditingController(text: c.basePrice > 0 ? '${c.basePrice}' : '');
  late final km = TextEditingController(text: c.pricePerKm > 0 ? '${c.pricePerKm}' : '');
  late String vehicle = c.vehicle;
  late String vehicleType = c.vehicleType;
  late final regions = List<String>.from(c.regions);
  bool saving = false;
  String? err;

  @override
  void dispose() {
    for (final x in [name, phone, email, about, capacity, base, km]) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    setState(() {
      saving = true;
      err = null;
    });
    try {
      final r = await Api.instance.put('/api/courier/profile', {
        'name': name.text.trim(),
        'phone': phone.text.trim(),
        'email': email.text.trim(),
        'about': about.text.trim(),
        'vehicle': vehicle,
        // Tarif endi kuryer va yuk tashuvchi uchun ham
        'basePrice': int.tryParse(base.text) ?? 0,
        'pricePerKm': int.tryParse(km.text) ?? 0,
        if (c.isCargo) 'vehicleType': vehicleType,
        if (c.isCargo) 'capacityKg': int.tryParse(capacity.text) ?? 0,
        if (c.isCargo) 'regions': regions,
      });
      AppState.instance.courier = Courier.fromJson(r['courier']).copyWith(online: AppState.instance.courier?.online ?? c.online);
      AppState.instance.refresh();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // Oyna ichida ko'rsatiladi (bottom sheet ustida snackbar ko'rinmaydi)
      if (mounted) {
        setState(() {
          saving = false;
          err = _errText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Profilni tahrirlash'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
          const SizedBox(height: 12),
          TextField(controller: name, decoration: InputDecoration(labelText: tr('Ism'))),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Telefon'))),
          const SizedBox(height: 10),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 10),
          TextField(controller: about, maxLines: 2, decoration: InputDecoration(labelText: tr("O'zingiz haqingizda"))),
          const SizedBox(height: 12),
          if (c.isCargo) ...[
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final v in cargoVehicles)
                ChoiceChip(selected: vehicleType == v, avatar: Icon(cargoVehicleIcon(v), size: 16, color: vehicleType == v ? p.onDark : p.text), label: Text(cargoVehicleName(v)), onSelected: (_) => setState(() => vehicleType = v)),
            ]),
            const SizedBox(height: 10),
            TextField(controller: capacity, keyboardType: TextInputType.number, inputFormatters: digits, decoration: InputDecoration(labelText: tr("Sig'im, kg"))),
            const SizedBox(height: 10),
            Text(tr('Xizmat viloyatlari'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in widget.allRegions)
                FilterChip(selected: regions.contains(r), label: Text(r, style: const TextStyle(fontSize: 12)), onSelected: (v) => setState(() => v ? regions.add(r) : regions.remove(r))),
            ]),
          ] else
            Wrap(spacing: 8, children: [
              for (final v in ['foot', 'bike', 'moto', 'car'])
                ChoiceChip(selected: vehicle == v, avatar: Icon(vehicleIcon(v), size: 16, color: vehicle == v ? p.onDark : p.text), label: Text(vehicleName(v)), onSelected: (_) => setState(() => vehicle = v)),
            ]),
          const SizedBox(height: 14),
          Text(tr('Tarif'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.muted)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(controller: base, keyboardType: TextInputType.number, inputFormatters: digits, decoration: InputDecoration(labelText: tr("Boshlang'ich narx"), suffixText: "so'm"))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: km, keyboardType: TextInputType.number, inputFormatters: digits, decoration: InputDecoration(labelText: tr('Har km narxi'), suffixText: "so'm"))),
          ]),
          const SizedBox(height: 6),
          Text(
            c.isCargo ? tr("Mijozlarga taxminiy narx shu tarif bo'yicha ko'rsatiladi") : tr("Yetkazish haqi = boshlang'ich narx + masofa × km narxi"),
            style: TextStyle(fontSize: 11.5, color: p.muted, fontWeight: FontWeight.w600),
          ),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: TextStyle(fontSize: 13, color: p.danger, fontWeight: FontWeight.w700))),
          const SizedBox(height: 16),
          FilledButton(onPressed: saving ? null : save, child: saving ? _spinner(p.muted, size: 18) : Text(tr('Saqlash'))),
        ]),
      ),
    );
  }
}

class CourierProfileTab extends StatelessWidget {
  final VoidCallback onExit;
  final ValueChanged<bool> onOnline;
  const CourierProfileTab({super.key, required this.onExit, required this.onOnline});

  /// Profil rasmi: kamera yoki galereyadan olinib, serverga yuboriladi
  Future<void> _photo(BuildContext context) async {
    final src = await askImageSource(context);
    if (src == null) return;
    final f = await PhotoPick.logo(src);
    if (f == null) return;
    try {
      final photo = await Api.instance.uploadImage(
        await f.readAsBytes(),
        mime: Api.imageMimeForPath(f.path),
      );
      final r = await Api.instance.put('/api/courier/profile', {'photo': photo});
      AppState.instance.courier = Courier.fromJson(r['courier']).copyWith(online: AppState.instance.courier?.online);
      AppState.instance.refresh();
    } catch (e) {
      if (context.mounted) showToast(context, _errText(e), error: true);
    }
  }

  /// Joriy parol + aynan shu profil emailiga yuborilgan kod bo'lmasa parol saqlanmaydi.
  void _password(BuildContext context) {
    final old = TextEditingController(), fresh = TextEditingController(), repeat = TextEditingController(), code = TextEditingController();
    var codeSent = false, busy = false;
    String? devCode, error;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(sheet).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr("Parolni o'zgartirish"), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
              const SizedBox(height: 5),
              Text(codeSent ? tr('Aynan profilingiz emailiga yuborilgan 6 xonali kodni kiriting') : tr("Joriy parol va email kodi bilan himoyalangan"), style: TextStyle(fontSize: 13, color: sheet.p.muted)),
              const SizedBox(height: 12),
              TextField(controller: old, obscureText: true, enabled: !codeSent && !busy, decoration: InputDecoration(labelText: tr('Joriy parol'))),
              const SizedBox(height: 10),
              TextField(controller: fresh, obscureText: true, enabled: !codeSent && !busy, decoration: InputDecoration(labelText: tr('Yangi parol (kamida 6 belgi)'))),
              if (!codeSent) ...[
                const SizedBox(height: 10),
                TextField(controller: repeat, obscureText: true, enabled: !busy, decoration: InputDecoration(labelText: tr('Yangi parolni takrorlang'))),
              ] else ...[
                const SizedBox(height: 10),
                TextField(controller: code, keyboardType: TextInputType.number, maxLength: 6, enabled: !busy, decoration: InputDecoration(labelText: tr('6 xonali tasdiqlash kodi'), counterText: '')),
                if (devCode != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${tr('Test kodi')}: $devCode', style: TextStyle(fontSize: 12, color: sheet.p.accentText, fontWeight: FontWeight.w800))),
              ],
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(fontSize: 12, color: sheet.p.danger, fontWeight: FontWeight.w700))),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(codeSent ? Icons.verified_rounded : Icons.mark_email_read_outlined, size: 18),
                label: Text(codeSent ? tr('Kod bilan tasdiqlash') : tr('Emailga kod yuborish')),
                onPressed: busy ? null : () async {
                  if (!codeSent && fresh.text != repeat.text) {
                    setSheet(() => error = tr('Parollar mos kelmadi'));
                    return;
                  }
                  setSheet(() { busy = true; error = null; });
                  try {
                    final r = await Api.instance.post('/api/courier/password', {
                      'oldPassword': old.text,
                      'newPassword': fresh.text,
                      if (codeSent) 'code': code.text,
                    });
                    if (!sheet.mounted) return;
                    if (!codeSent) {
                      setSheet(() { codeSent = true; devCode = r['devCode']?.toString(); });
                    } else {
                      Navigator.of(sheet).pop();
                      if (context.mounted) showToast(context, tr("Parol email kodi bilan o'zgartirildi"));
                    }
                  } catch (e) {
                    if (sheet.mounted) setSheet(() => error = _errText(e));
                  } finally {
                    if (sheet.mounted) setSheet(() => busy = false);
                  }
                },
              ),
            ]),
          ),
        ),
      ),
    ).whenComplete(() { old.dispose(); fresh.dispose(); repeat.dispose(); code.dispose(); });
  }

  // Tahrirlashdan keyin profil darhol yangilanishi uchun AppState tinglanadi
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: AppState.instance, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final p = context.p;
    final st = AppState.instance;
    final c = st.courier;
    if (c == null) return const Scaffold();
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
                if (c.about.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.about, textAlign: TextAlign.center, style: TextStyle(color: p.text.withValues(alpha: .8), fontSize: 13, height: 1.4))),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _Stat(c.isCargo ? tr('Reyslar') : tr('Yetkazilgan'), '${c.deliveries}', Icons.local_shipping_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat(tr('Holat'), c.online ? tr('Onlayn') : tr('Oflayn'), c.online ? Icons.wifi_rounded : Icons.wifi_off_rounded)),
                ]),
                const SizedBox(height: 10),
                // Tarif xulosasi
                Material(
                  color: c.hasTariff ? p.bg : p.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => showCourierEditSheet(context),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      child: Row(children: [
                        Icon(Icons.payments_outlined, size: 20, color: p.accentText),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tr('Tarif'), style: TextStyle(fontSize: 11, color: p.muted, fontWeight: FontWeight.w700)),
                            Text(c.hasTariff ? _tariffText(c) : tr('Kiritilmagan — daromad hisoblanmaydi'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.text)),
                          ]),
                        ),
                        Text(c.hasTariff ? tr("O'zgartirish") : tr('Kiritish'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.accentText)),
                        Icon(Icons.chevron_right_rounded, size: 18, color: p.accentText),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: p.bg, side: BorderSide.none), icon: const Icon(Icons.edit_outlined, size: 16), label: Text(tr('Profilni tahrirlash')), onPressed: () => showCourierEditSheet(context)),
              ]),
            ),
            const SizedBox(height: 12),
            _ServiceProfileCard(c),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
              // Oq kartochka ichida ListTile bosilish effekti ko'rinishi uchun alohida Material qatlami
              child: Material(type: MaterialType.transparency, child: Column(children: [
                ListTile(leading: Icon(Icons.verified_user_outlined, color: p.accentText), title: Text(tr('Xavfsizlik'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)), subtitle: Text(tr("Parol email kodi bilan himoyalangan"), style: TextStyle(fontSize: 12, color: p.muted)), trailing: Icon(Icons.chevron_right_rounded, color: p.muted), onTap: () => _password(context)),
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
              ])),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Kuryer yoki yuk tashuvchining mijoz ko'radigan ish pasporti.
class _ServiceProfileCard extends StatelessWidget {
  final Courier c;
  const _ServiceProfileCard(this.c);

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final rows = <(IconData, String, String)>[
      (c.isCargo ? Icons.local_shipping_outlined : providerIcon(c), tr('Transport'), c.isCargo ? cargoVehicleName(c.vehicleType) : vehicleName(c.vehicle)),
      if (c.plate.isNotEmpty) (Icons.pin_outlined, tr('Davlat raqami'), c.plate),
      if (c.isCargo && c.capacityKg > 0) (Icons.inventory_2_outlined, tr("Sig'im"), '${c.capacityKg} kg'),
      (Icons.route_outlined, tr('Xizmat hududi'), c.isCargo ? (c.regions.isEmpty ? tr("Ko'rsatilmagan") : c.regions.join(' · ')) : (c.region.isEmpty ? tr("Ko'rsatilmagan") : c.region)),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.badge_outlined, size: 19, color: p.accentText), const SizedBox(width: 8), Text(tr('Xizmat profili'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))]),
        const SizedBox(height: 7),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(r.$1, size: 18, color: p.muted), const SizedBox(width: 10),
              SizedBox(width: 98, child: Text(r.$2, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w700))),
              Expanded(child: Text(r.$3, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
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
  String? error;
  final busy = <String>{};
  Timer? _t;

  @override
  void initState() {
    super.initState();
    load();
    _t = Timer.periodic(const Duration(seconds: 20), (_) => load());
    AppState.instance.addListener(_onLive);
  }

  @override
  void dispose() {
    _t?.cancel();
    AppState.instance.removeListener(_onLive);
    super.dispose();
  }

  // Yangi yuk so'rovi kelsa ro'yxat joyida yangilanadi
  int _seenLive = AppState.instance.liveVersion;
  void _onLive() {
    final st = AppState.instance;
    if (st.liveVersion == _seenLive) return;
    _seenLive = st.liveVersion;
    if ((st.lastEvent?.type ?? '').startsWith('cargo:')) load();
  }

  Future<void> load() async {
    try {
      final r = await Api.instance.get('/api/courier/cargo');
      orders = (r as List).map((e) => CargoOrder.fromJson(e)).toList();
      error = null;
    } catch (e) {
      error = _errText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> setStatus(CargoOrder o, String status, {int? price}) async {
    if (busy.contains(o.id)) return;
    setState(() => busy.add(o.id));
    try {
      await Api.instance.patch('/api/courier/cargo/${o.id}', {'status': status, if (price != null) 'price': price});
      if (status == 'done') {
        final c = AppState.instance.courier;
        if (c != null) AppState.instance.courier = c.copyWith(deliveries: c.deliveries + 1);
        AppState.instance.refresh();
      }
      await load();
      if (mounted) showToast(context, switch (status) { 'accepted' => tr('Qabul qilindi'), 'done' => tr('Yetkazildi'), _ => tr('Rad etildi') });
    } catch (e) {
      if (mounted) showToast(context, _errText(e), error: true);
      if (e is ApiException && e.status == 409) await load(); // holat eskirgan — ro'yxatni yangilaymiz
    } finally {
      if (mounted) setState(() => busy.remove(o.id));
    }
  }

  /// Qabul qilish: avval kelishilgan narx so'raladi (tavsiya narx bilan to'ldirilgan)
  Future<void> accept(CargoOrder o) async {
    if (busy.contains(o.id)) return;
    final price = await showModalBottomSheet<int>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PriceSheet(order: o),
    );
    if (price == null || !mounted) return;
    await setStatus(o, 'accepted', price: price > 0 ? price : null);
  }

  @override
  Widget build(BuildContext context) {
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
              else if (error != null && orders.isEmpty)
                _ErrorState(error!, onRetry: () {
                  setState(() => loading = true);
                  load();
                })
              else ...[
                if (error != null) _InlineError(error!, onRetry: load),
                if (orders.isEmpty)
                  EmptyBox(Icons.local_shipping_outlined, tr("Hozircha yuk buyurtmasi yo'q.\nProfilingizda viloyatlar va narxni to'ldiring — mijozlar sizni topadi."))
                else
                  for (final o in orders)
                    _CargoCard(
                      o,
                      busy: busy.contains(o.id),
                      onAccept: () => accept(o),
                      onReject: () => setStatus(o, 'rejected'),
                      onDone: () => setStatus(o, 'done'),
                    ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _CargoCard extends StatelessWidget {
  final CargoOrder o;
  final bool busy;
  final VoidCallback onAccept, onReject, onDone;
  const _CargoCard(this.o, {required this.busy, required this.onAccept, required this.onReject, required this.onDone});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (label, color) = switch (o.status) { 'accepted' => (tr('Qabul qilindi'), p.success), 'done' => (tr('Yetkazildi'), p.success), 'rejected' => (tr('Rad etildi'), p.danger), _ => (tr('Yangi'), _blue) };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: softShadow(context), border: context.isDark ? Border.all(color: p.border) : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Pill(null, label, color),
          const Spacer(),
          Text(fmtTime(o.createdAt), style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Text('${o.fromRegion} → ${o.toRegion}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        Text([if (o.cargo.isNotEmpty) o.cargo, if (o.weightKg > 0) '${o.weightKg} kg', if (o.date.isNotEmpty) o.date].join(' · '), style: TextStyle(fontSize: 13, color: p.text.withValues(alpha: .85), fontWeight: FontWeight.w600)),
        if (o.address.isNotEmpty) Text(o.address, style: TextStyle(fontSize: 12, color: p.muted)),
        Text('${o.customerName} · ${o.phone}', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
        if (o.distanceKm != null || o.suggestedPrice != null || o.price != null) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (o.distanceKm != null) _Pill(Icons.route_rounded, fmtKm(o.distanceKm!), p.text, bg: p.bg),
            if (o.price != null)
              _Pill(Icons.handshake_outlined, "${tr('Kelishilgan')}: ${fmtPrice(o.price!)} so'm", p.success, bg: p.successSoft)
            else if (o.suggestedPrice != null)
              _Pill(Icons.auto_awesome_outlined, "${tr('Tavsiya')}: ${fmtPrice(o.suggestedPrice!)} so'm", p.accentText, bg: p.accentSoft),
          ]),
        ],
        const SizedBox(height: 10),
        Row(children: [
          IconBtn(Icons.phone_outlined, size: 42, bg: p.successSoft, color: p.success, onTap: () => launchUrl(Uri.parse('tel:${o.phone}'))),
          const SizedBox(width: 8),
          if (o.status == 'new') ...[
            Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42), foregroundColor: p.danger), onPressed: busy ? null : onReject, child: Text(tr('Rad etish')))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 42)), onPressed: busy ? null : onAccept, child: busy ? _spinner(p.muted) : Text(tr('Qabul qilish')))),
          ] else if (o.status == 'accepted')
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 42), backgroundColor: p.success, foregroundColor: Colors.white),
                icon: busy ? _spinner(p.muted) : const Icon(Icons.check_rounded, size: 18),
                label: Text(tr('Yetkazdim')),
                onPressed: busy ? null : onDone,
              ),
            ),
        ]),
      ]),
    );
  }
}

/// Kelishilgan narxni kiritish oynasi. Natija: narx (so'm), bo'sh bo'lsa 0, yopilsa null
class _PriceSheet extends StatefulWidget {
  final CargoOrder order;
  const _PriceSheet({required this.order});
  @override
  State<_PriceSheet> createState() => _PriceSheetState();
}

class _PriceSheetState extends State<_PriceSheet> {
  late final ctrl = TextEditingController(text: (widget.order.suggestedPrice ?? 0) > 0 ? '${widget.order.suggestedPrice}' : '');

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void submit() => Navigator.pop(context, int.tryParse(ctrl.text) ?? 0);

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final o = widget.order;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Kelishilgan narx'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
        const SizedBox(height: 4),
        Text('${o.fromRegion} → ${o.toRegion}${o.distanceKm != null ? ' · ${fmtKm(o.distanceKm!)}' : ''}', style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: ctrl,
          builder: (_, v, __) => TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(
              labelText: tr('Narx'),
              suffixText: "so'm",
              prefixIcon: const Icon(Icons.payments_outlined, size: 20),
              helperText: int.tryParse(v.text) != null ? "${fmtPrice(int.parse(v.text))} so'm" : null,
            ),
          ),
        ),
        if ((o.suggestedPrice ?? 0) > 0) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              avatar: Icon(Icons.auto_awesome_rounded, size: 16, color: p.accentText),
              label: Text("${tr('Tavsiya')}: ${fmtPrice(o.suggestedPrice!)} so'm"),
              onPressed: () => ctrl.text = '${o.suggestedPrice}',
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(tr("Narxni mijoz bilan telefonda kelishib oling. Bo'sh qoldirsangiz, narxsiz qabul qilinadi."), style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        FilledButton.icon(icon: const Icon(Icons.check_rounded, size: 18), label: Text(tr('Qabul qilish')), onPressed: submit),
      ]),
    );
  }
}
