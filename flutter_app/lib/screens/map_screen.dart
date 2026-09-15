import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shops_screen.dart';

/// Xarita qatlamlari: oddiy (OSM), sputnik (Esri), gibrid (sputnik + yozuvlar/yo'llar)
enum MapLayer { standard, satellite, hybrid }

/// Marshrut qadami (OSRM manevri): qayerda nima qilish kerak
class _Step {
  final String type; // turn, depart, arrive, roundabout, ...
  final String modifier; // left, right, slight left, ...
  final int exit;
  final String name;
  final double distance;
  final LatLng loc;
  _Step(this.type, this.modifier, this.exit, this.name, this.distance, this.loc);
}

class _Route {
  final List<LatLng> points;
  final double distanceM;
  final double durationS;
  final List<_Step> steps;
  _Route(this.points, this.distanceM, this.durationS, [this.steps = const []]);
}

/// To'liq ekran xarita: do'konlar, mening joyim, qatlamlar va marshrut (yo'nalish).
class MapScreen extends StatefulWidget {
  /// Pastki navigatsiya tabi sifatida ochilganda (panel yashirinadi, [onClose] bosh sahifaga qaytaradi)
  final bool inTab;
  final VoidCallback? onClose;

  /// Faqat shu do'konlarni ko'rsatib, ularga yaqinlashtirish (do'kon sahifasi, Sofia tavsiyasi)
  final List<Shop>? focus;
  const MapScreen({super.key, this.inTab = false, this.focus, this.onClose});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final ctrl = MapController();
  List<Shop> shops = [];
  LatLng? me;
  Shop? selected;
  MapLayer layer = MapLayer.standard;
  String profile = 'driving'; // driving | foot
  _Route? route;
  bool routing = false;
  bool locating = false;
  // Marker bosilganda xaritaning o'z onTap'i ham ishlaydi — uni e'tiborsiz qoldirish uchun
  DateTime _markerTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ---- Navigatsiya (ilova ichida, qadam-baqadam) ----
  bool navigating = false;
  bool arrived = false;
  int stepIndex = 0;
  StreamSubscription<Position>? _posSub;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
  Shop? _navShop;

  /// Marshrut keshi: bir xil so'rov qayta hisoblanmaydi (tez ochiladi)
  static final _routeCache = <String, _Route>{};
  static MapLayer _lastLayer = MapLayer.standard;

  @override
  void initState() {
    super.initState();
    layer = _lastLayer;
    final f = widget.focus;
    if (f != null && f.isNotEmpty) {
      shops = f;
      if (f.length == 1) selected = f.first;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit(shops.where((s) => s.lat != null).map((s) => LatLng(s.lat!, s.lon!)).toList()));
    } else {
      final cached = Api.instance.cached('/api/shops-map');
      if (cached != null) shops = (cached as List).map((e) => Shop.fromJson(e)).toList();
      Api.instance.get('/api/shops-map').then((r) {
        shops = (r as List).map((e) => Shop.fromJson(e)).toList();
        if (mounted) setState(() {});
      }).catchError((_) => null);
    }
    // Joylashuv ruxsati bor bo'lsa, xaritani darhol mening joyimga olib kelamiz
    _locate(silent: true);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  void _fit(List<LatLng> pts) {
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      ctrl.move(pts.first, 15);
      return;
    }
    ctrl.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.fromLTRB(60, 140, 60, 260)));
  }

  /// Haqiqiy joylashuv (GPS): avval oxirgi ma'lum joy, keyin aniq koordinata
  Future<LatLng?> _locate({bool silent = false}) async {
    if (locating) return me;
    if (!silent) setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (silent || !mounted) return null;
        showToast(context, tr("Joylashuv xizmati o'chiq. Sozlamalardan yoqing."), error: true);
        await Geolocator.openLocationSettings();
        return null;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        if (silent) return null;
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (!silent && mounted) {
          showToast(context, tr('Joylashuvga ruxsat berilmadi'), error: true);
          await Geolocator.openAppSettings();
        }
        return null;
      }
      if (perm == LocationPermission.denied) return null;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        me = LatLng(last.latitude, last.longitude);
        setState(() {});
        if (!silent || widget.focus == null) ctrl.move(me!, silent ? 14 : 16);
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)).timeout(const Duration(seconds: 15));
      if (!mounted) return me;
      me = LatLng(pos.latitude, pos.longitude);
      setState(() {});
      if (!silent) ctrl.move(me!, 16);
      return me;
    } catch (e) {
      if (!silent && mounted) showToast(context, e.toString(), error: true);
      return me;
    } finally {
      if (mounted && !silent) setState(() => locating = false);
    }
  }

  /// Marshrut: OSRM (bepul, tez) — mening joyimdan do'kongacha, xaritada chiziq
  Future<void> _buildRoute(Shop s) async {
    if (s.lat == null) return;
    final from = me ?? await _locate();
    if (from == null) {
      if (mounted) showToast(context, tr('Joylashuvga ruxsat berilmadi'), error: true);
      return;
    }
    final to = LatLng(s.lat!, s.lon!);
    final key = '$profile|${from.latitude.toStringAsFixed(4)},${from.longitude.toStringAsFixed(4)}|${to.latitude},${to.longitude}';
    if (_routeCache.containsKey(key)) {
      setState(() => route = _routeCache[key]);
      _fit([from, to, ...route!.points]);
      return;
    }
    setState(() {
      routing = true;
      route = null;
    });
    try {
      final res = await _fetchRoute(from, to);
      _routeCache[key] = res;
      if (!mounted) return;
      setState(() => route = res);
      if (navigating) {
        stepIndex = 0;
        ctrl.move(from, 17);
      } else {
        _fit([from, to, ...res.points]);
      }
    } catch (e) {
      // Internet yo'q yoki OSRM javob bermadi — to'g'ri chiziq bilan taxminiy masofa
      final d = const Distance().as(LengthUnit.Meter, from, to);
      final res = _Route([from, to], d, d / (profile == 'foot' ? 1.3 : 8.0));
      if (!mounted) return;
      setState(() => route = res);
      _fit([from, to]);
      showToast(context, tr('Marshrut topilmadi'), error: true);
    } finally {
      if (mounted) setState(() => routing = false);
    }
  }

  List<LatLng> _pts(List g) => g.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
  List<_Step> _steps(List st) => [
        for (final e in st)
          if (e['location'] != null)
            _Step((e['type'] ?? '').toString(), (e['modifier'] ?? '').toString(), (e['exit'] as num?)?.toInt() ?? 0, (e['name'] ?? '').toString(), (e['distance'] as num?)?.toDouble() ?? 0,
                LatLng((e['location'][1] as num).toDouble(), (e['location'][0] as num).toDouble())),
      ];

  /// 1) Bizning server (Redis kesh — bir xil yo'nalish darhol), 2) bo'lmasa to'g'ridan-to'g'ri OSRM
  Future<_Route> _fetchRoute(LatLng from, LatLng to) async {
    try {
      final j = await Api.instance.get('/api/route?from=${from.latitude},${from.longitude}&to=${to.latitude},${to.longitude}&profile=$profile').timeout(const Duration(seconds: 15));
      return _Route(_pts(j['geometry'] as List), (j['distance'] as num).toDouble(), (j['duration'] as num).toDouble(), _steps(j['steps'] as List? ?? const []));
    } catch (_) {
      final uri = Uri.parse('https://router.project-osrm.org/route/v1/$profile/${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson&steps=true');
      final r = await http.get(uri, headers: {'User-Agent': 'SalerAI/1.0'}).timeout(const Duration(seconds: 15));
      final j = jsonDecode(r.body);
      if (r.statusCode != 200 || j['code'] != 'Ok' || (j['routes'] as List).isEmpty) throw Exception(tr('Marshrut topilmadi'));
      final rt = j['routes'][0];
      final raw = ((rt['legs'] as List?)?.isNotEmpty == true ? rt['legs'][0]['steps'] as List? : null) ?? const [];
      final st = [
        for (final e in raw)
          {'type': e['maneuver']?['type'], 'modifier': e['maneuver']?['modifier'], 'exit': e['maneuver']?['exit'], 'location': e['maneuver']?['location'], 'name': e['name'], 'distance': e['distance']}
      ];
      return _Route(_pts(rt['geometry']['coordinates'] as List), (rt['distance'] as num).toDouble(), (rt['duration'] as num).toDouble(), _steps(st));
    }
  }

  // ---- Navigatsiya ----
  Future<void> _startNav(Shop s) async {
    if (route == null) return;
    _navShop = s;
    setState(() {
      navigating = true;
      arrived = false;
      stepIndex = 0;
      selected = s;
    });
    if (me != null) ctrl.move(me!, 17);
    await _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 3)).listen(_onPosition, onError: (_) {});
  }

  void _stopNav() {
    _posSub?.cancel();
    _posSub = null;
    ctrl.rotate(0);
    setState(() {
      navigating = false;
      arrived = false;
    });
  }

  /// Keyingi manevr (hozirgi qadamdan keyingi)
  _Step? get _nextStep {
    final st = route?.steps ?? const [];
    if (st.isEmpty) return null;
    return st[math.min(stepIndex + 1, st.length - 1)];
  }

  double get _remainingM {
    final r = route;
    if (r == null || me == null) return 0;
    if (r.steps.isEmpty) return const Distance().as(LengthUnit.Meter, me!, r.points.last);
    var sum = 0.0;
    for (var i = stepIndex + 1; i < r.steps.length; i++) {
      sum += r.steps[i].distance;
    }
    return sum + const Distance().as(LengthUnit.Meter, me!, _nextStep!.loc);
  }

  void _onPosition(Position pos) {
    if (!mounted || !navigating) return;
    me = LatLng(pos.latitude, pos.longitude);
    final r = route;
    if (r == null) return;
    // Kamera: mening joyim markazda, harakat yo'nalishi bo'yicha buriladi
    ctrl.move(me!, math.max(ctrl.camera.zoom, 16.5));
    if (pos.speed > 1.5 && pos.heading >= 0) ctrl.rotate(-pos.heading);
    // Keyingi manevrga yetildi — qadam oldinga
    final next = _nextStep;
    if (next != null) {
      final d = const Distance().as(LengthUnit.Meter, me!, next.loc);
      if (d < 22 && stepIndex < r.steps.length - 1) stepIndex++;
    }
    // Manzilga yetildi
    if (const Distance().as(LengthUnit.Meter, me!, r.points.last) < 30) {
      arrived = true;
      _posSub?.cancel();
    } else {
      // Marshrutdan chiqib ketildi (>70 m) — qayta hisoblash (15 soniyada bir marta)
      var minD = double.infinity;
      for (final pt in r.points) {
        final d = const Distance().as(LengthUnit.Meter, me!, pt);
        if (d < minD) minD = d;
      }
      if (minD > 70 && DateTime.now().difference(_lastReroute).inSeconds > 15 && !routing && _navShop != null) {
        _lastReroute = DateTime.now();
        _buildRoute(_navShop!);
      }
    }
    setState(() {});
  }

  /// Manevr matni va belgisi (o'zbekcha, tarjima lug'at orqali)
  (IconData, String) _instruction(_Step st) {
    final m = st.modifier;
    IconData icon;
    String text;
    switch (st.type) {
      case 'depart':
        icon = Icons.navigation_rounded;
        text = tr("Yo'lga chiqing");
      case 'arrive':
        icon = Icons.flag_rounded;
        text = tr('Manzilga yetib keldingiz');
      case 'roundabout':
      case 'rotary':
        icon = Icons.roundabout_left_rounded;
        text = st.exit > 0 ? '${tr('Aylanma yo\'lda')} ${st.exit}-${tr('chiqishdan chiqing')}' : tr("Aylanma yo'lga kiring");
      case 'merge':
      case 'on ramp':
        icon = Icons.merge_rounded;
        text = tr("Yo'lga qo'shiling");
      case 'off ramp':
        icon = Icons.fork_right_rounded;
        text = tr("Yo'ldan chiqing");
      case 'fork':
        icon = m.contains('left') ? Icons.fork_left_rounded : Icons.fork_right_rounded;
        text = m.contains('left') ? tr("Chapdagi yo'lni tanlang") : tr("O'ngdagi yo'lni tanlang");
      case 'end of road':
        icon = m.contains('left') ? Icons.turn_left_rounded : Icons.turn_right_rounded;
        text = m.contains('left') ? tr("Yo'l oxirida chapga buriling") : tr("Yo'l oxirida o'ngga buriling");
      default:
        switch (m) {
          case 'left':
            icon = Icons.turn_left_rounded;
            text = tr('Chapga buriling');
          case 'right':
            icon = Icons.turn_right_rounded;
            text = tr("O'ngga buriling");
          case 'slight left':
            icon = Icons.turn_slight_left_rounded;
            text = tr('Biroz chapga');
          case 'slight right':
            icon = Icons.turn_slight_right_rounded;
            text = tr("Biroz o'ngga");
          case 'sharp left':
            icon = Icons.turn_sharp_left_rounded;
            text = tr('Keskin chapga buriling');
          case 'sharp right':
            icon = Icons.turn_sharp_right_rounded;
            text = tr("Keskin o'ngga buriling");
          case 'uturn':
            icon = Icons.u_turn_left_rounded;
            text = tr('Orqaga qayting');
          default:
            icon = Icons.straight_rounded;
            text = tr("To'g'ri yuring");
        }
    }
    if (st.name.isNotEmpty && st.type != 'arrive') text = '$text — ${st.name}';
    return (icon, text);
  }

  /// Telefondagi navigator (Google Maps / Yandex) — ovozli yo'l-yo'riq uchun
  Future<void> _openNavigator(Shop s) async {
    final a = Uri.parse('google.navigation:q=${s.lat},${s.lon}&mode=${profile == 'foot' ? 'w' : 'd'}');
    if (await canLaunchUrl(a)) {
      await launchUrl(a, mode: LaunchMode.externalApplication);
      return;
    }
    final g = Uri.parse('geo:${s.lat},${s.lon}?q=${s.lat},${s.lon}(${Uri.encodeComponent(s.name)})');
    if (await canLaunchUrl(g)) {
      await launchUrl(g, mode: LaunchMode.externalApplication);
      return;
    }
    await launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${s.lat},${s.lon}'), mode: LaunchMode.externalApplication);
  }

  String _fmtDist(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
  String _fmtDur(double s) {
    final min = (s / 60).round();
    if (min < 60) return '$min ${tr('daqiqa')}';
    return '${min ~/ 60} ${tr('soat')} ${min % 60} ${tr('daqiqa')}';
  }

  void _setLayer(MapLayer l) {
    _lastLayer = l;
    setState(() => layer = l);
  }

  void _zoom(double d) => ctrl.move(ctrl.camera.center, (ctrl.camera.zoom + d).clamp(3, 19));

  List<Widget> _tiles() {
    const esri = 'https://server.arcgisonline.com/ArcGIS/rest/services';
    switch (layer) {
      case MapLayer.standard:
        return [TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'uz.saler.ai')];
      case MapLayer.satellite:
        return [TileLayer(urlTemplate: '$esri/World_Imagery/MapServer/tile/{z}/{y}/{x}', userAgentPackageName: 'uz.saler.ai')];
      case MapLayer.hybrid:
        return [
          TileLayer(urlTemplate: '$esri/World_Imagery/MapServer/tile/{z}/{y}/{x}', userAgentPackageName: 'uz.saler.ai'),
          TileLayer(urlTemplate: '$esri/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}', userAgentPackageName: 'uz.saler.ai'),
          TileLayer(urlTemplate: '$esri/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}', userAgentPackageName: 'uz.saler.ai'),
        ];
    }
  }

  void _showLayers() {
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Xarita turi'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
          const SizedBox(height: 12),
          Row(children: [
            for (final e in [
              (MapLayer.standard, Icons.map_outlined, tr('Oddiy'), const Color(0xFFE8ECF3)),
              (MapLayer.satellite, Icons.satellite_alt_rounded, tr('Sputnik'), const Color(0xFF2F3E33)),
              (MapLayer.hybrid, Icons.layers_rounded, tr('Gibrid'), const Color(0xFF3A4A5C))
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      _setLayer(e.$1);
                      Navigator.pop(c);
                    },
                    child: Column(children: [
                      Container(
                        height: 72,
                        width: double.infinity,
                        decoration: BoxDecoration(color: e.$4, borderRadius: BorderRadius.circular(16), border: Border.all(color: layer == e.$1 ? c.p.accentText : Colors.transparent, width: 2.5)),
                        child: Icon(e.$2, color: e.$1 == MapLayer.standard ? const Color(0xFF14161A) : Colors.white, size: 28),
                      ),
                      const SizedBox(height: 6),
                      Text(e.$3, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: layer == e.$1 ? c.p.accentText : c.p.text)),
                    ]),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    final dark = layer != MapLayer.standard;
    return Scaffold(
      body: Stack(children: [
        // ---- Xarita: butun ekran ----
        FlutterMap(
          mapController: ctrl,
          options: MapOptions(
            initialCenter: const LatLng(41.3111, 69.2797),
            initialZoom: 12,
            onTap: (_, __) {
              if (DateTime.now().difference(_markerTapAt).inMilliseconds < 400) return;
              setState(() => selected = null);
            },
          ),
          children: [
            ..._tiles(),
            if (route != null)
              PolylineLayer(polylines: [
                Polyline(points: route!.points, color: Colors.black.withValues(alpha: .25), strokeWidth: 9),
                Polyline(points: route!.points, color: const Color(0xFF2F80ED), strokeWidth: 5),
              ]),
            MarkerLayer(markers: [
              if (me != null)
                Marker(
                  point: me!,
                  width: 44,
                  height: 44,
                  child: Stack(alignment: Alignment.center, children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFF2F80ED).withValues(alpha: .18), shape: BoxShape.circle)),
                    Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                            color: const Color(0xFF2F80ED), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)])),
                  ]),
                ),
              for (final s in shops.where((s) => s.lat != null))
                Marker(
                  point: LatLng(s.lat!, s.lon!),
                  width: 52,
                  height: 62,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () {
                      _markerTapAt = DateTime.now();
                      setState(() => selected = s);
                      ctrl.move(LatLng(s.lat!, s.lon!), ctrl.camera.zoom < 14 ? 15 : ctrl.camera.zoom);
                    },
                    child: Column(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: selected?.id == s.id ? p.accent : Colors.transparent, width: 2.5),
                            boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black26, offset: Offset(0, 4))]),
                        padding: const EdgeInsets.all(3),
                        child: ShopAvatar(s, size: selected?.id == s.id ? 42 : 36),
                      ),
                      Icon(Icons.arrow_drop_down, color: selected?.id == s.id ? p.accent : Colors.white, size: 20),
                    ]),
                  ),
                ),
            ]),
          ],
        ),
        // ---- Navigatsiya: keyingi manevr kartasi ----
        if (navigating)
          Positioned(top: top + 10, left: 16, right: 16, child: _navCard())
        else
          // ---- Yuqori panel: yopish, sarlavha, qatlam ----
          Positioned(
            top: top + 10,
            left: 16,
            right: 16,
            child: Row(children: [
              _GlassBtn(widget.inTab ? Icons.close_rounded : Icons.arrow_back_ios_new_rounded, onTap: widget.inTab ? widget.onClose : () => Navigator.of(context).maybePop()),
              const SizedBox(width: 10),
              Expanded(
                child: _Glass(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Text(
                      widget.focus != null && widget.focus!.length == 1 ? widget.focus!.first.name : '${shops.where((s) => s.lat != null).length} ${tr("ta do'kon")}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _GlassBtn(Icons.layers_rounded, onTap: _showLayers),
            ]),
          ),
        // ---- O'ng tomon: masshtab va mening joyim ----
        Positioned(
          right: 16,
          top: top + 80,
          child: Column(children: [
            _GlassBtn(Icons.add_rounded, onTap: () => _zoom(1)),
            const SizedBox(height: 8),
            _GlassBtn(Icons.remove_rounded, onTap: () => _zoom(-1)),
            const SizedBox(height: 14),
            _GlassBtn(locating ? null : Icons.my_location_rounded, onTap: () => _locate(), accent: true),
          ]),
        ),
        // ---- Pastki panel: marshrut yoki tanlangan do'kon ----
        Positioned(
          left: 16,
          right: 16,
          bottom: 16 + bottom,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: navigating
                ? _navBar()
                : route != null && selected != null
                    ? _routePanel(selected!)
                    : selected != null
                        ? _shopPanel(selected!)
                        : (routing ? _routingPanel() : const SizedBox.shrink()),
          ),
        ),
        // Sputnik rejimida yozuvlar oq bo'lishi uchun status bar
        if (dark) Positioned(top: 0, left: 0, right: 0, height: top, child: Container(color: Colors.black.withValues(alpha: .25))),
      ]),
    );
  }

  Widget _routingPanel() => _Glass(
        key: const ValueKey('routing'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: context.p.accentText)),
            const SizedBox(width: 12),
            Text(tr("Yo'nalish hisoblanmoqda..."), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _shopPanel(Shop s) {
    final p = context.p;
    final d = me != null && s.lat != null ? const Distance().as(LengthUnit.Meter, me!, LatLng(s.lat!, s.lon!)) : null;
    return Container(
      key: ValueKey('shop-${s.id}'),
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 24, offset: const Offset(0, 10))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ShopAvatar(s, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(
                [if (s.description.isNotEmpty) s.description, '${s.productCount} ${tr('ta mahsulot')}', if (d != null) _fmtDist(d)].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600),
              ),
              if (s.address != null && s.address!.isNotEmpty) Text(s.address!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
          IconBtn(Icons.close_rounded, size: 34, bg: p.bg, onTap: () => setState(() => selected = null)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            flex: 3,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: p.accent),
              icon: const Icon(Icons.directions_rounded, size: 18),
              label: Text(tr("Yo'nalish"), maxLines: 1, overflow: TextOverflow.ellipsis),
              onPressed: routing ? null : () => _buildRoute(s),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: p.bg, side: BorderSide.none),
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: Text(tr("Do'kon")),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(s.id))),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _routePanel(Shop s) {
    final p = context.p;
    final r = route!;
    return Container(
      key: const ValueKey('route'),
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 24, offset: const Offset(0, 10))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(14)),
              child: Icon(profile == 'foot' ? Icons.directions_walk_rounded : Icons.directions_car_rounded, color: p.onAccent)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_fmtDur(r.durationS)} · ${_fmtDist(r.distanceM)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -.3)),
              Text('${tr("Yo'nalish")}: ${s.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
          IconBtn(Icons.close_rounded, size: 34, bg: p.bg, onTap: () => setState(() => route = null)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final e in [('driving', Icons.directions_car_rounded, tr('Mashina')), ('foot', Icons.directions_walk_rounded, tr('Piyoda'))])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: profile == e.$1,
                avatar: Icon(e.$2, size: 16, color: profile == e.$1 ? p.onDark : p.text),
                label: Text(e.$3),
                onSelected: (_) {
                  if (profile == e.$1) return;
                  setState(() => profile = e.$1);
                  _buildRoute(s);
                },
              ),
            ),
          const Spacer(),
          IconBtn(Icons.open_in_new_rounded, size: 40, bg: p.bg, onTap: () => _openNavigator(s)),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14), backgroundColor: p.accent),
            icon: const Icon(Icons.navigation_rounded, size: 16),
            label: Text(tr('Boshlash')),
            onPressed: () => _startNav(s),
          ),
        ]),
      ]),
    );
  }
}

extension _NavWidgets on _MapScreenState {
  Widget _navCard() {
    final p = context.p;
    final st = arrived ? null : _nextStep;
    final (icon, text) = st == null ? (Icons.flag_rounded, tr('Manzilga yetib keldingiz')) : _instruction(st);
    final dist = st == null || me == null ? null : const Distance().as(LengthUnit.Meter, me!, st.loc);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.dark, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3), blurRadius: 24, offset: const Offset(0, 10))]),
      child: Row(children: [
        Container(
            width: 56, height: 56, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: p.onAccent, size: 32)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (dist != null) Text(_fmtDist(dist), style: TextStyle(color: p.accent, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.5, height: 1.1)),
            Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .92), fontSize: 14, fontWeight: FontWeight.w700, height: 1.3)),
          ]),
        ),
      ]),
    );
  }

  Widget _navBar() {
    final p = context.p;
    final r = route!;
    final rem = _remainingM;
    final remS = r.distanceM > 0 ? r.durationS * rem / r.distanceM : 0.0;
    return Container(
      key: const ValueKey('nav'),
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 24, offset: const Offset(0, 10))]),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(arrived ? tr('Manzilga yetib keldingiz') : '${_fmtDur(remS)} · ${_fmtDist(rem)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -.3)),
            Text(_navShop?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
          ]),
        ),
        IconBtn(Icons.my_location_rounded, size: 40, bg: p.bg, color: p.accentText, onTap: () => me == null ? null : ctrl.move(me!, 17)),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14), backgroundColor: p.danger),
          onPressed: _stopNav,
          child: Text(tr('Tugatish')),
        ),
      ]),
    );
  }
}

/// Xarita ustidagi shisha panel
class _Glass extends StatelessWidget {
  final Widget child;
  const _Glass({super.key, required this.child});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
                color: context.p.card.withValues(alpha: .82),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: context.isDark ? .08 : .6)),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 14, offset: Offset(0, 4))]),
            child: child,
          ),
        ),
      );
}

class _GlassBtn extends StatelessWidget {
  final IconData? icon;
  final VoidCallback? onTap;
  final bool accent;
  const _GlassBtn(this.icon, {this.onTap, this.accent = false});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return _Glass(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 44,
            height: 44,
            child: icon == null
                ? Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: p.accent)))
                : Icon(icon, size: 22, color: accent ? p.accentText : p.text),
          ),
        ),
      ),
    );
  }
}
